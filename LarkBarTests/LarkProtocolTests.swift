import Foundation
import Testing
@testable import LarkBar

struct LarkProtocolTests {
    // MARK: V2 (Lark A1)

    @Test("V2 heartbeat request matches the A1 wire format")
    func v2HeartbeatRequest() {
        let frame = LarkProtocol.request(.v2, command: LarkProtocol.V2.heartbeat.rawValue)
        #expect(frame.count == 64)
        #expect(Array(frame.prefix(8)) == [0x05, 0x03, 0xAA, 0xDD, 0x1F, 0x00, 0x00, 0xEF])
        #expect(frame.dropFirst(8).allSatisfy { $0 == 0 })
    }

    @Test("Parses a real A1 reply with both mics in the case")
    func parsesIdleA1Reply() throws {
        // Captured from a Lark A1 USB-C receiver (3547:0407), firmware 1.0.2.12.
        let reply: [UInt8] = [0x05, 0x03, 0xBB, 0xDD, 0x1F, 0x00, 0x11,
                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x04,
                              0x00, 0x00, 0x00, 0x03, 0x00, 0x02, 0x00, 0x00, 0x6E]
            + [UInt8](repeating: 0, count: 39)
        let payload = try #require(LarkProtocol.payload(of: reply, command: 0x1F, version: .v2))
        #expect(payload.count == 17)
        let status = try ReceiverStatus(heartbeat: payload, version: .v2)
        #expect(status.transmitters.count == 2)
        #expect(status.connectedTransmitters.isEmpty)
        #expect(status.noiseEnabled)
        #expect(status.noiseLevel == 2)
        #expect(status.gain == 4)
        #expect(status.channelMode == .mono)
        #expect(status.shutdown == .fifteenMinutes)
        #expect(status.lightOn == true)
        #expect(status.eq == .balance)
        #expect(status.reverbEnabled == false)
        #expect(status.reverbGear == 3)
        #expect(status.signalMode == .normal)
    }

    @Test("Reads battery and mute per mic, with or without the report ID")
    func parsesBattery() throws {
        var payload = [UInt8](repeating: 0, count: 17)
        payload[0] = 1; payload[1] = 1
        payload[2] = 87; payload[3] = 15
        payload[5] = 1
        let reply: [UInt8] = [0x03, 0xBB, 0xDD, 0x1F, 0x00, 0x11] + payload
        let parsed = try #require(LarkProtocol.payload(of: reply, command: 0x1F, version: .v2))
        let status = try ReceiverStatus(heartbeat: parsed, version: .v2)
        #expect(status.transmitters[0] == Transmitter(index: 1, isConnected: true, battery: 87, isMuted: false))
        #expect(status.transmitters[1] == Transmitter(index: 2, isConnected: true, battery: 15, isMuted: true))
        #expect(status.transmitters[1].isLow)
    }

    @Test("A 23-byte heartbeat adds mics 3 and 4")
    func parsesFourMics() throws {
        var payload = [UInt8](repeating: 0, count: 23)
        payload[17] = 1; payload[19] = 64; payload[21] = 1
        let status = try ReceiverStatus(heartbeat: payload, version: .v2)
        #expect(status.transmitters.count == 4)
        #expect(status.transmitters[2] == Transmitter(index: 3, isConnected: true, battery: 64, isMuted: true))
        #expect(!status.transmitters[3].isConnected)
    }

    @Test("Rejects echoes and replies to other commands")
    func rejectsOtherFrames() {
        #expect(LarkProtocol.payload(of: LarkProtocol.request(.v2, command: 0x1F), command: 0x1F, version: .v2) == nil)
        #expect(LarkProtocol.payload(of: [0x05, 0x03, 0xBB, 0xDD, 0x0D, 0x00, 0x00], command: 0x1F, version: .v2) == nil)
        #expect(throws: ReceiverStatus.StatusError.self) { try ReceiverStatus(heartbeat: [1, 0], version: .v2) }
    }

