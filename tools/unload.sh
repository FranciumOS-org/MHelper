#!/bin/sh
# Unload the probe kext. Run by a person: sudo tools/unload.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo: sudo tools/unload.sh" >&2; exit 1; }
kmutil unload -b com.asuswmicontrol.probe
echo "unloaded com.asuswmicontrol.probe"
