import Foundation

// MARK: Setting values

enum ChannelMode: Int, CaseIterable, Identifiable, Sendable {
    case mono = 0, stereo = 1
    var id: Int { rawValue }
    var name: String { self == .mono ? "Mono" : "Stereo" }
}

enum EQPreset: Int, CaseIterable, Identifiable, Sendable {
    case overcast = 1, bright = 2, balance = 3
    var id: Int { rawValue }
    var name: String {
        switch self {
        case .overcast: return "Overcast"
        case .bright: return "Bright"
        case .balance: return "Balance"
        }
    }
}

enum AutoShutdown: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 0, never = 1
    var id: Int { rawValue }
    var name: String { self == .fifteenMinutes ? "After 15 min" : "Never" }
}

enum SignalMode: Int, CaseIterable, Identifiable, Sendable {
    case normal = 0, enhanced = 1
    var id: Int { rawValue }
    var name: String { self == .normal ? "Normal" : "Enhanced" }
}

// MARK: Settings

/// One change a receiver can apply.
enum LarkSetting: Equatable, Sendable {
    /// 0 (quietest) … 5.
    case gain(Int)
    /// `level` is a `NoiseLevel.wireValue`; it's kept when noise cancelling is switched off.
    case noise(enabled: Bool, level: Int)
    /// Transmitter number 1…4.
    case mute(transmitter: Int, muted: Bool)
    case channelMode(ChannelMode)
    case eq(EQPreset)
    /// Gear 1…3; the gear is kept when reverb is switched off.
    case reverb(enabled: Bool, gear: Int)
    case light(on: Bool)
    case shutdown(AutoShutdown)
    case signal(SignalMode)
    case performanceMode(on: Bool)
    case identify(on: Bool)
    case reboot

    static let gainRange = 0...5
    static let reverbGears = 1...3

    /// The commands that apply this setting, in order. Empty if `version` can't apply it.
    func commands(for version: LarkProtocolVersion) -> [(command: UInt8, payload: [UInt8])] {
        switch version {
        case .v2: return v2Command.map { [$0] } ?? []
        case .v1: return v1Commands
        }
    }

    private var v2Command: (command: UInt8, payload: [UInt8])? {
        typealias C = LarkProtocol.V2
        switch self {
        case let .gain(level): return (C.setGain.rawValue, [Self.clampedGain(level)])
        case let .noise(enabled, level): return (C.setNoise.rawValue, [enabled ? 1 : 0, UInt8(clamping: level)])
        case let .mute(transmitter, muted): return (C.setMute.rawValue, [UInt8(clamping: transmitter - 1), muted ? 1 : 0])
        case let .channelMode(mode): return (C.setVoiceMode.rawValue, [UInt8(mode.rawValue)])
        case let .eq(preset): return (C.setEQ.rawValue, [UInt8(preset.rawValue)])
        case let .reverb(enabled, gear):
            let gear = min(max(gear, Self.reverbGears.lowerBound), Self.reverbGears.upperBound)
            return (C.setReverb.rawValue, [enabled ? 1 : 0, UInt8(gear - 1)])
        // The LED flag is inverted on the wire: 0 means on.
        case let .light(on): return (C.setLight.rawValue, [on ? 0 : 1])
        case let .shutdown(value): return (C.setShutdownTime.rawValue, [UInt8(value.rawValue)])
        case let .signal(mode): return (C.setSignalMode.rawValue, [UInt8(mode.rawValue)])
        case let .performanceMode(on): return (C.setPerformanceMode.rawValue, [on ? 1 : 0])
        case let .identify(on): return (C.setIdentify.rawValue, [on ? 1 : 0])
        case .reboot: return (C.reboot.rawValue, [])
        }
    }

    private var v1Commands: [(command: UInt8, payload: [UInt8])] {
        typealias C = LarkProtocol.V1
        switch self {
        case let .gain(level): return [(C.setGain.rawValue, [Self.clampedGain(level)])]
        case let .noise(enabled, level):
            guard enabled else { return [(C.setNoiseEnabled.rawValue, [0])] }
            return [(C.setNoiseEnabled.rawValue, [1]), (C.setNoiseLevel.rawValue, [UInt8(clamping: level)])]
        case .reboot: return [(C.reboot.rawValue, [])]
        default: return []
        }
    }

    private static func clampedGain(_ level: Int) -> UInt8 {
        UInt8(min(max(level, gainRange.lowerBound), gainRange.upperBound))
    }
}

// MARK: Status

struct Transmitter: Equatable, Identifiable, Sendable {
    let index: Int
    var isConnected: Bool
    /// 0–100. Only meaningful while connected.
    var battery: Int
    var isMuted: Bool

    var id: Int { index }
    var name: String { "Mic \(index)" }
    var isLow: Bool { isConnected && battery <= 20 }
}

