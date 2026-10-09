// SPDX-License-Identifier: GPL-2.0
// ROG / TUF mice: one entry per model, from G-Helper's
// app/Peripherals/Mouse/Models/*.cs (seerge/g-helper, fetched 2026-10-09),
// with each class's inherited overrides flattened. Only what the Mouse tab uses:
// DPI, polling rate, angle snapping, lighting. Balteus (mouse pad) and Bulwark
// Dock are left out: they aren't mice and need their own packets.
import Foundation

enum MouseZone: UInt8 {
    case logo = 0, wheel = 1, underglow = 2
    var title: String {
        switch self {
        case .logo: return "Logo"
        case .wheel: return "Scroll wheel"
        case .underglow: return "Underglow"
        }
    }
}

/// Packet differences between mouse families (G-Helper overrides).
struct MouseQuirks: OptionSet {
    let rawValue: Int
    /// Polling read at byte 9, write 51 31 02; angle snapping read at 13, write 51 31 04
    /// (Gladius II, Strix Carry, Strix Impact, TUF M5).
    static let legacySensor  = MouseQuirks(rawValue: 1 << 0)
    /// Only the polling *read* is at byte 9 (Pugio).
    static let pollingReadAt9 = MouseQuirks(rawValue: 1 << 1)
    /// All zones come in one 12 03 00 answer, 5 bytes per zone at 5 + zone*5.
    static let lightingAllInOne = MouseQuirks(rawValue: 1 << 2)
    /// Gladius II PNK: one answer, 9 bytes per zone after an empty block; write has a dual-colour byte.
    static let lightingPink  = MouseQuirks(rawValue: 1 << 3)
    /// Rainbow sends red and speed 0x64 (Gladius II, Pugio).
    static let rainbowGladius = MouseQuirks(rawValue: 1 << 4)
    /// Strix Impact: 51 28 00 00 mode brightness r g b, no zone.
    static let lightingImpact1 = MouseQuirks(rawValue: 1 << 5)
    /// React is mode 3 on the wire (Chakram Core, Impact II, TUF M3/M5).
    static let reactIs3      = MouseQuirks(rawValue: 1 << 6)
    /// Off is 0xFF on the wire instead of 0xF0 (Keris Wireless, Impact II Wireless).
    static let offIsFF       = MouseQuirks(rawValue: 1 << 7)
    /// TUF M3 Gen II: DPI slot is 0-based on the wire.
    static let slotZeroBased = MouseQuirks(rawValue: 1 << 8)
    /// Active DPI slot is at byte 11 of 12 00 (Strix Carry), not 12.
    static let slotAt11      = MouseQuirks(rawValue: 1 << 9)
}

struct MouseModel {
    var pid: Int
    /// For mice behind the Omni receiver (0x1ACE): the PIDs the receiver reports for this mouse.
    var omniPids: [Int] = []
    var name: String
    var reportId: UInt8 = 0
    var dpiSlots = 4
    var minDPI = 100
    var maxDPI: Int
    var dpiStep = 50
    var xyDPI = false
    var dpiColors = false
    var canChangeSlot = true
    var pollingRates: [Int] = [125, 250, 500, 1000]
    var angleSnapping = true
    var zones: [MouseZone] = []
    var modes: [MouseLightMode] = MouseLightMode.allCases
    var maxBrightness = 100
    var quirks: MouseQuirks = []

    var hasRGB: Bool { !zones.isEmpty }
    var isOmni: Bool { !omniPids.isEmpty }

    static let vendorID = 0x0B05
    static let omniPID = 0x1ACE