    @Test("Every V2 setting encodes to the command and payload the A1 expects")
    func v2SettingPayloads() {
        let cases: [(LarkSetting, UInt8, [UInt8])] = [
            (.gain(4), 3, [4]),
            (.gain(9), 3, [5]),
            (.noise(enabled: true, level: 1), 19, [1, 1]),
            (.noise(enabled: false, level: 2), 19, [0, 2]),
            (.mute(transmitter: 2, muted: true), 22, [1, 1]),
            (.channelMode(.stereo), 1, [1]),
            (.eq(.bright), 7, [2]),
            (.reverb(enabled: true, gear: 1), 5, [1, 0]),
            (.reverb(enabled: false, gear: 3), 5, [0, 2]),
            (.light(on: true), 33, [0]),
            (.light(on: false), 33, [1]),
            (.shutdown(.never), 39, [1]),
            (.signal(.enhanced), 63, [1]),
            (.performanceMode(on: false), 69, [0]),
            (.identify(on: true), 35, [1]),
            (.reboot, 12, []),
        ]
        for (setting, command, payload) in cases {
            let commands = setting.commands(for: .v2)
            #expect(commands.count == 1, "\(setting)")
            #expect(commands.first?.command == command, "\(setting)")
            #expect(commands.first?.payload == payload, "\(setting)")
        }
        let frame = LarkProtocol.request(.v2, command: 19, payload: [1, 2])
        #expect(Array(frame.prefix(10)) == [0x05, 0x03, 0xAA, 0xDD, 19, 0x00, 0x02, 1, 2, 0xEF])
    }

    @Test("Firmware version reply skips the device type byte")
    func firmwareVersion() {
        #expect(LarkProtocol.firmwareVersion(from: [0, 1, 0, 2, 12], version: .v2) == "1.0.2.12")
        #expect(LarkProtocol.firmwareVersion(from: [2, 0, 0, 33], version: .v1) == "2.0.0.33")
        #expect(LarkProtocol.firmwareVersion(from: [0, 1], version: .v2) == nil)
    }

    // MARK: V1 (Lark M2)

    @Test("V1 requests target the receiver and carry no end marker")
    func v1Request() {
        let frame = LarkProtocol.request(.v1, command: 0x05, payload: [3])
        #expect(frame.count == 64)
        #expect(Array(frame.prefix(9)) == [0x55, 0xAA, 0xDD, 0x05, 0x40, 0x00, 0x01, 3, 0])
    }

    @Test("V1 replies carry a source byte before the length")
    func v1Reply() throws {
        let reply: [UInt8] = [0x55, 0xBB, 0xDD, 0x10, 0x80, 0x00, 0x08, 1, 0, 72, 0, 0, 0, 2, 3]
        let payload = try #require(LarkProtocol.payload(of: reply, command: 0x10, version: .v1))
        let status = try ReceiverStatus(heartbeat: payload, version: .v1)
        #expect(status.transmitters == [
            Transmitter(index: 1, isConnected: true, battery: 72, isMuted: false),
            Transmitter(index: 2, isConnected: false, battery: 0, isMuted: false),
        ])
        #expect(status.noiseEnabled)
        #expect(status.noiseLevel == 2)
        #expect(status.gain == 3)
        #expect(status.eq == nil && status.reverbEnabled == nil && status.lightOn == nil)
    }

    @Test("V1 noise and gain map to the M2's separate commands; unsupported settings are empty")
    func v1Settings() {
        #expect(LarkSetting.noise(enabled: false, level: 2).commands(for: .v1).map(\.command) == [0x19])
        let on = LarkSetting.noise(enabled: true, level: 1).commands(for: .v1)
        #expect(on.map(\.command) == [0x19, 0x06])
        #expect(on.map(\.payload) == [[1], [1]])
        #expect(LarkSetting.gain(2).commands(for: .v1).first?.payload == [2])
        #expect(LarkSetting.eq(.bright).commands(for: .v1).isEmpty)
        #expect(LarkSetting.mute(transmitter: 1, muted: true).commands(for: .v1).isEmpty)
    }

    // MARK: Models

    @Test("Known receivers are matched by product ID")
    func models() {
        #expect(LarkModel.model(productID: 0x0407) == .larkA1)
        #expect(LarkModel.model(productID: 0x0007) == .larkM2)
        #expect(LarkModel.model(productID: 0x1234) == nil)
    }

    @Test("Optimistic updates show the change before the receiver confirms")
    func optimisticApply() throws {
        var payload = [UInt8](repeating: 0, count: 17)
        payload[0] = 1
        let status = try ReceiverStatus(heartbeat: payload, version: .v2)
        #expect(status.applying(.mute(transmitter: 1, muted: true)).transmitters[0].isMuted)
        #expect(status.applying(.reverb(enabled: true, gear: 2)).reverbGear == 2)
        #expect(status.applying(.light(on: false)).lightOn == false)
    }
}

struct InputLevelMeterTests {
    @Test("Decibels map onto the meter's 0…1 range")
    func normalizesDecibels() {
        #expect(InputLevelMeter.normalized(0) == 1)
        #expect(InputLevelMeter.normalized(-30) == 0.5)
        #expect(InputLevelMeter.normalized(-80) == 0)
        #expect(InputLevelMeter.normalized(6) == 1)
        #expect(InputLevelMeter.normalized(-.infinity) == 0)
    }
}
