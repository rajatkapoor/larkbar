@preconcurrency import AVFoundation
import Observation

/// Live input levels from the receiver's own USB audio interface, so you can see your voice
/// coming in. Audio is only measured, never recorded or sent anywhere, and only while running.
@MainActor
@Observable
final class InputLevelMeter {
    enum Access: Equatable {
        case notAsked, granted, denied
    }

    /// 0…1 per audio channel. Empty while not running.
    private(set) var levels: [Float] = []
    /// Set when the receiver's audio input couldn't be found or opened.
    private(set) var problem: String?

    private var capture: Capture?

    #if DEBUG
    /// Debug snapshots only: fixed levels and access, instead of real audio.
    var debugLevels: [Float]? { didSet { levels = debugLevels ?? [] } }
    #endif

    var access: Access {
        #if DEBUG
        if debugLevels != nil { return .granted }
        #endif
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Asks for microphone access. Returns whether it was granted.
    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Starts measuring the audio input that belongs to the receiver with this USB ID ("3547:0407").
    func start(usbID: String) async {
        #if DEBUG
        if debugLevels != nil { return }
        #endif
        guard capture == nil, access == .granted else { return }
        guard let device = Self.audioDevice(usbID: usbID) else {
            problem = "The receiver's audio input isn't available"
            return
        }
        let capture = Capture(device: device)
        do {
            try await capture.start()
            self.capture = capture
            problem = nil
        } catch {
            problem = "Couldn't read the receiver's audio: \(error.localizedDescription)"
        }
    }

    /// Reads the latest levels. Call repeatedly while running.
    func poll() {
        #if DEBUG
        if debugLevels != nil { return }
        #endif
        guard let capture else { return }
        levels = capture.channelPowers().map(Self.normalized)
    }

    func stop() {
        capture?.stop()
        capture = nil
        levels = []
    }

    /// The receiver's audio device. macOS reports USB audio model IDs as "<name>:<vid>:<pid>".
    nonisolated static func audioDevice(usbID: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices
            .first { $0.modelID.lowercased().hasSuffix(":" + usbID.lowercased()) }
    }

    /// Maps decibels (-60…0 dBFS) to 0…1, the range speech moves through.
    nonisolated static func normalized(_ decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        return min(max((decibels + 60) / 60, 0), 1)
    }
}

/// An AVCaptureSession that only measures levels. Lives off the main actor because starting and
/// stopping a session blocks.
private final class Capture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "com.ubiqapps.larkbar.levels")
    private let device: AVCaptureDevice

    init(device: AVCaptureDevice) {
        self.device = device
    }

    func start() async throws {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CocoaError(.featureUnsupported)
        }
        session.addInput(input)
        // The samples themselves are dropped; the connection's channel meters do the measuring.
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        session.commitConfiguration()
        await withCheckedContinuation { continuation in
            queue.async {
                self.session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    /// Average power per channel, in dBFS.
    func channelPowers() -> [Float] {
        output.connections.first?.audioChannels.map(\.averagePowerLevel) ?? []
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {}
}
