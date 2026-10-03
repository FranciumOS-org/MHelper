# AsusWMIControl

Keyboard backlight and RGB, performance modes, fan speeds, dGPU Eco mode and
battery charge limit for ASUS laptops running macOS (hackintosh), using the same
firmware interface as Linux `asus-wmi` and G-Helper.

Status: M0, a read-only probe. See docs/PLAN.md.

    make probe
    sudo tools/load.sh        # loads the probe, prints what your laptop supports
    sudo tools/unload.sh

GPL-2.0.
