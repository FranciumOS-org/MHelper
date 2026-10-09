# Plan

## M0 — probe (read-only)            ✓ 2026-10-03: 17/39 IDs present on FA507NU
`MHelperProbe.kext` (class AsusWMIProbe): finds the WMI method via `_WDG`, calls SPEC, SFUN and
DSTS for every ID in include/asus_wmi_ids.h, logs and publishes the result
(`ioreg -r -c AsusWMIProbe -k AsusWMI -w0`). Tells us what this firmware supports.

## M1 — MHelper.kext (class AsusWMIControl) + IOUserClient   ✓ 2026-10-04 on FA507NU
Works: kbd level, RGB colour/effects, Silent/Turbo, fan RPM, charge limit.
Not yet tested: reapply after wake, Eco, overdrive write, RGB power states.

- Runtime feature detection (DSTS presence), like Linux: UI shows only what exists.
- Keyboard: brightness 0–3 (`0x80 | level` on KBD_BACKLIGHT); TUF RGB
  (`cmd | mode<<8 | r<<16 | g<<24`, `b | speed<<8`; cmd 0xb3 set / 0xb4 save;
  speed 0xe1/0xeb/0xf5; MODE or MODE2 whichever is present); RGB power states.
- Thermal policy: TUF/ROG order (0 bal, 1 turbo, 2 silent) or Vivo order.
- Fan RPM (CPU/GPU_FAN_CTRL, low 16 bits) — optionally exported via VirtualSMC.
- dGPU Eco (DGPU=1) with Linux's MUX/eGPU checks. MUX read-only.
- Charge limit (RSOC), panel overdrive, Fn-lock, boot sound.
- Reapply settings after wake.

## M2 — menu-bar app (SwiftUI, no Xcode needed: swiftc + bundle script)   ← now ✓ 2026-10-04, colour wheel + hex field
Mode switcher, brightness, colour picker + effects, fan RPM, Eco toggle,
charge limit. Saves settings; applies at login.

## M3 — native macOS integration
Keyboard backlight through VirtualSMC/AsusSMC so the system slider and keys work;
Fn+F5 (fan key) cycles modes.

## M4 — more hardware
ROG Aura keyboards over USB HID (N-KEY device, as G-Helper does) from the app,
no kext; fan curves (CPU/GPU/MID_FAN_CURVE); TGP / PPT with firmware limits.

## Release   ← 0.1.0, github.com/FranciumOS-org/MHelper
GPL-2.0. Testers' guide + log collector; the probe doubles as a "send us your
report" tool for unknown models. Names: "for ASUS laptops", no ASUS logos.
Refresh rate waits for the Rembrandt iGPU work (~/Developer/RembrandtGPU).

## M5 — ROG mice (USB HID, user space)   ✓ 2026-10-09, Mouse tab verified on Strix Impact III
tools/rogmouse and the app's Mouse tab (app/Sources/RogMouse.swift), protocol from
G-Helper AsusMouse.cs. Strix Impact III verified. All 67 G-Helper mouse models in app/Sources/MouseModels.swift (quirk flags for the
older protocols, Omni receiver detection via 01 A0). Only the Impact III is tested.
Not yet: battery, power-off, lift-off, debounce, button bindings; Balteus/Bulwark.
