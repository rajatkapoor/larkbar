import SwiftUI

/// Mics, sound and receiver settings for a connected receiver. Only what the receiver reports is shown.
struct ReceiverControls: View {
    let store: ReceiverStore
    let model: LarkModel
    let status: ReceiverStatus

    @AppStorage("showReceiverSettings") private var showReceiverSettings = false
    @State private var confirmingRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            mics
            sound
            receiver
            statusLine
        }
    }

    // MARK: Mics

    private var mics: some View {
        Section {
            ForEach(status.transmitters) { mic in
                MicRow(mic: mic, canMute: model.supportsMute) {
                    store.apply(.mute(transmitter: mic.index, muted: !mic.isMuted))
                }
            }
        } header: {
            SectionTitle("Mics")
        }
    }

    // MARK: Sound

    private var sound: some View {
        Section {
            SettingRow("Gain") {
                Picker("Gain", selection: binding(status.gain) { .gain($0) }) {
                    ForEach(Array(LarkSetting.gainRange), id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .help("Mic input level. 0 is the quietest.")

            SettingRow("Noise cancelling") {
                Toggle("Noise cancelling", isOn: binding(status.noiseEnabled) {
                    .noise(enabled: $0, level: status.noiseLevel)
                })
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            SettingRow("Strength") {
                Picker("Strength", selection: binding(status.noiseLevel) { .noise(enabled: true, level: $0) }) {
                    ForEach(model.noiseLevels) { Text($0.name).tag($0.wireValue) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!status.noiseEnabled)

            if let eq = status.eq {
                SettingRow("EQ") {
                    Picker("EQ", selection: binding(eq) { .eq($0) }) {
                        ForEach(EQPreset.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if let reverbEnabled = status.reverbEnabled {
                SettingRow("Reverb") {
                    Picker("Reverb", selection: binding(reverbEnabled ? status.reverbGear : 0) { gear in
                        gear == 0 ? .reverb(enabled: false, gear: status.reverbGear) : .reverb(enabled: true, gear: gear)
                    }) {
                        Text("Off").tag(0)
                        ForEach(Array(LarkSetting.reverbGears), id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if let channelMode = status.channelMode {
                SettingRow("Channels") {
                    Picker("Channels", selection: binding(channelMode) { .channelMode($0) }) {
                        ForEach(ChannelMode.allCases) { Text($0.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .help("Stereo puts Mic 1 on the left channel and Mic 2 on the right.")
            }
        } header: {
            SectionTitle("Sound")
        }
    }

    // MARK: Receiver

    private var receiver: some View {
        DisclosureGroup(isExpanded: $showReceiverSettings) {
            VStack(alignment: .leading, spacing: 8) {
                if let shutdown = status.shutdown {
                    SettingRow("Auto power off") {
                        Picker("Auto power off", selection: binding(shutdown) { .shutdown($0) }) {
                            ForEach(AutoShutdown.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                    .help("Turn the mics off after 15 minutes without a connection.")
                }

                if let signalMode = status.signalMode {
                    SettingRow("Signal") {
                        Picker("Signal", selection: binding(signalMode) { .signal($0) }) {
                            ForEach(SignalMode.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }

                if let lightOn = status.lightOn {
                    toggleRow("Status light", isOn: lightOn) { .light(on: $0) }
                }
                if let performance = status.performanceMode {
                    toggleRow("Performance mode", isOn: performance) { .performanceMode(on: $0) }
                }
                if let identify = status.identify {
                    toggleRow("Identify mics", isOn: identify) { .identify(on: $0) }
                        .help("Blink the transmitters' lights so you can tell them apart.")
                }

                HStack {
                    Spacer()
                    Button(confirmingRestart ? "Click Again to Restart" : "Restart Receiver…") {
                        if confirmingRestart {
                            confirmingRestart = false
                            store.apply(.reboot)
                        } else {
                            confirmingRestart = true
                            Task {
                                try? await Task.sleep(for: .seconds(4))
                                confirmingRestart = false
                            }
                        }
                    }
                    .controlSize(.small)
                    .help("Audio from the mics drops for a few seconds while the receiver restarts.")
                }
                .padding(.top, 2)
            }
            .padding(.top, 8)
        } label: {
            SectionTitle("Receiver")
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showReceiverSettings.toggle() } }
        }
    }

    // MARK: Status

    private var statusLine: some View {
        HStack(spacing: 6) {
            if store.pendingChanges > 0 {
                ProgressView().controlSize(.mini)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var statusColor: Color {
        if store.changeError != nil || status.transmitters.contains(where: \.isLow) { return .orange }
        return status.connectedTransmitters.isEmpty ? .secondary : .green
    }

    private var statusText: String {
        if store.pendingChanges > 0 { return "Applying…" }
        if let changeError = store.changeError { return changeError }
        let count = status.connectedTransmitters.count
        if count == 0 { return "Mics are off or in the case" }
        return "\(count) mic\(count == 1 ? "" : "s") on"
    }

    // MARK: Building blocks

    /// A binding that reads from the latest status and writes through to the receiver.
    private func binding<Value: Equatable>(_ value: Value, _ setting: @escaping (Value) -> LarkSetting) -> Binding<Value> {
        Binding(get: { value }, set: { newValue in
            guard newValue != value else { return }
            store.apply(setting(newValue))
        })
    }

    private func toggleRow(_ title: String, isOn: Bool, _ setting: @escaping (Bool) -> LarkSetting) -> some View {
        SettingRow(title) {
            Toggle(title, isOn: binding(isOn, setting))
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

// MARK: - Pieces

private struct Section<Content: View, Header: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let header: Header

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 12)
            control
                .labelsHidden()
                .fixedSize()
        }
    }
}

private struct MicRow: View {
    let mic: Transmitter
    let canMute: Bool
    let toggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if canMute {
                Button(action: toggleMute) {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(mic.isMuted ? .red : .primary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!mic.isConnected)
                .help(mic.isConnected ? (mic.isMuted ? "Unmute \(mic.name)" : "Mute \(mic.name)") : "\(mic.name) is off")
                .accessibilityLabel(mic.isMuted ? "Unmute \(mic.name)" : "Mute \(mic.name)")
            } else {
                Image(systemName: "mic.fill")
                    .frame(width: 22, height: 22)
            }

            Text(mic.name)
            if mic.isMuted {
                Text("Muted")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer()
            if mic.isConnected {
                Text("\(mic.battery)%")
                    .monospacedDigit()
                    .foregroundStyle(mic.isLow ? .red : .secondary)
                Image(systemName: batterySymbol)
                    .foregroundStyle(mic.isLow ? .red : .secondary)
            } else {
                Text("Off")
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(mic.isConnected ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    private var batterySymbol: String {
        switch mic.battery {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
