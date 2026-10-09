// SPDX-License-Identifier: GPL-2.0
// ROG mice over USB HID, from user space: the packets of G-Helper's
// AsusMouse.cs and its model overrides (MouseModels.swift has the quirks).
//
// Indexing: `g(r, i)` reads G-Helper's byte i of an answer. G-Helper's buffers
// start with the report ID; macOS hands over reports without it when the ID is
// 0 and with it otherwise, so i maps to r[i - 1] or r[i].
import Foundation
import IOKit.hid

struct MouseLight: Equatable {
    var mode: MouseLightMode
    var brightness: Int     // 0...model.maxBrightness
    var r: Int, g: Int, b: Int
}

struct MouseState {
    var dpi: [Int]
    var dpiColors: [(Int, Int, Int)]   // per slot, when the model has DPI colours
    var dpiSlot: Int                   // 1-based
    var pollingHz: Int
    var angleSnapping: Bool
    var lights: [MouseLight]           // one per model zone
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

/// Firmware polling-rate codes (G-Helper PollingRate)
private let pollingCodes = [125, 250, 500, 1000, 2000, 4000, 8000]

/// One HID connection: sends packets, waits for the matching answer.
final class HIDChannel {
    static let reportSize = 64

    let device: IOHIDDevice
    private let answered = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var wantId: UInt8? = nil
    private var want = [UInt8]()
    private var waiting = false
    private var answer = [UInt8]()
    private let inbuf = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDChannel.reportSize)

