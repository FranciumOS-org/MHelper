// SPDX-License-Identifier: GPL-2.0
// Panel state for a connected ROG mouse. The mouse keeps its own settings, so
// nothing is saved here: the panel reads them from the mouse.
import Foundation
import SwiftUI

@MainActor
final class MouseController: ObservableObject {
    private let watcher = MouseWatcher()
    private var mouse: RogMouse?

    @Published private(set) var model: MouseModel?
    @Published private(set) var state: MouseState?
    @Published private(set) var lastError: String?
    /// nil = all zones together
    @Published var zone: Int? = nil
    @Published var color: Color = .white

    init() {
        watcher.onChange = { [weak self] m in self?.connected(m) }
        watcher.start()
    }

    private func connected(_ m: RogMouse?) {
        mouse = m
        model = m?.model
        state = nil
        lastError = nil
        if m != nil { refresh() }
    }

    /// Runs a mouse call off the main thread, then re-reads the mouse.
    private func run(reread: Bool = true, _ body: @escaping (RogMouse) throws -> Void) {
        guard let mouse else { return }
        Task.detached {
            var err: String?
            var st: MouseState?
            do {
                try body(mouse)
                if reread { st = try mouse.read() }
            } catch {
                err = "\(error)"
            }
            let (e, s) = (err, st)
            await MainActor.run {
                guard self.mouse === mouse else { return }
                self.lastError = e
                if let s { self.apply(s) }
            }
        }
    }

    private func apply(_ st: MouseState) {
        state = st
        let l = currentLight(st)
        color = Color(red: Double(l.r) / 255, green: Double(l.g) / 255, blue: Double(l.b) / 255)
    }

    func refresh() { run { _ in } }

    func currentLight(_ st: MouseState? = nil) -> MouseLight {
        let s = st ?? state
        guard let s, !s.lights.isEmpty else {
            return MouseLight(mode: .staticColor, brightness: model?.maxBrightness ?? 100, r: 255, g: 255, b: 255)
        }
        return s.lights[zone ?? 0]
    }

    func setSlot(_ slot: Int) { run { try $0.setSlot(slot) } }
    func setDPI(slot: Int, dpi: Int) {
        let color = state.flatMap { slot - 1 < $0.dpiColors.count ? $0.dpiColors[slot - 1] : nil }
        run { try $0.setDPI(slot: slot, dpi: dpi, color: color) }
    }
    func setPolling(_ hz: Int) { run { try $0.setPolling(hz) } }
    func setAngleSnapping(_ on: Bool) { run { try $0.setAngleSnapping(on) } }

    func setZone(_ z: Int?) {
        zone = z
        if let state { apply(state) }
    }

    func setMode(_ mode: MouseLightMode) {
        var l = currentLight()
        l.mode = mode
        sendLight(l)
    }

    func setBrightness(_ b: Int) {
        var l = currentLight()
        l.brightness = b
        sendLight(l)
    }

    /// From the wheel / hex field / swatches (the wheel throttles itself).
    func sendColor() {
        var l = currentLight()
        let (r, g, b) = color.rgb255
        (l.r, l.g, l.b) = (r, g, b)
        if !l.mode.usesColor { l.mode = .staticColor }
        sendLight(l)
    }

    private func sendLight(_ l: MouseLight) {
        // Show it at once; the mouse is re-read afterwards.
        if var st = state {
            if let z = zone { st.lights[z] = l } else { st.lights = st.lights.map { _ in l } }
            state = st
        }
        let z = zone
        run(reread: false) { try $0.setLight(l, zone: z) }
    }
}
