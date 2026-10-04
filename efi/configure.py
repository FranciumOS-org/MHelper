#!/usr/bin/env python3
"""Add MHelper.kext to an OpenCore config.plist, or switch it off again.

Usage: python3 efi/configure.py install|uninstall IN_CONFIG OUT_CONFIG

install: Kernel -> Add gets an entry for MHelper.kext (from Darwin 22, Ventura),
at the end: it needs nothing but Apple's own kexts. An entry already there is
switched on and otherwise left alone, so running it twice changes nothing.
uninstall: the entry is switched off (not removed).

Nothing else in the file is touched.
"""
import plistlib
import sys

BUNDLE = 'MHelper.kext'
ENTRY = {
    'Arch': 'x86_64', 'BundlePath': BUNDLE, 'Comment': 'MHelper: ASUS keyboard, fans, modes',
    'Enabled': True, 'ExecutablePath': 'Contents/MacOS/MHelper', 'MaxKernel': '',
    'MinKernel': '22.0.0', 'PlistPath': 'Contents/Info.plist',
}


def install(config, changes):
    add = config['Kernel']['Add']
    for e in add:
        if e.get('BundlePath') == BUNDLE:
            if not e.get('Enabled'):
                e['Enabled'] = True
                changes.append('switched on ' + BUNDLE)
            return
    add.append(dict(ENTRY))
    changes.append('Kernel -> Add: ' + BUNDLE)


def uninstall(config, changes):
    for e in config['Kernel']['Add']:
        if e.get('BundlePath') == BUNDLE and e.get('Enabled'):
            e['Enabled'] = False
            changes.append('switched off ' + BUNDLE)


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ('install', 'uninstall'):
        sys.exit(__doc__)
    mode, src, dst = sys.argv[1:]
    with open(src, 'rb') as f:
        config = plistlib.load(f)
    changes = []
    (install if mode == 'install' else uninstall)(config, changes)
    with open(dst, 'wb') as f:
        plistlib.dump(config, f, sort_keys=False)
    for c in changes:
        print('  ' + c)
    if not changes:
        print('  config.plist: nothing to change')


if __name__ == '__main__':
    main()
