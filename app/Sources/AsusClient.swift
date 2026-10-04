// SPDX-License-Identifier: GPL-2.0
// Connection to AsusWMIControl.kext (selectors in include/asus_wmi_uc.h).
import Foundation
import IOKit

enum AsusError: Error, CustomStringConvertible {
    case notLoaded
    case open(kern_return_t)
    case call(kern_return_t)

    var description: String {
        switch self {
        case .notLoaded: return "AsusWMIControl.kext is not loaded"
        case .open(let kr): return String(format: "Could not open the driver (0x%x)", kr)
        case .call(let kr):
            switch kr {
            case kIOReturnUnsupported: return "Not supported on this laptop"
            case kIOReturnBadArgument: return "Value out of range"
            case kIOReturnNotPermitted: return "Refused: the GPU MUX is in dGPU-only mode"
            default: return String(format: "Firmware call failed (0x%x)", kr)
            }
        }
    }
}

struct Features: OptionSet {
    let rawValue: UInt32
    static let kbdBacklight = Features(rawValue: UInt32(kAsusFeatKbdBacklight))
    static let rgb          = Features(rawValue: UInt32(kAsusFeatRGB))
    static let rgbState     = Features(rawValue: UInt32(kAsusFeatRGBState))
    static let thermal      = Features(rawValue: UInt32(kAsusFeatThermal))
    static let cpuFan       = Features(rawValue: UInt32(kAsusFeatCPUFan))
    static let gpuFan       = Features(rawValue: UInt32(kAsusFeatGPUFan))
    static let chargeLimit  = Features(rawValue: UInt32(kAsusFeatChargeLimit))
    static let panelOD      = Features(rawValue: UInt32(kAsusFeatPanelOD))
    static let dgpu         = Features(rawValue: UInt32(kAsusFeatDGPU))
    static let gpuMux       = Features(rawValue: UInt32(kAsusFeatGPUMux))
}

/// nil means unknown / unreadable (ASUS_UNKNOWN in the kext).
private func known(_ v: UInt32) -> UInt32? { v == ASUS_UNKNOWN ? nil : v }

struct AsusStatus {
    var features: Features
    var kbdLevel: UInt32?
    var thermalPolicy: UInt32?
    var chargeLimit: UInt32?
    var panelOD: Bool?
    var dgpuDisabled: Bool?
    var gpuMuxHybrid: Bool?
    var cpuFanRPM: UInt32?
    var gpuFanRPM: UInt32?

    init(_ i: AsusWMIInfo) {
        features = Features(rawValue: i.features)
        kbdLevel = known(i.kbdLevel)
        thermalPolicy = known(i.thermalPolicy)
        chargeLimit = known(i.chargeLimit)
        panelOD = known(i.panelOD).map { $0 != 0 }
        dgpuDisabled = known(i.dgpuDisabled).map { $0 != 0 }
        gpuMuxHybrid = known(i.gpuMux).map { $0 != 0 }
        cpuFanRPM = known(i.cpuFanRPM)
        gpuFanRPM = known(i.gpuFanRPM)
    }
}

final class AsusClient {
    private var conn: io_connect_t = 0

    deinit {
        if conn != 0 { IOServiceClose(conn) }
    }

    private func connect() throws {
        if conn != 0 { return }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(ASUS_WMI_SERVICE_CLASS))
        guard svc != 0 else { throw AsusError.notLoaded }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        let kr = IOServiceOpen(svc, mach_task_self_, 0, &c)
        guard kr == KERN_SUCCESS else { throw AsusError.open(kr) }
        conn = c
    }

    /// Drops a dead connection (kext unloaded/reloaded) so the next call reconnects.
    private func run(_ body: () -> kern_return_t) throws {
        try connect()
        let kr = body()
        if kr == MACH_SEND_INVALID_DEST || kr == kIOReturnNotOpen || kr == kIOReturnNoDevice {
            IOServiceClose(conn)
            conn = 0
        }
        guard kr == KERN_SUCCESS else { throw AsusError.call(kr) }
    }

    func status() throws -> AsusStatus {
        var info = AsusWMIInfo()
        var size = MemoryLayout<AsusWMIInfo>.size
        try run { IOConnectCallStructMethod(conn, UInt32(kAsusSelGetInfo), nil, 0, &info, &size) }
        return AsusStatus(info)
    }

    private func scalar(_ sel: Int32, _ args: [UInt64]) throws {
        try run { IOConnectCallScalarMethod(conn, UInt32(sel), args, UInt32(args.count), nil, nil) }
    }

    func setKbd(_ level: Int) throws { try scalar(Int32(kAsusSelSetKbdBrightness), [UInt64(level)]) }

    func setRGB(mode: Int, r: Int, g: Int, b: Int, speed: Int, save: Bool) throws {
        try scalar(Int32(kAsusSelSetRGB),
                   [UInt64(mode), UInt64(r), UInt64(g), UInt64(b), UInt64(speed), save ? 1 : 0])
    }

    func setRGBState(boot: Bool, awake: Bool, sleep: Bool, keyboard: Bool, save: Bool) throws {
        try scalar(Int32(kAsusSelSetRGBState),
                   [boot, awake, sleep, keyboard, save].map { $0 ? 1 : 0 })
    }

    func setThermal(_ policy: Int) throws { try scalar(Int32(kAsusSelSetThermalPolicy), [UInt64(policy)]) }
    func setCharge(_ percent: Int) throws { try scalar(Int32(kAsusSelSetChargeLimit), [UInt64(percent)]) }
    func setPanelOD(_ on: Bool) throws { try scalar(Int32(kAsusSelSetPanelOD), [on ? 1 : 0]) }
    func setDGPUDisabled(_ off: Bool) throws { try scalar(Int32(kAsusSelSetDGPUDisabled), [off ? 1 : 0]) }
}
