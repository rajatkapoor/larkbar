import SwiftUI

/// Mics, sound and receiver settings for a connected receiver. Only what the receiver reports is shown.
struct ReceiverControls: View {
    let store: ReceiverStore
    let model: LarkModel
    let status: ReceiverStatus

    @AppStorage("showReceiverSettings") private var showReceiverSettings = false
    @AppStorage("showVoiceLevels") private var showVoiceLevels = false
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
                MicRow(mic: mic, canMute: model.supportsMute, level: level(for: mic)) {
                    store.apply(.mute(transmitter: mic.index, muted: !mic.isMuted))
                }
            }
            if !status.connectedTransmitters.isEmpty {
                voiceLevels
            }
        } header: {
            SectionTitle("Mics")
        }
    }

    // MARK: Voice levels

    private var isMeasuring: Bool {
        showVoiceLevels && store.meter.access == .granted && store.meter.problem == nil
    }

    /// Stereo puts Mic 1 on the left channel and Mic 2 on the right, so each mic has its own level.
    private var hasPerMicChannels: Bool { status.channelMode == .stereo }

    /// The level to show inside a mic's row, when it can be told apart from the others.
    /// Mono mixes every mic into one signal, so it's only attributable when a single mic is on.
    private func level(for mic: Transmitter) -> Float? {
        guard isMeasuring, mic.isConnected else { return nil }
        let levels = store.meter.levels
        if hasPerMicChannels {
            let channel = mic.index - 1
            return channel < levels.count ? levels[channel] : 0
        }
        return status.connectedTransmitters.count == 1 ? (levels.max() ?? 0) : nil
    }

    @ViewBuilder
    private var voiceLevels: some View {
        let meter = store.meter
        if showVoiceLevels && meter.access == .granted {
            VStack(alignment: .leading, spacing: 6) {
                if let problem = meter.problem {
                    Text(problem).font(.caption).foregroundStyle(.secondary)
                } else if !hasPerMicChannels && status.connectedTransmitters.count > 1 {
                    // In Mono the receiver mixes the mics, so only their combined level exists.
                    LevelRow(title: "All mics", level: meter.levels.max() ?? 0)
                        .help("In Mono the receiver mixes the mics together. Switch Channels to Stereo for a level per mic.")
                }
                HStack {
                    Spacer()
                    Button("Hide Voice Levels") { showVoiceLevels = false }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(.top, 2)
            .task(id: store.device?.usbID) {
                guard let usbID = store.device?.usbID else { return }
                await meter.start(usbID: usbID)
                while !Task.isCancelled {
                    meter.poll()
                    try? await Task.sleep(for: .milliseconds(50))
                }
                meter.stop()
            }
        } else if showVoiceLevels && meter.access == .denied {
            VStack(alignment: .leading, spacing: 4) {
                Text("To show voice levels, allow LarkBar to use the microphone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                    }
                    Button("Hide") { showVoiceLevels = false }
                }
                .controlSize(.small)
            }
        } else {
            Button {
                Task {
                    if meter.access == .notAsked { _ = await meter.requestAccess() }
                    showVoiceLevels = true
                }
            } label: {
                Label("Show Voice Levels", systemImage: "waveform")
            }
            .controlSize(.small)
            .help("Shows how loud your voice is coming in, next to each mic. In Mono with several mics on, the receiver mixes them, so you get one combined bar. LarkBar only measures the level; it never records audio.")
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
            SectionTitle("Sound (all mics)")
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

/// A label and a level meter, for the combined level of several mics.
private struct LevelRow: View {
    let title: String
    let level: Float

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            LevelMeter(level: level, segments: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// A segmented level meter, like the input level meter in Sound settings.
private struct LevelMeter: View {
    let level: Float
    let segments: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < lit ? color(for: index) : Color.primary.opacity(0.12))
            }
        }
        .frame(height: 8)
        .animation(.linear(duration: 0.08), value: lit)
    }

    private var lit: Int { Int((level * Float(segments)).rounded()) }

    private func color(for index: Int) -> Color {
        let position = Double(index) / Double(segments)
        if position >= 0.9 { return .red }
        if position >= 0.75 { return .yellow }
        return .green
    }
}

private struct MicRow: View {
    let mic: Transmitter
    let canMute: Bool
    /// Voice level 0…1, shown when it can be measured for this mic.
    let level: Float?
    let toggleMute: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if canMute {
                Button(action: toggleMute) {
                    Image(systemName: mic.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mic.isMuted ? Color.white : Color.primary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(mic.isMuted ? Color.red : Color.primary.opacity(0.1)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!mic.isConnected)
                .help(mic.isConnected ? (mic.isMuted ? "Unmute \(mic.name)" : "Mute \(mic.name)") : "\(mic.name) is off")
                .accessibilityLabel(mic.isMuted ? "Unmute \(mic.name)" : "Mute \(mic.name)")
            } else {
                Image(systemName: "mic.fill")
                    .frame(width: 28, height: 28)
            }

            Text(mic.name)
            if mic.isMuted {
                Text("Muted")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 8)
            if let level {
                LevelMeter(level: level, segments: 14)
                    .frame(width: 96)
                    .accessibilityLabel("\(mic.name) voice level")
                    .accessibilityValue("\(Int(level * 100)) percent")
            }
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
