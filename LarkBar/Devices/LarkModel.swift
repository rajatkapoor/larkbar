import Foundation

/// Which wire protocol a receiver speaks. See `LarkProtocol` for the byte layouts.
enum LarkProtocolVersion: Sendable {
    /// Lark M2 family: 64-byte interrupt reports with ID `0x55`.
    case v1
    /// Lark A1 family: 64-byte feature reports with ID `0x05`.
    case v2
}

/// A noise-cancelling strength as the receiver encodes it.
struct NoiseLevel: Hashable, Identifiable, Sendable {
    let wireValue: Int
    let name: String
    var id: Int { wireValue }
}

/// A Hollyland receiver model LarkBar knows how to talk to.
struct LarkModel: Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let productID: Int
    let protocolVersion: LarkProtocolVersion
    /// Transmitters the receiver can pair with at once.
    let maxMics: Int
    let noiseLevels: [NoiseLevel]
    let supportsMute: Bool
    /// Tested against real hardware. Unverified models are shown as experimental.
    let isVerified: Bool

    /// Hollyland's USB vendor ID.
    static let vendorID = 0x3547

    static let larkA1 = LarkModel(
        id: "a1",
        name: "Lark A1",
        productID: 0x0407,
        protocolVersion: .v2,
        maxMics: 4,
        noiseLevels: [
            NoiseLevel(wireValue: 0, name: "Low"),
            NoiseLevel(wireValue: 1, name: "Medium"),
            NoiseLevel(wireValue: 2, name: "Strong"),
        ],
        supportsMute: true,
        isVerified: true
    )

    static let larkM2 = LarkModel(
        id: "m2",
        name: "Lark M2",
        productID: 0x0007,
        protocolVersion: .v1,
        maxMics: 2,
        noiseLevels: [
            NoiseLevel(wireValue: 1, name: "Weak"),
            NoiseLevel(wireValue: 2, name: "Strong"),
        ],
        supportsMute: false,
        isVerified: false
    )

    static let all: [LarkModel] = [.larkA1, .larkM2]

    static func model(productID: Int) -> LarkModel? {
        all.first { $0.productID == productID }
    }
}