    // Shorthands for the mode lists G-Helper's models allow
    private static let sbcr: [MouseLightMode] = [.staticColor, .breathe, .cycle, .react]
    private static let sbcrb: [MouseLightMode] = [.staticColor, .breathe, .cycle, .react, .battery]
    private static let sbcrbo: [MouseLightMode] = [.staticColor, .breathe, .cycle, .react, .battery, .off]
    private static let sbcRrc: [MouseLightMode] = [.staticColor, .breathe, .cycle, .rainbow, .react, .comet]
    private static let lsu: [MouseZone] = [.logo, .wheel, .underglow]
    private static let ls: [MouseZone] = [.logo, .wheel]
    private static let to8k = [125, 250, 500, 1000, 2000, 4000, 8000]

    static let all: [MouseModel] = {
        var m = [MouseModel]()
        func add(_ x: MouseModel) { m.append(x) }

        // ROG Chakram X (XY DPI, DPI colours)
        let chakramX = MouseModel(pid: 0x1A1A, name: "ROG Chakram X (Wireless)", maxDPI: 36_000, xyDPI: true,
                                  dpiColors: true, pollingRates: [250, 500, 1000], zones: lsu)
        add(chakramX)
        add(chakramX.with(pid: 0x1A18, name: "ROG Chakram X (Wired)") { $0.pollingRates = [250, 500, 1000, 2000, 4000, 8000] })

        // ROG Gladius III Aimpoint family
        let g3a = MouseModel(pid: 0x1A72, name: "ROG Gladius III Aimpoint (Wireless)", maxDPI: 36_000, xyDPI: true,
                             dpiColors: true, zones: lsu)
        add(g3a)
        add(g3a.with(pid: 0x1A70, name: "ROG Gladius III Aimpoint (Wired)"))
        let eva2 = g3a.with(pid: 0x1B0C, name: "ROG Gladius III Eva 2 (Wireless)") {
            $0.zones = [.logo]
            $0.modes = [.staticColor, .breathe, .cycle, .react, .comet, .battery]
        }
        add(eva2)
        add(eva2.with(pid: 0x1B0A, name: "ROG Gladius III Eva 2 (Wired)"))
        add(g3a.with(pid: omniPID, name: "ROG Gladius III Aimpoint (Omni)") { $0.omniPids = [0x1A72]; $0.reportId = 3 })

        // ROG Gladius III
        let g3 = MouseModel(pid: 0x197F, name: "ROG Gladius III (Wireless)", maxDPI: 26_000, zones: lsu)
        add(g3)
        add(g3.with(pid: 0x197D, name: "ROG Gladius III (Wired)"))
        add(g3.with(pid: 0x197B, name: "ROG Gladius III") { $0.modes = sbcRrc })

        // ROG Gladius II family (older protocol)
        let g2Legacy: MouseQuirks = [.legacySensor, .lightingAllInOne, .rainbowGladius]
        add(MouseModel(pid: 0x18A0, name: "ROG Gladius II Wireless", dpiSlots: 2, maxDPI: 16_000, dpiStep: 100,
                       zones: ls, modes: [.staticColor, .breathe, .cycle, .react, .battery], maxBrightness: 4,
                       quirks: g2Legacy))
        let g2o = MouseModel(pid: 0x1877, name: "ROG Gladius II Origin", dpiSlots: 2, maxDPI: 12_000, dpiStep: 100,
                             zones: lsu, modes: sbcRrc, maxBrightness: 4, quirks: g2Legacy)
        add(g2o)
        add(g2o.with(pid: 0x1845, name: "ROG Gladius II"))
        add(g2o.with(pid: 0x18B1, name: "ROG Gladius II Origin COD"))
        add(g2o.with(pid: 0x18CD, name: "ROG Gladius II PNK LTD") {
            $0.zones = [.wheel, .underglow]
            $0.quirks = [.legacySensor, .lightingPink]
        })

        // ROG Harpe Ace family
        let harpeAL = MouseModel(pid: 0x1A94, name: "ROG Harpe Ace Aim Lab Edition (Wireless)", minDPI: 50,
                                 maxDPI: 36_000, xyDPI: true, dpiColors: true, zones: [.wheel], modes: sbcrbo)
        add(harpeAL)
        add(harpeAL.with(pid: 0x1A92, name: "ROG Harpe Ace Aim Lab Edition (Wired)"))
        add(harpeAL.with(pid: omniPID, name: "ROG Harpe Ace Aim Lab Edition (Omni)") { $0.omniPids = [0x1A94]; $0.reportId = 3 })
        add(harpeAL.with(pid: 0x1B67, name: "ROG Harpe Ace Extreme (Wired)") { $0.maxDPI = 42_000 })
        add(harpeAL.with(pid: omniPID, name: "ROG Harpe Ace Extreme (Omni)") {
            $0.maxDPI = 42_000; $0.omniPids = [0x1B68, 0x1B69]; $0.reportId = 3
        })
        let harpeMini = MouseModel(pid: 0x1B63, name: "ROG Harpe Ace Mini (Wired)", maxDPI: 42_000, xyDPI: true,
                                   dpiColors: true, zones: [.wheel], modes: sbcrbo)
        add(harpeMini)
        add(harpeMini.with(pid: omniPID, name: "ROG Harpe Ace Mini (Omni)") { $0.omniPids = [0x1B65]; $0.reportId = 3 })
        let harpe2 = MouseModel(pid: 0x1C69, name: "ROG Harpe II Ace (Wired)", maxDPI: 42_000, xyDPI: true,
                                dpiColors: true, pollingRates: to8k, zones: [.wheel], modes: sbcrbo)
        add(harpe2)
        add(harpe2.with(pid: 0x1AD0, name: "ROG Harpe II Ace (Wireless)") { $0.reportId = 3 })

        // ROG Keris II
        let keris2Ace = MouseModel(pid: 0x1B16, name: "ROG Keris II Ace (Wired)", maxDPI: 42_000, xyDPI: true,
                                   dpiColors: true, zones: [.logo], modes: sbcrbo)
        add(keris2Ace)
        add(keris2Ace.with(pid: omniPID, name: "ROG Keris II Ace (Omni)") { $0.omniPids = [0x1B1A, 0x1B18]; $0.reportId = 3 })
        let keris2O = MouseModel(pid: 0x1C0C, name: "ROG Keris II Origin (Wired)", maxDPI: 42_000, xyDPI: true,
                                 dpiColors: true, zones: lsu, modes: sbcrbo)
        add(keris2O)
        add(keris2O.with(pid: omniPID, name: "ROG Keris II Origin (Omni)") { $0.omniPids = [0x1C0E]; $0.reportId = 3 })
        add(keris2O.with(pid: 0x1D4C, name: "ROG Keris II Origin KJP (Wired)"))
        add(keris2O.with(pid: omniPID, name: "ROG Keris II Origin KJP (Omni)") { $0.omniPids = [0x1D4E]; $0.reportId = 3 })

        // ROG Keris (Wireless)
        let keris = MouseModel(pid: 0x1960, name: "ROG Keris (Wireless)", maxDPI: 16_000, dpiStep: 100,
                               canChangeSlot: false, zones: ls, modes: sbcrbo, maxBrightness: 4, quirks: [.offIsFF])
        add(keris)
        add(keris.with(pid: 0x195C, name: "ROG Keris"))
        add(keris.with(pid: 0x195E, name: "ROG Keris (Wired)"))
        add(keris.with(pid: 0x1A59, name: "ROG Keris EVA Edition"))
        add(keris.with(pid: 0x1A57, name: "ROG Keris EVA Edition (Wired)"))

        // ROG Keris Wireless Aimpoint
        let kerisAP = MouseModel(pid: 0x1A68, name: "ROG Keris Wireless Aimpoint (Wireless)", maxDPI: 36_000,
                                 xyDPI: true, dpiColors: true, zones: [.logo], modes: sbcrb)
        add(kerisAP)
        add(kerisAP.with(pid: 0x1A66, name: "ROG Keris Wireless Aimpoint (Wired)"))
        add(kerisAP.with(pid: omniPID, name: "ROG Keris Wireless Aimpoint (Omni)") { $0.omniPids = [0x1A68, 0x1A6A]; $0.reportId = 3 })

        // ASUS MD200 (no lighting)
        add(MouseModel(pid: 0x1A24, name: "ASUS Mouse MD200", dpiSlots: 2, maxDPI: 4_200,
                       pollingRates: [125, 250], angleSnapping: false))

        // ROG Pugio
        add(MouseModel(pid: 0x1846, name: "ROG Pugio", dpiSlots: 2, minDPI: 50, maxDPI: 7_200, zones: lsu,
                       modes: sbcRrc, maxBrightness: 4, quirks: [.pollingReadAt9, .lightingAllInOne, .rainbowGladius]))
        let pugio2 = MouseModel(pid: 0x1908, name: "ROG Pugio II (Wireless)", maxDPI: 16_000, dpiStep: 100,
                                canChangeSlot: false, zones: lsu, maxBrightness: 4, quirks: [.lightingAllInOne])
        add(pugio2)
        add(pugio2.with(pid: 0x1906, name: "ROG Pugio II (Wired)"))

        // ROG Spatha X
        let spatha = MouseModel(pid: 0x1979, name: "ROG Spatha X (Wireless)", maxDPI: 19_000, dpiColors: true,
                                pollingRates: [250, 500, 1000], zones: lsu)
        add(spatha)
        add(spatha.with(pid: 0x1977, name: "ROG Spatha X (Wired)"))

        // ROG Strix Carry (no lighting)
        add(MouseModel(pid: 0x18B4, name: "ROG Strix Carry", dpiSlots: 2, minDPI: 50, maxDPI: 7_200,
                       canChangeSlot: false, quirks: [.legacySensor, .slotAt11]))

        // ROG Strix Evolve
        add(MouseModel(pid: 0x185B, name: "ROG Strix Evolve", dpiSlots: 2, minDPI: 50, maxDPI: 7_200, dpiStep: 100,
                       zones: [.logo], modes: sbcr, maxBrightness: 4))

        // ROG Strix Impact family
        add(MouseModel(pid: 0x1847, name: "ROG Strix Impact", dpiSlots: 2, maxDPI: 5_000, angleSnapping: false,
                       zones: [.logo], modes: sbcr, maxBrightness: 4,
                       quirks: [.legacySensor, .lightingAllInOne, .lightingImpact1]))
        let impact2 = MouseModel(pid: 0x18E1, name: "ROG Strix Impact II", maxDPI: 6_200, dpiStep: 100, zones: lsu,
                                 modes: sbcr, maxBrightness: 4, quirks: [.lightingAllInOne, .reactIs3])
        add(impact2)
        add(impact2.with(pid: 0x1956, name: "ROG Strix Impact II Electro Punk"))
        add(impact2.with(pid: 0x19D2, name: "ROG Strix Impact II Moonlight White"))
        let impact2W = MouseModel(pid: 0x1949, name: "ROG Strix Impact II (Wireless)", maxDPI: 16_000, dpiStep: 100,
                                  canChangeSlot: false, zones: ls, modes: sbcrbo, maxBrightness: 4,
                                  quirks: [.lightingAllInOne, .offIsFF])
        add(impact2W)
        add(impact2W.with(pid: 0x1947, name: "ROG Strix Impact II (Wired)"))
        add(MouseModel(pid: 0x1A88, name: "ROG Strix Impact III", maxDPI: 12_000, zones: ls,
                       modes: [.staticColor, .breathe, .cycle, .react, .off]))
        add(MouseModel(pid: omniPID, omniPids: [0x1AD7], name: "ROG Strix Impact III Wireless (Omni)", reportId: 3,
                       maxDPI: 36_000, xyDPI: true, dpiColors: true, zones: [.wheel], modes: sbcrbo))

        // ROG Chakram
        let chakram = MouseModel(pid: 0x18E5, name: "ROG Chakram (Wireless)", maxDPI: 16_000, dpiStep: 100,
                                 canChangeSlot: false, zones: lsu, maxBrightness: 4, quirks: [.lightingAllInOne])
        add(chakram)
        add(chakram.with(pid: 0x18E3, name: "ROG Chakram (Wired)"))
        add(MouseModel(pid: 0x1958, name: "ROG Chakram Core", maxDPI: 16_000, dpiStep: 100, canChangeSlot: false,
                       zones: ls, modes: sbcr, maxBrightness: 4, quirks: [.lightingAllInOne, .reactIs3]))

        // TUF Gaming
        let m3 = MouseModel(pid: 0x1910, name: "TUF Gaming M3", maxDPI: 7_000, dpiStep: 100, zones: [.logo],
                            modes: sbcr, maxBrightness: 4, quirks: [.reactIs3])
        add(m3)
        add(m3.with(pid: 0x1A9B, name: "TUF Gaming M3 (Gen II)") {
            $0.maxDPI = 8_000; $0.dpiStep = 50; $0.maxBrightness = 100; $0.dpiColors = true
            $0.quirks = [.reactIs3, .slotZeroBased]
        })
        add(MouseModel(pid: 0x1A03, name: "TUF Gaming M4 Air", maxDPI: 16_000, dpiStep: 100))
        let m4w = MouseModel(pid: 0x19F4, name: "TUF Gaming M4 (Wireless)", maxDPI: 12_000, dpiStep: 100)
        add(m4w)
        add(m4w.with(pid: 0x1A8D, name: "TX Gaming Mouse (Wireless)") { $0.dpiStep = 50 })
        let txMini = m4w.with(pid: 0x1AF5, name: "TX Gaming Mouse Mini (Wireless)") { $0.dpiStep = 50; $0.xyDPI = true }
        add(txMini)
        add(txMini.with(pid: 0x1AF3, name: "TX Gaming Mouse Mini (Wired)"))
        let miku = txMini.with(pid: 0x1C57, name: "TUF Gaming Mini Miku Edition (Wireless)") { $0.zones = [.logo] }
        add(miku)
        add(miku.with(pid: 0x1C56, name: "TUF Gaming Mini Miku Edition (Wired)"))
        add(MouseModel(pid: 0x1898, name: "TUF Gaming M5", dpiSlots: 2, maxDPI: 6_200, dpiStep: 100, zones: [.logo],
                       modes: sbcr, maxBrightness: 4, quirks: [.legacySensor, .reactIs3]))
        return m
    }()

