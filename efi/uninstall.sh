#!/bin/sh
# Switch MHelper.kext off in the OpenCore EFI: its config.plist entry is
# disabled, the file stays. sudo efi/install.sh switches it on again.
#
#   sudo efi/uninstall.sh [EFI volume: a mounted path, a partition UUID or diskNsM]
set -eu

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo $0" >&2; exit 1; }
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/find_efi.sh"
find_efi "${1:-}"
oc="$EFI_MOUNT/EFI/OC"
echo "OpenCore: $oc ($EFI_PART)"

tmp="$(mktemp -t config.plist)"
trap 'rm -f "$tmp"' EXIT
python3 "$here/configure.py" uninstall "$oc/config.plist" "$tmp"
plutil -lint "$tmp" >/dev/null || { echo "the new config does not parse; nothing was changed" >&2; exit 1; }
cp "$oc/config.plist" "$oc/config.plist.before-mhelper-uninstall"
cp "$tmp" "$oc/config.plist"
sync
echo "done (the config before this is kept as config.plist.before-mhelper-uninstall). Restart."
