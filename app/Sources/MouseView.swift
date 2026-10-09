// SPDX-License-Identifier: GPL-2.0
// The Mouse tab: DPI slots, polling rate, angle snapping, lighting.
import SwiftUI

struct MouseView: View {
    @EnvironmentObject var mouse: MouseController
    @State private var dpiText = ["", "", "", ""]
    private let swatches: [Color] = [.white, .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let model = mouse.model {
                HStack {
                    Label(model.name, systemImage: "computermouse")
                        .font(.headline)
                    Spacer()
                    Button {
                        mouse.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Read the settings from the mouse again")
                }
                if let st = mouse.state {
                    dpiSection(model, st)
                    sensorSection(model, st)
                    lightSection(model, st)
                } else {
                    ProgressView().controlSize(.small)
                }
                if let err = mouse.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Settings are stored in the mouse.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
    }

    // MARK: DPI

    private func dpiSection(_ model: MouseModel, _ st: MouseState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("DPI")
            HStack(spacing: 6) {
                ForEach(0..<model.dpiSlots, id: \.self) { i in
                    VStack(spacing: 4) {
                        Button {
                            mouse.setSlot(i + 1)
                        } label: {
                            Text("\(i + 1)")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .background(st.dpiSlot == i + 1 ? Color.accentColor.opacity(0.25) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .help("Use this DPI slot")
                        TextField("", text: Binding(
                            get: { dpiText[i].isEmpty ? "\(st.dpi[i])" : dpiText[i] },
                            set: { dpiText[i] = $0 }))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .onSubmit { commitDPI(model, i) }
                    }
                }
            }
            Text("\(model.minDPI)–\(model.maxDPI) in steps of \(model.dpiStep). Press Return to apply.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func commitDPI(_ model: MouseModel, _ i: Int) {
        let text = dpiText[i]
        dpiText[i] = ""
        guard var v = Int(text.trimmingCharacters(in: .whitespaces)) else { return }
        v = min(max(v, model.minDPI), model.maxDPI) / model.dpiStep * model.dpiStep
        mouse.setDPI(slot: i + 1, dpi: v)
    }

    // MARK: Sensor

    private func sensorSection(_ model: MouseModel, _ st: MouseState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Sensor")
            Picker("Polling rate", selection: Binding(
                get: { st.pollingHz },
                set: { mouse.setPolling($0) })) {
                ForEach(model.pollingRates, id: \.self) { hz in
                    Text(hz >= 1000 ? "\(hz / 1000)k Hz" : "\(hz) Hz").tag(hz)
                }
            }
            .pickerStyle(.segmented)
            if model.hasAngleSnapping {
                Toggle("Angle snapping", isOn: Binding(
                    get: { st.angleSnapping },
                    set: { mouse.setAngleSnapping($0) }))
            }
        }
    }

    // MARK: Lighting

    private func lightSection(_ model: MouseModel, _ st: MouseState) -> some View {
        let light = mouse.currentLight()
        return VStack(alignment: .leading, spacing: 8) {
            header("Lighting")
            if model.zones.count > 1 {
                Picker("Zone", selection: Binding(
                    get: { mouse.zone ?? -1 },
                    set: { mouse.setZone($0 < 0 ? nil : $0) })) {
                    Text("All").tag(-1)
                    ForEach(model.zones.indices, id: \.self) { i in
                        Text(model.zones[i].name).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                Picker("Effect", selection: Binding(
                    get: { light.mode },
                    set: { mouse.setMode($0) })) {
                    ForEach(model.modes) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                Spacer()
            }
            if light.mode != .off {
                HStack {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    BrightnessDragCatcher(value: light.brightness) { mouse.setBrightness($0) }
                    Image(systemName: "sun.max").foregroundStyle(.secondary)
                }
            }
            if light.mode.usesColor {
                HStack(spacing: 5) {
                    ForEach(swatches.indices, id: \.self) { i in
                        Circle()
                            .fill(swatches[i])
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                            .onTapGesture {
                                mouse.color = swatches[i]
                                mouse.sendColor()
                            }
                    }
                }
                HStack(alignment: .center, spacing: 12) {
                    ColorWheel(color: $mouse.color, onChange: { mouse.sendColor() })
                        .frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(mouse.color)
                            .frame(width: 104, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                        HexField(color: $mouse.color, onChange: { mouse.sendColor() })
                    }
                }
            }
        }
    }
}

/// A slider that only sends when the drag ends (each change is a USB write + save).
private struct BrightnessDragCatcher: View {
    let value: Int
    let commit: (Int) -> Void
    @State private var local: Double?

    var body: some View {
        Slider(value: Binding(
            get: { local ?? Double(value) },
            set: { local = $0 }), in: 0...100, onEditingChanged: { editing in
                if !editing, let v = local {
                    commit(Int(v.rounded()))
                    local = nil
                }
            })
    }
}
