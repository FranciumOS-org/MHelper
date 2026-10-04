#!/bin/sh
# Unload a kext. Run by a person:
#   sudo tools/unload.sh          MHelper.kext
#   sudo tools/unload.sh probe    MHelperProbe.kext
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo tools/unload.sh" >&2; exit 1; }
id=org.franciumos.mhelper.driver
[ "${1:-}" = probe ] && id=org.franciumos.mhelper.probe
kmutil unload -b "$id"
echo "unloaded $id"