/// Everything a receiver reports. Settings a model doesn't report are nil and hidden in the UI.
struct ReceiverStatus: Equatable, Sendable {
    var transmitters: [Transmitter]
    var gain: Int
    var noiseEnabled: Bool
    /// A `NoiseLevel.wireValue`.
    var noiseLevel: Int
    var channelMode: ChannelMode?
    var eq: EQPreset?
    var reverbEnabled: Bool?
    /// 1…3.
    var reverbGear: Int
    var shutdown: AutoShutdown?
    var lightOn: Bool?
    var signalMode: SignalMode?
    var identify: Bool?
    /// Not part of the heartbeat; filled in by a separate query where supported.
    var performanceMode: Bool?

    var connectedTransmitters: [Transmitter] { transmitters.filter(\.isConnected) }

    init(heartbeat payload: [UInt8], version: LarkProtocolVersion) throws {
        switch version {
        case .v2: try self.init(v2Heartbeat: payload)
        case .v1: try self.init(v1Heartbeat: payload)
        }
    }

    /// V2 heartbeat:
    ///
    ///     [0/1] TX1/TX2 connected   [2/3] battery   [4/5] muted
    ///     [6] noise on   [7] noise level   [8] gain   [9] channel mode
    ///     [10] auto shutdown   [11] LED (0 = on)   [12] EQ   [13] reverb on   [14] reverb gear
    ///     [15] identify   [16] signal mode   [17…22] TX3/TX4 connected, battery, muted
    private init(v2Heartbeat p: [UInt8]) throws {
        guard p.count >= 6 else { throw StatusError.shortHeartbeat }
        func byte(_ i: Int) -> Int? { i < p.count ? Int(p[i]) : nil }

        var transmitters = [
            Transmitter(index: 1, isConnected: p[0] == 1, battery: Self.percent(p[2]), isMuted: p[4] == 1),
            Transmitter(index: 2, isConnected: p[1] == 1, battery: Self.percent(p[3]), isMuted: p[5] == 1),
        ]
        if p.count >= 23 {
            transmitters += [
                Transmitter(index: 3, isConnected: p[17] == 1, battery: Self.percent(p[19]), isMuted: p[21] == 1),
                Transmitter(index: 4, isConnected: p[18] == 1, battery: Self.percent(p[20]), isMuted: p[22] == 1),
            ]
        }
        self.transmitters = transmitters
        noiseEnabled = byte(6) == 1
        noiseLevel = byte(7) ?? 1
        gain = byte(8) ?? 0
        channelMode = byte(9).flatMap(ChannelMode.init(rawValue:))
        shutdown = byte(10).flatMap(AutoShutdown.init(rawValue:))
        lightOn = byte(11).map { $0 == 0 }
        eq = byte(12).flatMap(EQPreset.init(rawValue:))
        reverbEnabled = byte(13).map { $0 == 1 }
        reverbGear = min(byte(14) ?? 0, 2) + 1
        identify = byte(15).map { $0 == 1 }
        signalMode = byte(16).flatMap(SignalMode.init(rawValue:))
        performanceMode = nil
    }

    /// V1 heartbeat:
    ///
    ///     [0/1] TX1/TX2 connected   [2/3] battery   [4…5] audio level
    ///     [6] noise (0 off, 1 weak, 2 strong)   [7] gain   [8…] firmware-dependent extras
    private init(v1Heartbeat p: [UInt8]) throws {
        guard p.count >= 8 else { throw StatusError.shortHeartbeat }
        transmitters = [
            Transmitter(index: 1, isConnected: p[0] == 1, battery: Self.percent(p[2]), isMuted: false),
            Transmitter(index: 2, isConnected: p[1] == 1, battery: Self.percent(p[3]), isMuted: false),
        ]
        noiseEnabled = p[6] != 0
        noiseLevel = p[6] == 0 ? 2 : Int(p[6])
        gain = Int(p[7])
        reverbGear = 1
    }

    enum StatusError: LocalizedError {
        case shortHeartbeat
        var errorDescription: String? { "Receiver sent an incomplete status" }
    }

    /// The status as it will read once `setting` is applied, so the UI can update immediately.
    func applying(_ setting: LarkSetting) -> ReceiverStatus {
        var next = self
        switch setting {
        case let .gain(level): next.gain = level
        case let .noise(enabled, level): next.noiseEnabled = enabled; next.noiseLevel = level
        case let .mute(transmitter, muted):
            if let i = next.transmitters.firstIndex(where: { $0.index == transmitter }) {
                next.transmitters[i].isMuted = muted
            }
        case let .channelMode(mode): next.channelMode = mode
        case let .eq(preset): next.eq = preset
        case let .reverb(enabled, gear): next.reverbEnabled = enabled; next.reverbGear = gear
        case let .light(on): next.lightOn = on
        case let .shutdown(value): next.shutdown = value
        case let .signal(mode): next.signalMode = mode
        case let .performanceMode(on): next.performanceMode = on
        case let .identify(on): next.identify = on
        case .reboot: break
        }
        return next
    }

    private static func percent(_ byte: UInt8) -> Int { min(Int(byte), 100) }
}
