// SPDX-License-Identifier: GPL-2.0
// ROG mice over USB HID, from user space (same protocol as tools/rogmouse.c,
// from G-Helper's AsusMouse.cs). Byte offsets are G-Helper's minus one: macOS
// reports carry no report-ID byte.
import Foundation
import IOKit.hid

struct MouseModel {
    let vid: Int, pid: Int
    let name: String
    let dpiSlots: Int, minDPI: Int, maxDPI: Int, dpiStep: Int
    let pollingRates: [Int]          // Hz, index = firmware code
    let zones: [(name: String, id: UInt8)]
    let modes: [MouseLightMode]
    let hasAngleSnapping: Bool

    static let all: [MouseModel] = [
        MouseModel(vid: 0x0B05, pid: 0x1A88, name: "ROG Strix Impact III",
                   dpiSlots: 4, minDPI: 100, maxDPI: 12_000, dpiStep: 50,
                   pollingRates: [125, 250, 500, 1000],
                   zones: [("Logo", 0x00), ("Scroll wheel", 0x01)],
                   modes: [.staticColor, .breathe, .cycle, .react, .off],
                   hasAngleSnapping: true),
    ]
}

enum MouseLightMode: UInt8, CaseIterable, Identifiable {
    case staticColor = 0x00, breathe = 0x01, cycle = 0x02, rainbow = 0x03, react = 0x04, comet = 0x05, off = 0xF0
    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .staticColor: return "Static"
        case .breathe: return "Breathing"
        case .cycle: return "Color cycle"
        case .rainbow: return "Rainbow"
        case .react: return "React"
        case .comet: return "Comet"
        case .off: return "Off"
        }
    }
    var usesColor: Bool { self == .staticColor || self == .breathe || self == .react || self == .comet }
}

struct MouseLight: Equatable {
    var mode: MouseLightMode
    var brightness: Int     // 0-100
    var r: Int, g: Int, b: Int
}

struct MouseState {
    var dpi: [Int]
    var dpiSlot: Int          // 1-based
    var pollingHz: Int
    var angleSnapping: Bool
    var lights: [MouseLight]  // one per model zone
}

enum MouseError: Error, CustomStringConvertible {
    case noAnswer, refused, write(IOReturn), open(IOReturn)
    var description: String {
        switch self {
        case .noAnswer: return "The mouse didn't answer"
        case .refused: return "The mouse refused the command"
        case .write(let r): return String(format: "USB write failed (0x%x)", r)
        case .open(let r): return String(format: "Could not open the mouse (0x%x)", r)
        }
    }
}

/// One connected mouse. Commands run on `queue`; reports arrive on the mouse thread.
final class RogMouse {
    static let reportSize = 64

