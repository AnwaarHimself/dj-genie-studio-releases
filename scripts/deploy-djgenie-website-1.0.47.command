#!/bin/bash
set -euo pipefail
PROJECT="/Users/Anwaar/HumbleStack/DJGenieWeb-p04-deploy"
cd "$PROJECT" || { echo "Website folder not found."; exit 1; }

if [ ! -f src/lib/desktop/release.ts ] || [ ! -f src/app/download/page.tsx ] || [ ! -f package.json ]; then
  echo "STOP: DJ Genie website files are missing. Nothing deployed."
  exit 1
fi

BASE="https://github.com/AnwaarHimself/dj-genie-studio-releases/releases/download/v1.0.47"
for ASSET in DJ.Genie.Studio-1.0.47-universal.dmg DJ.Genie.Studio-1.0.47-catalina-x64.dmg; do
  if ! curl -fsSI -L --max-time 60 "$BASE/$ASSET" >/dev/null; then
    echo "STOP: The installer is not publicly downloadable: $ASSET"
    exit 1
  fi
done

python3 - <<'PY'
from pathlib import Path
import re

release_path = Path("src/lib/desktop/release.ts")
source = release_path.read_text()
versions = {
    "MAC_DESKTOP_RELEASE": ("DJ.Genie.Studio-1.0.47-universal.dmg", "Universal (Apple Silicon + Intel, macOS 11+)"),
    "INTEL_DESKTOP_RELEASE": ("DJ.Genie.Studio-1.0.47-universal.dmg", "Universal (Apple Silicon + Intel, macOS 11+)"),
    "CATALINA_DESKTOP_RELEASE": ("DJ.Genie.Studio-1.0.47-catalina-x64.dmg", "Intel x64 (macOS Catalina 10.15+)"),
}
source = re.sub(r'const MAC_DMG_FILENAME = "[^"]+";', 'const MAC_DMG_FILENAME = "DJ.Genie.Studio-1.0.47-universal.dmg";', source)
source = re.sub(r'const CATALINA_DMG_FILENAME = "[^"]+";', 'const CATALINA_DMG_FILENAME = "DJ.Genie.Studio-1.0.47-catalina-x64.dmg";', source)

dollar = chr(36)
tick = chr(96)
for name, (filename, architecture) in versions.items():
    pattern = r'(export const ' + name + r': DesktopRelease = \{)(.*?)(\n\};)'
    match = re.search(pattern, source, re.S)
    if not match:
        raise SystemExit("STOP: Missing release definition " + name)
    block = match.group(2)
    link = 'downloadUrl: ' + tick + dollar + '{GITHUB_RELEASES_BASE}/v1.0.47/' + dollar + '{encodeURIComponent("' + filename + '")}' + tick + ','
    for regex, replacement in [
        (r'version: "[^"]+"', 'version: "1.0.47"'),
        (r'downloadUrl: [^\n]+', link),
        (r'filename: [^\n]+', 'filename: "' + filename + '",'),
        (r'architecture: "[^"]+"', 'architecture: "' + architecture + '"'),
        (r'releaseDate: "[^"]+"', 'releaseDate: "2026-11-26"'),
    ]:
        if not re.search(regex, block):
            raise SystemExit("STOP: Missing " + regex + " for " + name)
        block = re.sub(regex, lambda _: replacement, block, count=1)
    source = source[:match.start()] + match.group(1) + block + match.group(3) + source[match.end():]
source = source.replace('Apple Silicon Macs (M1, M2, M3, M4+) — 1.0.46', 'Mac (Intel + Apple Silicon) — 1.0.47')
source = source.replace('Apple Silicon Macs — 1.0.46', 'Mac (Intel + Apple Silicon) — 1.0.47')
release_path.write_text(source)

page = Path("src/app/download/page.tsx")
page.write_text("""import Link from "next/link";
import { MAC_DESKTOP_RELEASE, CATALINA_DESKTOP_RELEASE } from "@/lib/desktop/release";

export default function DownloadPage() {
  return (
    <div className="home">
      <section className="panel hero">
        <img className="hero-logo" src="/brand/dj-genie-logo.png"
          alt="DJ Genie Studio" width={160} height={106} />
        <h1>Download DJ Genie Studio 1.0.47</h1>
        <p>What's new: Track Rescue, Duplicate Cleaner, crate tools and music
          editing are now protected by subscription. Track Rescue also shows
          full track names in a wider list.</p>
        <p>Free to download and browse your library. A membership is required
          to use the DJ Genie tools.</p>
        <div className="hero-actions">
          <span className="hero-download-option">
            <a href={MAC_DESKTOP_RELEASE.downloadUrl} className="button-link hero-download-cta">
              Mac (Intel + Apple Silicon) — Download 1.0.47
            </a>
            <span className="muted hero-download-note">macOS 11 or newer</span>
          </span>
          <span className="hero-download-option">
            <a href={CATALINA_DESKTOP_RELEASE.downloadUrl} className="button-link hero-download-cta">
              Older Intel Mac — Download 1.0.47
            </a>
            <span className="muted hero-download-note">macOS Catalina 10.15 (Intel only)</span>
          </span>
        </div>
        <p className="muted">Installers are unsigned. If macOS blocks opening,
          use Privacy &amp; Security → Open Anyway. Catalina includes
          missing-track search; automatic restore is disabled.</p>
      </section>
      <section className="panel">
        <h2>Need help installing?</h2>
        <Link href="/installation-help" className="button-link secondary">Installation Help</Link>
      </section>
    </div>
  );
}
""")

hero_path = Path("src/components/home/hero-ctas.tsx")
if hero_path.exists():
    hero = hero_path.read_text()
    hero = hero.replace("INTEL_DESKTOP_RELEASE,", "CATALINA_DESKTOP_RELEASE,")
    hero = hero.replace("INTEL_DESKTOP_RELEASE.downloadUrl", "CATALINA_DESKTOP_RELEASE.downloadUrl")
    hero = hero.replace("Apple Silicon (M1 or newer) — Download 1.0.46", "Mac (Intel + Apple Silicon) — Download 1.0.47")
    hero = hero.replace("Intel Mac — Download 1.0.46", "Older Intel Mac — Download 1.0.47")
    hero = hero.replace("macOS 11+ · Catalina 10.15 repair pending", "macOS 10.15 (Intel only)")
    hero = hero.replace("1.0.46", "1.0.47")
    hero_path.write_text(hero)

print("Prepared v1.0.47 universal and Catalina download links.")
PY

npm run build
if ! npx -y firebase-tools@latest projects:list --json >/dev/null 2>&1; then
  npx -y firebase-tools@latest login
fi
npx -y firebase-tools@latest deploy --only apphosting:djgenie-web --project dj-genie

if curl -fsSL --max-time 45 https://djgeniestudio.com/api/releases/desktop | grep -q "1.0.47"; then
  echo "SUCCESS: Live DJ Genie website reports 1.0.47."
else
  echo "Firebase deploy finished, but the website has not reported 1.0.47 yet. Check App Hosting rollout."
fi
