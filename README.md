# MHelper

**G-Helper for macOS.** Keyboard backlight and RGB, performance modes, fan speeds,
battery charge limit, panel overdrive and dGPU Eco mode for ASUS laptops running
macOS (Hackintosh), from a small menu-bar app.

MHelper talks to the same firmware interface (ASUS WMI, `WMNB` on `ATKD`) as
Linux's `asus-wmi` driver and G-Helper on Windows. It works alongside AsusSMC.

| | |
|---|---|
| Performance | Silent / Balanced / Turbo |
| Fans | CPU and GPU fan RPM, live |
| Keyboard | Brightness 0–3; RGB colour (wheel, hex, swatches), Static / Breathing / Colour cycle / Strobe, speed; lit while asleep; save to firmware |
| Battery | Charge limit (60 / 80 / 100 %) |
| Display & GPU | Panel overdrive; Eco mode (NVIDIA dGPU off) |
| ROG mouse | DPI slots, polling rate, angle snapping, logo/wheel lighting (Mouse tab; no kext needed) |

The app only shows what your laptop's firmware reports, so it adapts to each model.
Settings are reapplied at login and after sleep.

## Tested

| Laptop | Status |
|---|---|
| ASUS TUF Gaming A15 FA507NU (2023) | Everything above works. Eco mode not yet tested. |
| ROG Strix Impact III (wired, `0b05:1a88`) | DPI, polling, angle snapping, lighting |

Other ASUS laptops that Linux `asus-wmi` supports (TUF, ROG, Zenbook, Vivobook) should
work for the features their firmware has. Please report your model: see
[Reporting a laptop](#reporting-a-laptop).

## Requirements

- macOS 13 Ventura or newer (Intel/AMD Hackintosh, x86_64)
- An ASUS laptop with the `ATKD` ACPI device (every recent ASUS laptop has it)
- OpenCore, to load the kext at boot

## Install

Download `MHelper-<version>.dmg` (or `.zip`) from [Releases](../../releases). Inside:
`MHelper.app`, `MHelper.kext`, `How to install.txt`, and an `Extras` folder.

### 1. The kext, with OpenCore

**Automatic:** `sudo Extras/install.sh` finds your OpenCore EFI, copies `MHelper.kext`
to `EFI/OC/Kexts`, adds it to `config.plist` (backup: `config.plist.pre-mhelper`) and
asks you to restart. `sudo Extras/uninstall.sh` switches it off again. If OpenCore is on
more than one drive, it lists them and asks which one.

**By hand:**

1. Copy `MHelper.kext` to `EFI/OC/Kexts/`.
2. In `config.plist`, add to **Kernel → Add**:

   | Key | Value |
   |---|---|
   | `Arch` | `x86_64` |
   | `BundlePath` | `MHelper.kext` |
   | `Enabled` | `true` |
   | `ExecutablePath` | `Contents/MacOS/MHelper` |
   | `PlistPath` | `Contents/Info.plist` |
   | `MinKernel` | `22.0.0` |

   (ProperTree: *OC Snapshot* adds it for you.) No Lilu needed.
3. Reboot.

To try it first without touching your EFI (needs unsigned kexts allowed, for example
`csr-active-config` `0x03`; it is gone after a reboot):

    sudo Extras/load.sh

### 2. The app

Move `MHelper.app` to **Applications** and open it. The app isn't notarised: the
first time, right-click it → **Open** → **Open**, or run

    xattr -dr com.apple.quarantine /Applications/MHelper.app

It lives in the menu bar (no Dock icon). Tick **Open at login** in its panel.

### Command line

`mhelper` does the same from Terminal:

    mhelper                          # status
    mhelper mode silent|balanced|turbo
    mhelper kbd 0-3
    mhelper color ff8800 [static|breathe|cycle|strobe] [0-2] [--save]
    mhelper lights <boot> <awake> <sleep> <keyboard> [--save]
    mhelper charge 80
    mhelper overdrive 0|1
    mhelper eco 0|1                  # 1 = NVIDIA dGPU off

## Safety

- Loading MHelper changes nothing. It only reads which features the firmware has;
  every change comes from you.
- Colours aren't stored in the firmware unless you choose **Save to firmware**
  (or `--save`): a reboot undoes any experiment.
- **Eco mode** powers the NVIDIA GPU off at firmware level. It stays off, also in
  Windows, until you turn Eco off again; a reboot may be needed for it to come back.
  MHelper refuses Eco while the GPU MUX is in dGPU-only mode, like Linux does.
- MHelper never changes the GPU MUX (dGPU-only would mean a black screen in macOS)
  and doesn't touch CPU/GPU power limits.

## Reporting a laptop

`MHelperProbe.kext` (in the zip) only reads: it lists every ASUS WMI feature your
firmware reports. Load it and open an issue with the output and your model:

    sudo Extras/load.sh probe

## Building

Command Line Tools are enough (no Xcode):

    make            # MHelper.kext, mhelper, MHelper.app in build/out
    make probe      # MHelperProbe.kext
    make release    # build/release/MHelper-<version>.dmg and .zip

## Not working yet

- Changing the refresh rate (needs a GPU driver for the iGPU)
- Fan curves, the Fn+F5 fan key, macOS's own keyboard-brightness keys
- ROG keyboards with Aura over USB

## Credits and licence

The protocol (method and device IDs, value encodings, safety checks) comes from the
Linux kernel's [`asus-wmi`](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-wmi.c)
driver and [G-Helper](https://github.com/seerge/g-helper); MHelper's code is its own.
Built with acidanthera's [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK)
(APSL 2.0, in `third_party/`).

MHelper is GPL-2.0. It isn't affiliated with or endorsed by ASUS; "ASUS", "TUF" and
"ROG" are ASUS trademarks, used only to say which laptops this is for.