    let model: MouseModel
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "mhelper.mouse")
    private let answered = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var want = [UInt8]()
    private var answer = [UInt8](repeating: 0, count: RogMouse.reportSize)
    private let inbuf = UnsafeMutablePointer<UInt8>.allocate(capacity: RogMouse.reportSize)

    init(model: MouseModel, device: IOHIDDevice, runLoop: CFRunLoop) throws {
        self.model = model
        self.device = device
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw MouseError.open(r) }
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, inbuf, RogMouse.reportSize, { ctx, _, _, _, _, report, len in
            guard let ctx else { return }
            Unmanaged<RogMouse>.fromOpaque(ctx).takeUnretainedValue().received(report, len)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func close(runLoop: CFRunLoop) {
        IOHIDDeviceRegisterInputReportCallback(device, inbuf, RogMouse.reportSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { inbuf.deallocate() }

    private func received(_ report: UnsafeMutablePointer<UInt8>, _ len: CFIndex) {
        lock.lock()
        defer { lock.unlock() }
        guard !want.isEmpty, len >= want.count else { return }
        for i in 0..<want.count where report[i] != want[i] { return }   // left over from earlier
        answer = Array(UnsafeBufferPointer(start: report, count: min(len, RogMouse.reportSize)))
        want = []
        answered.signal()
    }

    /// Send one packet; wait for the answer that repeats its first `match` bytes.
    private func command(_ packet: [UInt8], match: Int = 2) throws -> [UInt8] {
        var buf = packet + [UInt8](repeating: 0, count: RogMouse.reportSize - packet.count)
        for _ in 0..<3 {
            lock.lock()
            want = Array(buf[0..<match])
            lock.unlock()
            while answered.wait(timeout: .now()) == .success {}    // drop a late signal
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &buf, buf.count)
            guard r == kIOReturnSuccess else { throw MouseError.write(r) }
            if answered.wait(timeout: .now() + 0.4) == .success {
                lock.lock()
                let a = answer
                lock.unlock()
                if a[0] == 0xFF && a[1] == 0xAA { throw MouseError.refused }
                return a
            }
        }
        throw MouseError.noAnswer
    }

    private func save() throws { _ = try command([0x50, 0x03]) }

    // MARK: - API (blocking; call off the main thread)

    func read() throws -> MouseState {
        try queue.sync {
            let p = try command([0x12, 0x00], match: 3)
            let d = try command([0x12, 0x04, 0x00], match: 3)
            var dpi = [Int]()
            for i in 0..<model.dpiSlots {
                let v = Int(d[4 + i * 2]) | Int(d[5 + i * 2]) << 8
                dpi.append(v * model.dpiStep + model.dpiStep)
            }
            let code = Int(d[12] & 0x07)
            var lights = [MouseLight]()
            for z in 0..<model.zones.count {
                let l = try command([0x12, 0x03, UInt8(z)])   // the answer doesn't repeat the zone
                lights.append(MouseLight(mode: MouseLightMode(rawValue: l[4]) ?? .off,
                                         brightness: Int(l[5]), r: Int(l[6]), g: Int(l[7]), b: Int(l[8])))
            }
            return MouseState(dpi: dpi, dpiSlot: max(1, min(model.dpiSlots, Int(p[11]))),
                              pollingHz: code < model.pollingRates.count ? model.pollingRates[code] : 0,
                              angleSnapping: d[16] == 1, lights: lights)
        }
    }

    func setDPI(slot: Int, dpi: Int) throws {
        guard (1...model.dpiSlots).contains(slot), (model.minDPI...model.maxDPI).contains(dpi) else { return }
        let v = (dpi / model.dpiStep * model.dpiStep - model.dpiStep) / model.dpiStep
        try queue.sync {
            _ = try command([0x51, 0x31, UInt8(slot - 1), 0x00, UInt8(v & 0xFF), UInt8(v >> 8)])
            try save()
        }
    }

    func setSlot(_ slot: Int) throws {
        guard (1...model.dpiSlots).contains(slot) else { return }
        try queue.sync {
            _ = try command([0x51, 0x31, 0x09, 0x00, UInt8(slot)])
            try save()
        }
    }

    func setPolling(_ hz: Int) throws {
        guard let code = model.pollingRates.firstIndex(of: hz) else { return }
        try queue.sync {
            _ = try command([0x51, 0x31, 0x04, 0x00, UInt8(code)])
            try save()
        }
    }

    func setAngleSnapping(_ on: Bool) throws {
        try queue.sync {
            _ = try command([0x51, 0x31, 0x06, 0x00, on ? 1 : 0])
            try save()
        }
    }

    /// zone: index into model.zones, or nil for all zones.
    func setLight(_ l: MouseLight, zone: Int?) throws {
        let id: UInt8 = zone.map { model.zones[$0].id } ?? 0x03
        try queue.sync {
            _ = try command([0x51, 0x28, id, 0x00, l.mode.rawValue, UInt8(max(0, min(100, l.brightness))),
                             UInt8(l.r), UInt8(l.g), UInt8(l.b), 0, 0, 0])
            try save()
        }
    }
}

/// Watches for supported mice coming and going; owns the HID run-loop thread.
final class MouseWatcher {
    private var manager: IOHIDManager!
    private var runLoop: CFRunLoop!
    private var mice = [IOHIDDevice: RogMouse]()
    /// Called on the main queue with the current mouse (nil when unplugged).
    var onChange: ((RogMouse?) -> Void)?

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDPrimaryUsagePageKey: 0xFF01] as CFDictionary)
            let me = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
                Unmanaged<MouseWatcher>.fromOpaque(ctx!).takeUnretainedValue().added(dev)
            }, me)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
                Unmanaged<MouseWatcher>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
            }, me)
            IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            ready.signal()
            CFRunLoopRun()
        }
        t.name = "mhelper.hid"
        t.start()
        ready.wait()
    }

    private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func added(_ dev: IOHIDDevice) {
        let vid = intProp(dev, kIOHIDVendorIDKey), pid = intProp(dev, kIOHIDProductIDKey)
        guard mice[dev] == nil, let model = MouseModel.all.first(where: { $0.vid == vid && $0.pid == pid }),
              let mouse = try? RogMouse(model: model, device: dev, runLoop: runLoop) else { return }
        mice[dev] = mouse
        DispatchQueue.main.async { self.onChange?(mouse) }
    }

    private func removed(_ dev: IOHIDDevice) {
        guard let mouse = mice.removeValue(forKey: dev) else { return }
        mouse.close(runLoop: runLoop)
        let next = mice.values.first
        DispatchQueue.main.async { self.onChange?(next) }
    }
}
