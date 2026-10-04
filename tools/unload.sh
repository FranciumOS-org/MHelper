#!/bin/sh
# Unload a kext. Run by a person:
#   sudo tools/unload.sh          AsusWMIControl.kext
#   sudo tools/unload.sh probe    AsusWMIProbe.kext
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo tools/unload.sh" >&2; exit 1; }
id=com.asuswmicontrol.driver
[ "${1:-}" = probe ] && id=com.asuswmicontrol.probe
kmutil unload -b "$id"
echo "unloaded $id"
