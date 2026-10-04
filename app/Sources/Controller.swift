// SPDX-License-Identifier: GPL-2.0
// App state: what the user chose (saved), what the kext reports (polled).
import Foundation
import SwiftUI
import ServiceManagement

enum Policy: Int, CaseIterable, Identifiable {
    // Values are the kext API's (TUF/ROG order); the UI order is Silent → Turbo.
    case silent = 2, balanced = 0, turbo = 1
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .silent: return "Silent"
        case .balanced: return "Balanced"
        case .turbo: return "Turbo"
        }
    }
    var symbol: String {
        switch self {
        case .silent: return "leaf"
        case .balanced: return "scalemass"
        case .turbo: return "flame"
        }
    }
    static let uiOrder: [Policy] = [.silent, .balanced, .turbo]
}

enum Effect: Int, CaseIterable, Identifiable {
    // Firmware mode numbers (Linux kbd_rgb_mode)
    case staticColor = 0, breathe = 1, cycle = 2, strobe = 10
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .staticColor: return "Static"
        case .breathe: return "Breathing"
        case .cycle: return "Color cycle"
        case .strobe: return "Strobe"
        }
    }
}

@MainActor
final class Controller: ObservableObject {
    private let client = AsusClient()
    private let defaults = UserDefaults.standard
    private var pollTimer: Timer?

    @Published private(set) var status: AsusStatus?
    @Published private(set) var lastError: String?

    // Saved settings. nil/absent = never chosen: the app leaves the hardware alone.
    @Published var policy: Policy? { didSet { save("policy", policy?.rawValue) } }
    @Published var kbdLevel: Int? { didSet { save("kbdLevel", kbdLevel) } }
    @Published var color: Color = .white { didSet { saveColor() } }
    @Published var effect: Effect = .staticColor { didSet { save("effect", effect.rawValue) } }
    @Published var speed: Int = 1 { didSet { save("speed", speed) } }
    @Published var colorChosen = false { didSet { defaults.set(colorChosen, forKey: "colorChosen") } }
    @Published var chargeLimit: Int? { didSet { save("chargeLimit", chargeLimit) } }
    @Published var lightsWhenAsleep = true { didSet { defaults.set(lightsWhenAsleep, forKey: "lightsWhenAsleep") } }

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Login item: \(error.localizedDescription)"
            }
        }
    }

    init() {
        policy = (defaults.object(forKey: "policy") as? Int).flatMap(Policy.init(rawValue:))
        kbdLevel = defaults.object(forKey: "kbdLevel") as? Int
        effect = Effect(rawValue: defaults.integer(forKey: "effect")) ?? .staticColor
        speed = (defaults.object(forKey: "speed") as? Int) ?? 1
        chargeLimit = defaults.object(forKey: "chargeLimit") as? Int
        colorChosen = defaults.bool(forKey: "colorChosen")
        lightsWhenAsleep = (defaults.object(forKey: "lightsWhenAsleep") as? Bool) ?? true
        if let hex = defaults.string(forKey: "color"), let c = Color(hex: hex) { color = c }
        refresh()
        applySaved()
    }

    private func save(_ key: String, _ value: Int?) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    private func saveColor() { defaults.set(color.hex, forKey: "color") }

    var features: Features { status?.features ?? [] }

    // MARK: - Kext calls

    private func attempt(_ body: () throws -> Void) {
        do {
            try body()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    func refresh() {
        do {
            status = try client.status()
            if lastError == AsusError.notLoaded.description { lastError = nil }
        } catch {
            status = nil
            lastError = "\(error)"
        }
    }

    /// Reapply the user's choices (launch / login). Nothing the user never chose.
    func applySaved() {
        guard status != nil else { return }
        if let p = policy { attempt { try client.setThermal(p.rawValue) } }
        if let l = kbdLevel { attempt { try client.setKbd(l) } }
        if colorChosen { sendColor() }
        if let c = chargeLimit { attempt { try client.setCharge(c) } }
        refresh()
    }

    func setPolicy(_ p: Policy) {
        attempt { try client.setThermal(p.rawValue) }
        if lastError == nil { policy = p }
        refresh()
    }

    func setKbd(_ level: Int) {
        attempt { try client.setKbd(level) }
        if lastError == nil { kbdLevel = level }
        refresh()
    }

    func sendColor() {
        let (r, g, b) = color.rgb255
        attempt {
            try client.setRGB(mode: effect.rawValue, r: r, g: g, b: b, speed: speed, save: false)
        }
        if lastError == nil { colorChosen = true }
    }

    /// Store the current colour in the firmware too, so it survives a reboot into Windows.
    func saveColorToFirmware() {
        let (r, g, b) = color.rgb255
        attempt {
            try client.setRGB(mode: effect.rawValue, r: r, g: g, b: b, speed: speed, save: true)
        }
    }

    func setLightsWhenAsleep(_ on: Bool) {
        attempt { try client.setRGBState(boot: true, awake: true, sleep: on, keyboard: true, save: true) }
        if lastError == nil { lightsWhenAsleep = on }
    }

    func setCharge(_ percent: Int) {
        attempt { try client.setCharge(percent) }
        if lastError == nil { chargeLimit = percent }
        refresh()
    }

    func setPanelOD(_ on: Bool) {
        attempt { try client.setPanelOD(on) }
        refresh()
    }

    func setEco(_ on: Bool) {
        attempt { try client.setDGPUDisabled(on) }
        refresh()
    }

    // MARK: - Fans: poll only while the menu is open

    func startPolling() {
        refresh()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - Colour helpers

extension Color {
    init?(hex: String) {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }

    var rgb255: (Int, Int, Int) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func c(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return (c(ns.redComponent), c(ns.greenComponent), c(ns.blueComponent))
    }

    var hex: String {
        let (r, g, b) = rgb255
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
