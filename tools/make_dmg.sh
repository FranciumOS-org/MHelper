#!/bin/sh
# Styled DMG: MHelper.app → Applications on top, the kext row below.
#
#   tools/make_dmg.sh <release folder> <out.dmg> <volume name>
#
# Finder lays out the window (AppleScript), so this needs a logged-in session;
# the first run may ask to allow Terminal to control Finder.
set -eu

src=$1; out=$2; vol=$3
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'hdiutil detach -quiet "/Volumes/$vol" 2>/dev/null || true; rm -rf "$work"' EXIT

# Background (1x + 2x in one TIFF so Retina screens stay sharp)
swift "$here/dmg_background.swift" "$work/bg.png" "$work/bg@2x.png"
tiffutil -cathidpicheck "$work/bg.png" "$work/bg@2x.png" -out "$work/background.tiff" 2>/dev/null

stage="$work/stage"
cp -R "$src" "$stage"
ln -s /Applications "$stage/Applications"
mkdir "$stage/.background"
cp "$work/background.tiff" "$stage/.background/background.tiff"

hdiutil detach -quiet "/Volumes/$vol" 2>/dev/null || true
hdiutil create -quiet -volname "$vol" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"

osascript <<OSA
tell application "Finder"
    tell disk "$vol"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 562}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 96
        set text size of opts to 12
        set background picture of opts to file ".background:background.tiff"
        set position of item "MHelper.app" of container window to {170, 150}
        set position of item "Applications" of container window to {470, 150}
        set position of item "MHelper.kext" of container window to {170, 345}
        set position of item "How to install.txt" of container window to {320, 345}
        set position of item "Extras" of container window to {470, 345}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

# Let Finder write .DS_Store before detaching; drop the volume's event log
sync; sleep 2
rm -rf "/Volumes/$vol/.fseventsd"
hdiutil detach -quiet "/Volumes/$vol"
rm -f "$out"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$out"
echo "built $out"
