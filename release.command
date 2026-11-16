#!/bin/bash
# Publie une GitHub Release : DMG + empreinte SHA-256.
# C'est ce que lit la mise à jour automatique d'AudioLook (releases/latest → AudioLook.dmg).
# Prérequis : GitHub CLI (brew install gh, puis gh auth login).
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(grep -m1 'CFBundleShortVersionString' build.sh | sed -E 's/.*<string>([^<]+)<\/string>.*/\1/')
[ -n "$VERSION" ] || { echo "Version introuvable dans build.sh"; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI absent : brew install gh, puis gh auth login"; exit 1; }
if gh release view "$VERSION" >/dev/null 2>&1; then
  echo "La release $VERSION existe déjà — incrémente la version dans build.sh (CFBundleShortVersionString + CFBundleVersion)."
  exit 1
fi

echo "→ Build $VERSION"
# compile sans installer : la release ne touche pas à la copie de ~/Applications
NOINSTALL=1 ./build.sh
echo "→ DMG"
APP="${TMPDIR:-/tmp}/AudioLook-build/AudioLook.app" ./makedmg.command
shasum -a 256 AudioLook.dmg | awk '{print $1"  AudioLook.dmg"}' > AudioLook.dmg.sha256
cat AudioLook.dmg.sha256

# Notes = section « ## $VERSION » du CHANGELOG
NOTES=$(awk -v v="## $VERSION " 'index($0, v) == 1 {f=1; next} /^## / && f {exit} f' CHANGELOG.md)
[ -n "$NOTES" ] || NOTES="AudioLook $VERSION"

echo "→ Release GitHub $VERSION"
# le DMG du dépôt est celui que le README propose : il part dans le même commit que la release
git add AudioLook.dmg
git diff --cached --quiet || git commit -m "Release $VERSION"
git push origin HEAD
gh release create "$VERSION" AudioLook.dmg AudioLook.dmg.sha256 \
  --title "AudioLook $VERSION" --notes "$NOTES"
echo "✓ Publiée."
