// SPDX-License-Identifier: GPL-2.0
// Hue/saturation wheel and hex field for the keyboard colour.
import SwiftUI

/// Hue around the circle, saturation from the centre (white) to the rim.
/// Brightness is left at full: the keyboard has its own brightness levels.
struct ColorWheel: View {
    @Binding var color: Color
    /// Called while dragging (throttled) and once when the drag ends.
    var onChange: () -> Void

    @State private var lastSent = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12)
                            .map { Color(hue: $0, saturation: 1, brightness: 1) }),
                        center: .center))
                    // SwiftUI angles run clockwise from 3 o'clock; flip so hue grows counter-clockwise.
                    .scaleEffect(x: 1, y: -1)
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(color))
                    .frame(width: 16, height: 16)
                    .shadow(radius: 1.5)
                    .position(knob(radius: radius))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { pick($0.location, radius: radius, final: false) }
                .onEnded { pick($0.location, radius: radius, final: true) })
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var hs: (CGFloat, CGFloat) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return (ns.hueComponent, ns.saturationComponent)
    }

    private func knob(radius: CGFloat) -> CGPoint {
        let (h, s) = hs
        let a = h * 2 * .pi
        return CGPoint(x: radius + cos(a) * s * radius, y: radius - sin(a) * s * radius)
    }

    private func pick(_ p: CGPoint, radius: CGFloat, final: Bool) {
        let dx = p.x - radius, dy = radius - p.y
        var a = atan2(dy, dx)
        if a < 0 { a += 2 * .pi }
        let s = min(hypot(dx, dy) / radius, 1)
        color = Color(hue: a / (2 * .pi), saturation: s, brightness: 1)
        // Each colour is one firmware call; ~10 per second keeps the drag live.
        let now = Date()
        if final || now.timeIntervalSince(lastSent) > 0.1 {
            lastSent = now
            onChange()
        }
    }
}

/// "#RRGGBB" text field; applies on Return or when focus leaves.
struct HexField: View {
    @Binding var color: Color
    var onChange: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("#").foregroundStyle(.secondary)
            TextField("RRGGBB", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(width: 80)
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { f in if !f { apply() } }
            if !valid {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .help("Six hex digits, e.g. ff8800")
            }
        }
        .onAppear { text = color.hex.uppercased() }
        .onChange(of: color.hex) { h in if !focused { text = h.uppercased() } }
    }

    private var cleaned: String {
        text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
    }

    private var valid: Bool { Color(hex: cleaned.lowercased()) != nil || cleaned.isEmpty }

    private func apply() {
        var h = cleaned.lowercased()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }  // f80 → ff8800
        guard let c = Color(hex: h) else { return }
        color = c
        text = h.uppercased()
        onChange()
    }
}