    init(device: IOHIDDevice, runLoop: CFRunLoop) throws {
        self.device = device
        let r = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard r == kIOReturnSuccess else { throw MouseError.open(r) }
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, inbuf, HIDChannel.reportSize, { ctx, _, _, _, id, report, len in
            Unmanaged<HIDChannel>.fromOpaque(ctx!).takeUnretainedValue().received(id: UInt8(truncatingIfNeeded: id), report, len)
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func close(runLoop: CFRunLoop) {
        IOHIDDeviceRegisterInputReportCallback(device, inbuf, HIDChannel.reportSize, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, runLoop, CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    deinit { inbuf.deallocate() }

    private func received(id: UInt8, _ report: UnsafeMutablePointer<UInt8>, _ len: CFIndex) {
        let bytes = Array(UnsafeBufferPointer(start: report, count: min(len, HIDChannel.reportSize)))
        lock.lock()
        defer { lock.unlock() }
        guard waiting else { return }
        // With a report ID the first byte is the ID: it must be ours, and the payload follows it.
        let rid = wantId ?? 0
        if rid != 0 && bytes.first != rid { return }
        let payload = rid != 0 ? Array(bytes.dropFirst()) : bytes
        guard payload.count >= want.count, Array(payload.prefix(want.count)) == want else { return }
        answer = bytes
        waiting = false
        answered.signal()
    }

    /// Send `payload` (without report ID) and wait for an answer whose payload starts
    /// with the first `match` bytes. Returns the raw report.
    func send(_ payload: [UInt8], reportId: UInt8, match: Int, timeout: Double = 0.4) throws -> [UInt8] {
        var buf = [UInt8]()
        if reportId != 0 { buf.append(reportId) }
        buf += payload
        if buf.count < HIDChannel.reportSize { buf += [UInt8](repeating: 0, count: HIDChannel.reportSize - buf.count) }
        let padded = reportId != 0 ? Array(buf.dropFirst()) : buf
        for _ in 0..<3 {
            lock.lock()
            wantId = reportId
            want = Array(padded.prefix(match))
            waiting = true
            lock.unlock()
            while answered.wait(timeout: .now()) == .success {}
            let r = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportId), &buf, buf.count)
            guard r == kIOReturnSuccess else { throw MouseError.write(r) }
            if answered.wait(timeout: .now() + timeout) == .success {
                lock.lock()
                let a = answer
                lock.unlock()
                return a
            }
        }
        lock.lock()
        waiting = false
        lock.unlock()
        throw MouseError.noAnswer
    }
}

/// One connected mouse. Calls block: use them off the main thread.
final class RogMouse {
    let model: MouseModel
    private let channel: HIDChannel
    private let queue = DispatchQueue(label: "mhelper.mouse")

    init(model: MouseModel, channel: HIDChannel) {
        self.model = model
        self.channel = channel
    }

    var device: IOHIDDevice { channel.device }
    func close(runLoop: CFRunLoop) { channel.close(runLoop: runLoop) }

    // MARK: packets

    private func command(_ p: [UInt8], match: Int = 2) throws -> [UInt8] {
        let a = try channel.send(p, reportId: model.reportId, match: match)
        if g(a, 1) == 0xFF && g(a, 2) == 0xAA { throw MouseError.refused }
        return a
    }

    /// G-Helper's byte i of an answer
    private func g(_ a: [UInt8], _ i: Int) -> UInt8 {
        let k = model.reportId != 0 ? i : i - 1
        return k >= 0 && k < a.count ? a[k] : 0
    }

    private func save() throws { _ = try command([0x50, 0x03]) }

    private func wireMode(_ m: MouseLightMode) -> UInt8 {
        if m == .react && model.quirks.contains(.reactIs3) { return 0x03 }
        if m == .off && model.quirks.contains(.offIsFF) { return 0xFF }
        return m.rawValue
    }

    private func mode(fromWire b: UInt8) -> MouseLightMode {
        if b == 0x03 && model.quirks.contains(.reactIs3) { return .react }
        if b > 0x06 { return .off }
        return MouseLightMode(rawValue: b) ?? .off
    }

    // MARK: read

    func read() throws -> MouseState {
        try queue.sync {
            let q = model.quirks

            var slot = 1
            if model.dpiSlots > 1 {
                let p = try command([0x12, 0x00], match: 3)
                slot = Int(g(p, q.contains(.slotAt11) ? 11 : 12))
                if q.contains(.slotZeroBased) { slot += 1 }
                slot = max(1, min(model.dpiSlots, slot))
            }

            let d = try command([0x12, 0x04, model.xyDPI ? 0x02 : 0x00], match: 3)
            var dpi = [Int]()
            for i in 0..<model.dpiSlots {
                let off = model.xyDPI ? 5 + i * 4 : 5 + i * 2
                let v = Int(g(d, off)) | Int(g(d, off + 1)) << 8
                dpi.append(v * model.dpiStep + model.dpiStep)
            }

            var colors = [(Int, Int, Int)]()
            if model.dpiColors {
                let c = try command([0x12, 0x04, 0x03], match: 3)
                for i in 0..<model.dpiSlots {
                    colors.append((Int(g(c, 5 + i * 3)), Int(g(c, 6 + i * 3)), Int(g(c, 7 + i * 3))))
                }
            }

            // Polling and angle snapping are in the 12 04 00 answer
            let s = model.xyDPI ? try command([0x12, 0x04, 0x00], match: 3) : d
            let legacy = q.contains(.legacySensor)
            let code = Int(legacy || q.contains(.pollingReadAt9) ? g(s, 9) : g(s, 13) & 0x07)
            let hz = code < pollingCodes.count ? pollingCodes[code] : 0
            let angle = g(s, legacy ? 13 : 17) == 0x01

            var lights = [MouseLight]()
            if model.hasRGB {
                if q.contains(.lightingAllInOne) || q.contains(.lightingPink) {
                    let l = try command([0x12, 0x03, 0x00])
                    for z in model.zones {
                        let pink = q.contains(.lightingPink)
                        let off = pink ? 5 + 9 + Int(z.rawValue) * 9 : 5 + Int(z.rawValue) * 5
                        let rgb = pink ? off + 3 : off + 2
                        lights.append(MouseLight(mode: mode(fromWire: g(l, off)), brightness: Int(g(l, off + 1)),
                                                 r: Int(g(l, rgb)), g: Int(g(l, rgb + 1)), b: Int(g(l, rgb + 2))))
                    }
                } else {
                    for i in model.zones.indices {
                        let l = try command([0x12, 0x03, UInt8(i)])   // the answer doesn't repeat the zone
                        lights.append(MouseLight(mode: mode(fromWire: g(l, 5)), brightness: Int(g(l, 6)),
                                                 r: Int(g(l, 7)), g: Int(g(l, 8)), b: Int(g(l, 9))))
                    }
                }
            }

            return MouseState(dpi: dpi, dpiColors: colors, dpiSlot: slot, pollingHz: hz,
                              angleSnapping: angle, lights: lights)
        }
    }

    // MARK: write (each followed by save, as G-Helper does)

    /// `color`: the slot's DPI colour, kept as it is (models with DPI colours need it in the packet).
    func setDPI(slot: Int, dpi: Int, color: (Int, Int, Int)?) throws {
        guard (1...model.dpiSlots).contains(slot), (model.minDPI...model.maxDPI).contains(dpi) else { return }
        let v = (dpi - model.dpiStep) / model.dpiStep
        var p: [UInt8] = [0x51, 0x31, UInt8(slot - 1), 0x00, UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
        if model.dpiColors {
            let c = color ?? (255, 0, 0)
            p += [UInt8(c.0), UInt8(c.1), UInt8(c.2)]
        }
        try queue.sync {
            _ = try command(p)
            try save()
        }
    }

    func setSlot(_ slot: Int) throws {
        guard model.canChangeSlot, (1...model.dpiSlots).contains(slot) else { return }
        let wire = model.quirks.contains(.slotZeroBased) ? slot - 1 : slot
        try queue.sync {
            _ = try command([0x51, 0x31, 0x09, 0x00, UInt8(wire)])
            try save()
        }
    }

    func setPolling(_ hz: Int) throws {
        guard model.pollingRates.contains(hz), let code = pollingCodes.firstIndex(of: hz) else { return }
        let sub: UInt8 = model.quirks.contains(.legacySensor) ? 0x02 : 0x04
        try queue.sync {
            _ = try command([0x51, 0x31, sub, 0x00, UInt8(code)])
            try save()
        }
    }

    func setAngleSnapping(_ on: Bool) throws {
        guard model.angleSnapping else { return }
        let sub: UInt8 = model.quirks.contains(.legacySensor) ? 0x04 : 0x06
        try queue.sync {
            _ = try command([0x51, 0x31, sub, 0x00, on ? 1 : 0])
            try save()
        }
    }

    /// zone: index into model.zones, or nil for all zones.
    func setLight(_ l: MouseLight, zone: Int?) throws {
        guard model.hasRGB else { return }
        let q = model.quirks
        let z: UInt8 = zone.map { model.zones[$0].rawValue } ?? 0x03
        let m = wireMode(l.mode)
        let br = UInt8(max(0, min(model.maxBrightness, l.brightness)))
        let (r, g, b) = (UInt8(l.r), UInt8(l.g), UInt8(l.b))
        let p: [UInt8]
        if q.contains(.lightingImpact1) {
            p = [0x51, 0x28, 0x00, 0x00, m, br, r, g, b]
        } else if q.contains(.lightingPink) {
            let speed: UInt8 = l.mode == .rainbow ? 0x64 : 0x00
            p = [0x51, 0x28, z, 0x00, m, br, 0x00, r, g, b, 0x00, 0x00, 0x00, 0x00, 0x00, speed]
        } else if q.contains(.rainbowGladius) && l.mode == .rainbow {
            p = [0x51, 0x28, z, 0x00, m, br, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x64]
        } else {
            let speed: UInt8 = l.mode == .rainbow ? 0x07 : 0x00   // AnimationSpeed.Medium
            p = [0x51, 0x28, z, 0x00, m, br, r, g, b, 0x00, 0x00, speed]
        }
        try queue.sync {
            _ = try command(p)
            try save()
        }
    }
}

/// Watches for supported mice coming and going; owns the HID run-loop thread.
final class MouseWatcher {
    private var manager: IOHIDManager!
    private var runLoop: CFRunLoop!
    private var mice = [IOHIDDevice: RogMouse]()
    /// Called on the main queue with the current mouse (nil when none is left).
    var onChange: ((RogMouse?) -> Void)?

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            // Any ASUS device with the vendor page among its collections (the Omni
            // receiver has it on a secondary collection)
            IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: MouseModel.vendorID,
                                                    kIOHIDDeviceUsagePageKey: 0xFF01] as CFDictionary)
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

    // Runs on the HID thread
    private func added(_ dev: IOHIDDevice) {
        guard mice[dev] == nil else { return }
        let pid = intProp(dev, kIOHIDProductIDKey)
        let model: MouseModel
        let channel: HIDChannel
        do {
            if pid == MouseModel.omniPID {
                channel = try HIDChannel(device: dev, runLoop: runLoop)
                // Not on this thread: the answer arrives on this run loop.
                DispatchQueue.global().async { self.identifyOmni(dev, channel) }
                return
            }
            guard let m = MouseModel.direct(pid: pid) else { return }
            model = m
            channel = try HIDChannel(device: dev, runLoop: runLoop)
        } catch {
            return
        }
        connect(dev, RogMouse(model: model, channel: channel))
    }

    /// Omni receiver: ask which mice are paired (G-Helper DedectOmniMouse: 01 A0 00 00
    /// on report 1; PIDs at bytes 5, 9, 13, ... little endian).
    private func identifyOmni(_ dev: IOHIDDevice, _ channel: HIDChannel) {
        guard let a = try? channel.send([0xA0, 0x00, 0x00], reportId: 0x01, match: 0, timeout: 2) else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { channel.close(runLoop: self.runLoop) }
            CFRunLoopWakeUp(runLoop)
            return
        }
        var found: MouseModel?
        var off = 5
        while off + 1 < a.count {
            let pid = Int(a[off]) | Int(a[off + 1]) << 8
            if pid == 0 { break }
            if let m = MouseModel.omni(pairedPid: pid) { found = m; break }
            off += 4
        }
        guard let model = found else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) { channel.close(runLoop: self.runLoop) }
            CFRunLoopWakeUp(runLoop)
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
            self.connect(dev, RogMouse(model: model, channel: channel))
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func connect(_ dev: IOHIDDevice, _ mouse: RogMouse) {
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
