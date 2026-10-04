#!/bin/sh
# Install MHelper.kext into the OpenCore EFI and add it to config.plist, so it
# loads at every boot. Run it again to update the kext.
#
#   sudo efi/install.sh [EFI volume: a mounted path, a partition UUID or diskNsM]
#
# Without an argument it finds the volume with OpenCore on it; if there is
# more than one it asks which. The config as it was before the first install
# is kept as EFI/OC/config.plist.pre-mhelper. Takes effect at the next
# restart; efi/uninstall.sh switches it off again.
set -eu

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo $0" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"

# The kext: next to this folder (release: Extras/ beside MHelper.kext) or a build
ours=
for d in "$here/.." "$here/../build/out" "$here"; do
    if [ -f "$d/MHelper.kext/Contents/MacOS/MHelper" ]; then
        ours="$(cd "$d" && pwd)/MHelper.kext"
        break
    fi
done
[ -n "$ours" ] || { echo "MHelper.kext not found next to $here; in a checkout run: make" >&2; exit 1; }

. "$here/find_efi.sh"
find_efi "${1:-}"
oc="$EFI_MOUNT/EFI/OC"
echo "OpenCore: $oc ($EFI_PART)"

tmp="$(mktemp -t config.plist)"
trap 'rm -f "$tmp"' EXIT
python3 "$here/configure.py" install "$oc/config.plist" "$tmp"
plutil -lint "$tmp" >/dev/null || { echo "the new config does not parse; nothing was changed" >&2; exit 1; }
efi_room "$ours"

backup="$oc/config.plist.pre-mhelper"
[ -e "$backup" ] || { cp "$oc/config.plist" "$backup"; echo "saved the config as it was: $backup"; }

export COPYFILE_DISABLE=1
rm -rf "$oc/Kexts/MHelper.kext"
cp -R -X "$ours" "$oc/Kexts/"
echo "  copied MHelper.kext ($(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ours/Contents/Info.plist"))"
# no AppleDouble files on the FAT volume: OpenCore would try to read them
find "$oc/Kexts" -name '._*' -delete 2>/dev/null || true

cp "$tmp" "$oc/config.plist"
sync
echo "done. Restart for it to take effect."
echo "to switch it off: sudo efi/uninstall.sh"
