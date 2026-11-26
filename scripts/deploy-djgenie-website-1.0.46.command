#!/bin/bash
set -euo pipefail
PROJECT="/Users/Anwaar/HumbleStack/DJGenieWeb-p04-deploy"
cd "$PROJECT" || { echo "Website folder not found: $PROJECT"; exit 1; }
if [ ! -f src/lib/desktop/release.ts ] || [ ! -f firebase.json ] || [ ! -f package.json ]; then
  echo "STOP: This is not the DJ Genie website project. Nothing was deployed."
  exit 1
fi
node <<'JS'
const fs = require('fs');
const pathname = 'src/lib/desktop/release.ts';
let source = fs.readFileSync(pathname, 'utf8');
const base = 'https://github.com/AnwaarHimself/dj-genie-studio-releases/releases/download';
const releases = [
  { name: 'MAC_DESKTOP_RELEASE', file: 'DJ.Genie.Studio-1.0.46-universal.dmg', architecture: 'Universal (Apple Silicon + Intel)' },
  { name: 'CATALINA_DESKTOP_RELEASE', file: 'DJ.Genie.Studio-1.0.46-catalina-x64.dmg', architecture: 'Intel x64 (macOS Catalina 10.15+)' }
];
for (const release of releases) {
  const regex = new RegExp('(' + 'export\\s+const\\s+' + release.name + '\\b[^=]*=\\s*\\{' + ')([\\s\\S]*?)(\\n\\};)');
  const found = source.match(regex);
  if (!found) { console.error('Missing ' + release.name + '; refusing to deploy an uncertain site.'); process.exit(1); }
  let block = found[2];
  const changes = [
    [/\bversion:\s*["']1\.0\.\d+["']/, 'version: "1.0.46"'],
    [/\bdownloadUrl:\s*[^\n]+,/, 'downloadUrl: "' + base + '/v1.0.46/' + release.file + '",'],
    [/\bfilename:\s*[^\n]+,/, 'filename: "' + release.file + '",'],
    [/\breleaseDate:\s*["'][^"']+["']/, 'releaseDate: "2026-11-25"'],
    [/\barchitecture:\s*["'][^"']+["']/, 'architecture: "' + release.architecture + '"'],
    [/\bsigned:\s*(?:true|false)/, 'signed: false'],
    [/\bnotarized:\s*(?:true|false)/, 'notarized: false']
  ];
  for (const [find, replace] of changes) {
    if (!find.test(block)) { console.error('Missing setting for ' + release.name + ': ' + find + '; refusing partial deploy.'); process.exit(1); }
    block = block.replace(find, replace);
  }
  source = source.replace(regex, found[1] + block + found[3]);
}
source = source.replace(/DJ\.Genie\.Studio-1\.0\.45-universal\.dmg/g, 'DJ.Genie.Studio-1.0.46-universal.dmg');
source = source.replace(/DJ\.Genie\.Studio-1\.0\.45-catalina-x64\.dmg/g, 'DJ.Genie.Studio-1.0.46-catalina-x64.dmg');
source = source.replace(/Newer Macs — macOS 11\+ \(2020 or newer\)/g, 'Mac (Intel + Apple Silicon) — Version 1.0.46');
source = source.replace(/Older Macs — macOS 10\.15 \(2019 or earlier Macs\)/g, 'Catalina Intel — Version 1.0.46');
fs.writeFileSync(pathname, source);
const pagePath = 'src/app/download/page.tsx';
if (fs.existsSync(pagePath)) {
  let page = fs.readFileSync(pagePath, 'utf8');
  page = page.replace(/recommended modern installer is notarized/g, 'latest modern installer is unsigned');
  page = page.replace(/ · Signed and\s*\n\s*notarized by Apple/g, ' · Unsigned');
  page = page.replace(/ · Signed and notarized by Apple/g, ' · Unsigned');
  page = page.replace(/ · Signed and notarized/g, ' · Unsigned');
  fs.writeFileSync(pagePath, page);
}
console.log('Prepared website labels and public download URLs for 1.0.46.');
JS
if [ ! -d node_modules ]; then npm ci; fi
npm run build
if ! npx -y firebase-tools@latest projects:list --json > /dev/null 2>&1; then
  echo "Please sign into the Google account owning Firebase project dj-genie."
  npx -y firebase-tools@latest login
fi
npx -y firebase-tools@latest deploy --only apphosting:djgenie-web --project dj-genie
printf '\nDeploy requested. Checking website version now:\n'
response=$(curl -fsSL --max-time 30 https://djgeniestudio.com/api/releases/desktop || true)
if [[ "$response" == *"1.0.46"* ]]; then
  echo "SUCCESS: Live site API reports 1.0.46."
else
  echo "Deployment command finished. Live site may need rollout/caching time; check App Hosting > Rollouts and refresh the website."
fi
