// SPDX-License-Identifier: GPL-2.0
// Menu-bar app for AsusWMIControl.kext.
import SwiftUI

@main
struct AsusWMIControlApp: App {
    @StateObject private var ctl = Controller()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(ctl)
        } label: {
            Image(systemName: (ctl.policy ?? .balanced).symbol)
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    @EnvironmentObject var ctl: Controller
    @State private var confirmEco = false
    private let swatches: [Color] = [.white, .red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if ctl.status == nil {
                notLoaded
            } else {
                if ctl.features.contains(.thermal) { modeSection }
                if ctl.features.contains(.cpuFan) || ctl.features.contains(.gpuFan) { fanSection }
                if ctl.features.contains(.kbdBacklight) || ctl.features.contains(.rgb) { keyboardSection }
                if ctl.features.contains(.chargeLimit) { batterySection }
                if ctl.features.contains(.panelOD) || ctl.features.contains(.dgpu) { displaySection }
            }
            if let err = ctl.lastError, ctl.status != nil {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
            HStack {
                Toggle("Open at login", isOn: $ctl.launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { ctl.startPolling() }
        .onDisappear { ctl.stopPolling() }
        .alert("Turn off the NVIDIA GPU?", isPresented: $confirmEco) {
            Button("Turn off", role: .destructive) { ctl.setEco(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The dGPU stays powered off, in Windows too, until you turn Eco mode off again. A reboot may be needed for it to come back.")
        }
    }

    private var notLoaded: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Driver not loaded", systemImage: "bolt.slash")
                .font(.headline)
            Text(ctl.lastError ?? "AsusWMIControl.kext is not running.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") { ctl.refresh(); ctl.applySaved() }
                .controlSize(.small)
        }
    }

    private func header(_ title: String) -> some View {
        Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Performance")
            HStack(spacing: 6) {
                ForEach(Policy.uiOrder) { p in
                    Button {
                        ctl.setPolicy(p)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: p.symbol)
                            Text(p.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .tint(ctl.policy == p ? .accentColor : nil)
                    .background(ctl.policy == p ? Color.accentColor.opacity(0.18) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var fanSection: some View {
        HStack {
            if ctl.features.contains(.cpuFan) {
                fanTile("CPU fan", ctl.status?.cpuFanRPM)
            }
            if ctl.features.contains(.gpuFan) {
                fanTile("GPU fan", ctl.status?.gpuFanRPM)
            }
        }
    }

    private func fanTile(_ title: String, _ rpm: UInt32?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(rpm.map { "\($0) rpm" } ?? "–")
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyboardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            header("Keyboard")
            if ctl.features.contains(.kbdBacklight) {
                Picker("Brightness", selection: Binding(
                    get: { ctl.kbdLevel ?? Int(ctl.status?.kbdLevel ?? 0) },
                    set: { ctl.setKbd($0) })) {
                    Text("Off").tag(0)
                    Text("Low").tag(1)
                    Text("Mid").tag(2)
                    Text("High").tag(3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if ctl.features.contains(.rgb) {
                HStack(spacing: 5) {
                    ForEach(swatches.indices, id: \.self) { i in
                        Circle()
                            .fill(swatches[i])
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                            .onTapGesture {
                                ctl.color = swatches[i]
                                ctl.sendColor()
                            }
                    }
                    ColorPicker("", selection: Binding(
                        get: { ctl.color },
                        set: { ctl.color = $0; ctl.sendColor() }), supportsOpacity: false)
                        .labelsHidden()
                        .help("System colour picker")
                }
                HStack(alignment: .center, spacing: 12) {
                    ColorWheel(color: $ctl.color, onChange: { ctl.sendColor() })
                        .frame(width: 120, height: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ctl.color)
                            .frame(width: 104, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(.secondary.opacity(0.4), lineWidth: 0.5))
                        HexField(color: $ctl.color, onChange: { ctl.sendColor() })
                        let (r, g, b) = ctl.color.rgb255
                        Text("R \(r)  G \(g)  B \(b)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Picker("Effect", selection: Binding(
                        get: { ctl.effect },
                        set: { ctl.effect = $0; ctl.sendColor() })) {
                        ForEach(Effect.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    if ctl.effect != .staticColor {
                        Picker("Speed", selection: Binding(
                            get: { ctl.speed },
                            set: { ctl.speed = $0; ctl.sendColor() })) {
                            Text("Slow").tag(0)
                            Text("Medium").tag(1)
                            Text("Fast").tag(2)
                        }
                        .labelsHidden()
                    }
                }
                HStack {
                    if ctl.features.contains(.rgbState) {
                        Toggle("Lit while asleep", isOn: Binding(
                            get: { ctl.lightsWhenAsleep },
                            set: { ctl.setLightsWhenAsleep($0) }))
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Save to firmware") { ctl.saveColorToFirmware() }
                        .controlSize(.small)
                        .help("Keep this colour after reboot, also in Windows")
                }
            }
        }
    }

    private var batterySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Battery")
            Picker("Charge limit", selection: Binding(
                get: { ctl.chargeLimit ?? 100 },
                set: { ctl.setCharge($0) })) {
                Text("60%").tag(60)
                Text("80%").tag(80)
                Text("100%").tag(100)
            }
            .pickerStyle(.segmented)
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("Display & GPU")
            if ctl.features.contains(.panelOD) {
                Toggle("Panel overdrive", isOn: Binding(
                    get: { ctl.status?.panelOD ?? false },
                    set: { ctl.setPanelOD($0) }))
            }
            if ctl.features.contains(.dgpu) {
                Toggle("Eco mode (NVIDIA GPU off)", isOn: Binding(
                    get: { ctl.status?.dgpuDisabled ?? false },
                    set: { on in if on { confirmEco = true } else { ctl.setEco(false) } }))
                    .disabled(ctl.status?.gpuMuxHybrid == false)
                if ctl.status?.gpuMuxHybrid == false {
                    Text("The GPU MUX is in dGPU-only mode; switch it back in Windows first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
