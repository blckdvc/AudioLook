#!/bin/bash
cd "$(dirname "$0")"
APP="${APP:-$HOME/Applications/AudioLook.app}"   # APP=<chemin> pour empaqueter un build non installé
[ -d "$APP" ] || { echo "AudioLook.app introuvable dans ~/Applications (lance d'abord ./build.sh)"; exit 1; }
STAGE=".dmgstage"
rm -rf "$STAGE" AudioLook.dmg audiolook.dmg LoopLook.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE"/
ln -s /Applications "$STAGE"/Applications
[ -f packaging/readme-first-launch.txt ] && cp packaging/readme-first-launch.txt "$STAGE/Read me - first launch.txt"
xattr -cr "$STAGE/AudioLook.app" 2>/dev/null || true
hdiutil create -volname "AudioLook" -srcfolder "$STAGE" -ov -format UDZO AudioLook.dmg
rm -rf "$STAGE"
echo "✓ AudioLook.dmg créé (racine du repo)"
