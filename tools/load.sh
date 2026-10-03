#!/bin/sh
# Stage a built kext as root:wheel and load it into the running kernel.
#
#   sudo tools/load.sh [probe]
#
# Only a person runs this: a bad load can panic the machine. Nothing is
# installed; the staged copy lives under /private/var/tmp and is gone after
# a reboot.
set -eu

[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo tools/load.sh" >&2; exit 1; }

name=AsusWMIProbe; id=com.asuswmicontrol.probe
src="$(cd "$(dirname "$0")/.." && pwd)/build/out/$name.kext"
stage=/private/var/tmp/AsusWMIControl.stage
[ -d "$src" ] || { echo "no kext at $src; run: make probe" >&2; exit 1; }

if kmutil showloaded 2>/dev/null | grep -q "$id"; then
    echo "$id is already loaded; run sudo tools/unload.sh first" >&2
    exit 1
fi

rm -rf "$stage"
mkdir -p "$stage"
cp -R "$src" "$stage/"
chown -R root:wheel "$stage"
chmod -R go-w "$stage"
sync

echo "loading $stage/$name.kext"
kmutil load -p "$stage/$name.kext"
sleep 3
echo "--- kernel log"
/usr/bin/log show --last 1m --style compact --predicate 'eventMessage CONTAINS "AsusWMIProbe"' | tail -60
echo "--- registry"
ioreg -r -c AsusWMIProbe -k AsusWMI -w0 | grep -A60 '"AsusWMI"' | tr ',' '\n'
