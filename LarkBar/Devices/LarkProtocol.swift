import Foundation

/// Wire format of the control channel on Hollyland Lark USB receivers.
///
/// The receivers are composite USB devices: a USB audio interface for the mics, plus a vendor HID
/// interface that carries this protocol. Every frame is a 64-byte HID report.
///
/// **V2** (Lark A1, `3547:0407`) uses feature reports with ID `0x05`:
///
///     request  05 03 AA DD <cmd> <len hi> <len lo> <payload…> EF 00…
///     reply    05 03 BB DD <cmd> <len hi> <len lo> <payload…>
///
/// **V1** (Lark M2, `3547:0007`) uses output/input reports with ID `0x55`, and names the target
/// device (0x40 receiver, 0x41/0x42 transmitters) in the header:
///
///     request  55 AA DD <cmd> <target> <len hi> <len lo> <payload…> 00…
///     reply    55 BB DD <cmd> <source> <len hi> <len lo> <payload…>
///
/// The format follows Hollyland's own LarkSound app. It was reverse-engineered by larkctl
/// (github.com/blchinezu/larkctl); the V2 side is verified against a real A1 receiver.
enum LarkProtocol {
    static let reportSize = 64

    static func reportID(for version: LarkProtocolVersion) -> UInt8 {
        version == .v1 ? 0x55 : 0x05
    }

    // MARK: Commands

    enum V2: UInt8 {
        case setVoiceMode = 1
        case setGain = 3
        case setReverb = 5
        case setEQ = 7
        case reboot = 12
        case getVersion = 13
        case setNoise = 19
        case setMute = 22
        /// Status of every paired transmitter and every receiver setting.
        case heartbeat = 31
        case setLight = 33
        case setIdentify = 35
        case setShutdownTime = 39
        case setSignalMode = 63
        case setPerformanceMode = 69
        case getPerformanceMode = 70
    }

    enum V1: UInt8 {
        case getVersion = 0x03
        case setGain = 0x05
        case setNoiseLevel = 0x06
        case reboot = 0x0C
        case heartbeat = 0x10
        case setNoiseEnabled = 0x19
    }

    /// The receiver itself, as a V1 target.
    static let v1Receiver: UInt8 = 0x40

    // MARK: Framing

    static func request(_ version: LarkProtocolVersion, command: UInt8, payload: [UInt8] = []) -> [UInt8] {
        let length = [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
        var frame: [UInt8]
        switch version {
        case .v2:
            frame = [reportID(for: .v2), 0x03, 0xAA, 0xDD, command] + length + payload + [0xEF]
        case .v1:
            frame = [reportID(for: .v1), 0xAA, 0xDD, command, v1Receiver] + length + payload
        }
        frame += [UInt8](repeating: 0, count: max(0, reportSize - frame.count))
        return frame
    }

    /// The payload of a reply to `command`, or nil if `report` isn't one. Accepts buffers with or
    /// without the leading report ID, since IOKit returns either depending on the device.
    static func payload(of report: [UInt8], command: UInt8, version: LarkProtocolVersion) -> [UInt8]? {
        guard let sync = report.indices.dropLast().first(where: { report[$0] == 0xBB && report[$0 + 1] == 0xDD }),
              sync <= 2 else { return nil }
        let commandIndex = sync + 2
        // V1 replies carry the source device between the command and the length.
        let lengthIndex = commandIndex + (version == .v1 ? 2 : 1)
        guard report.count >= lengthIndex + 2, report[commandIndex] == command else { return nil }
        let length = Int(report[lengthIndex]) << 8 | Int(report[lengthIndex + 1])
        let start = lengthIndex + 2
        guard report.count >= start + length else { return nil }
        return Array(report[start..<start + length])
    }

    /// Formats a version reply (`[deviceType?, a, b, c, d]`) as "a.b.c.d".
    static func firmwareVersion(from payload: [UInt8], version: LarkProtocolVersion) -> String? {
        let digits = version == .v2 ? Array(payload.dropFirst()) : payload
        guard digits.count >= 4 else { return nil }
        return digits.prefix(4).map(String.init).joined(separator: ".")
    }
}
