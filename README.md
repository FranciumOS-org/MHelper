# AsusWMIControl

Keyboard backlight and RGB, performance modes, fan speeds, dGPU Eco mode and
battery charge limit for ASUS laptops running macOS (hackintosh), using the same
firmware interface as Linux `asus-wmi` and G-Helper.

Status: kext + asusctl work on a TUF A15 FA507NU; menu-bar app in progress. See docs/PLAN.md.

    make                      # kext, asusctl, menu-bar app
    make probe
    sudo tools/load.sh        # loads the probe, prints what your laptop supports
    sudo tools/unload.sh

GPL-2.0.