    /// A copy with a different PID and name (and optional changes), like a G-Helper subclass.
    func with(pid: Int, name: String, _ change: (inout MouseModel) -> Void = { _ in }) -> MouseModel {
        var c = self
        c.pid = pid
        c.name = name
        change(&c)
        return c
    }

    /// Direct (non-Omni) models by USB product ID.
    static func direct(pid: Int) -> MouseModel? { all.first { $0.pid == pid && !$0.isOmni } }
    /// Omni models by the PID the receiver reports for the paired mouse.
    static func omni(pairedPid: Int) -> MouseModel? { all.first { $0.omniPids.contains(pairedPid) } }
}

enum MouseLightMode: UInt8, CaseIterable, Identifiable {
    // G-Helper's LightingMode values; per-model remapping happens in RogMouse.
    case staticColor = 0x00, breathe = 0x01, cycle = 0x02, rainbow = 0x03, react = 0x04, comet = 0x05,
         battery = 0x06, off = 0xF0
    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .staticColor: return "Static"
        case .breathe: return "Breathing"
        case .cycle: return "Color cycle"
        case .rainbow: return "Rainbow"
        case .react: return "React"
        case .comet: return "Comet"
        case .battery: return "Battery level"
        case .off: return "Off"
        }
    }
    var usesColor: Bool { self == .staticColor || self == .breathe || self == .react || self == .comet }
}
