# AsusWMIControl — notes for Claude

macOS (hackintosh) port of the Linux `asus-wmi` controls: keyboard backlight and
TUF RGB, performance/fan modes, fan RPM, dGPU Eco mode, charge limit, panel
overdrive. Goal: work on every ASUS laptop Linux asus-wmi supports, like G-Helper,
and be released. Plan and milestones: docs/PLAN.md.

## Machine

ASUS TUF A15 FA507NU (Ryzen 7 7735HS, RTX 4050), macOS 15 hackintosh, OpenCore
DEBUG build, no GPU acceleration. AsusSMC 1.4.1 is loaded and owns ATKD
(`IsKeyboardBacklightSupported = No`). Development and testing on the same machine.
Same owner as ~/Developer/AirPort_RTW89 (see its CLAUDE.md for the EFI rules).

## How it works

All features go through one ACPI call: `WMxx` (found via `_WDG` for GUID
97845ED0-4E6D-11DE-8A39-0800200C9A66; `WMNB` on ASUS) with Arg0 = 0,
Arg1 = method ID (DSTS/DEVS/...), Arg2 = 24-byte `bios_args` buffer. IDs in
include/asus_wmi_ids.h, taken from Linux asus-wmi.h / asus-wmi.c. Our kexts use
their own IOMatchCategory so they attach next to AsusSMC.

## Rules

- **Always ask before loading or unloading a kext.** The user runs
  `sudo tools/load.sh` / `sudo tools/unload.sh`; Claude never does, never asks for
  or stores the password. Commit before any load.
- Read-only (DSTS) before any write. A DEVS call only for a device DSTS reports
  present, with the Linux value encoding.
- **Never set GPU_MUX to 0 (dGPU only)** from macOS: black screen. Follow Linux's
  checks for DGPU vs MUX vs EGPU. No PPT/TGP writes without explicit limits from DSTS.
- Clean-room: use Linux and G-Helper for the protocol (IDs, encodings), write our
  own code. Project is GPL-2.0.
- Build: `make` (kext + asusctl), `make probe`; check imports with `kmutil libraries -p build/out/<kext> --undef-symbols`.
