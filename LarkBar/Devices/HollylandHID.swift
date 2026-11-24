import Foundation
import IOKit.hid

/// A Hollyland USB device plugged into the Mac, known model or not.
struct HollylandDevice: Equatable, Identifiable, Sendable {
    /// USB location, stable while the device stays in the same port.
    let locationID: Int
    let productID: Int
    let productName: String
    let model: LarkModel?

    var id: Int { locationID }
    var displayName: String { model.map { "Hollyland \($0.name)" } ?? productName }
    var usbID: String { String(format: "%04x:%04x", LarkModel.vendorID, productID) }
}

/// Finds Hollyland receivers over IOKit HID and talks to their control interface.
///
/// Only the HID side of the receiver is touched, so the mics' audio keeps working while LarkBar
/// polls. All device I/O blocks; call it off the main thread. Plug/unplug notifications arrive on
/// the main run loop.
final class HollylandHID: @unchecked Sendable {
    enum HIDError: LocalizedError {
        case notConnected
        case unsupported
        case transferFailed(step: String, code: IOReturn)
        case noReply
        case refusedNoMic
        case refused(UInt8)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Receiver isn't plugged in"
            case .unsupported: return "This receiver can't change that setting"
            case let .transferFailed(step, code): return "Receiver \(step) failed (\(String(format: "0x%08X", code)))"
            case .noReply: return "Receiver didn't answer"
            case .refusedNoMic: return "That mic isn't connected"
            case let .refused(code): return "Receiver refused the change (status \(code))"
            }
        }
    }

    /// Called on the main thread when a Hollyland device is plugged in or removed.
    var onDevicesChanged: (@MainActor () -> Void)?

    private let lock = NSLock()
    private let manager: IOHIDManager

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: LarkModel.vendorID] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let changed: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            let hid = Unmanaged<HollylandHID>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hid.onDevicesChanged?() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, changed, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, changed, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Every Hollyland device currently plugged in, one entry per physical device.
    func devices() -> [HollylandDevice] {
        var seen = Set<Int>()
        return hidDevices()
            .sorted { locationID(of: $0) < locationID(of: $1) }
            .compactMap { device in
                let location = locationID(of: device)
                guard seen.insert(location).inserted else { return nil }
                let productID = intProperty(device, kIOHIDProductIDKey)
                let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String
                return HollylandDevice(locationID: location,
                                       productID: productID,
                                       productName: name ?? "Hollyland device",
                                       model: LarkModel.model(productID: productID))
            }
    }

    /// Reads the receiver's status, plus the extras the heartbeat doesn't carry.
    func status(of device: HollylandDevice) throws -> ReceiverStatus {
        try withControlInterface(of: device) { hid, version in
            let heartbeat = version == .v2 ? LarkProtocol.V2.heartbeat.rawValue : LarkProtocol.V1.heartbeat.rawValue
            var status = try ReceiverStatus(heartbeat: exchange(heartbeat, on: hid, version: version), version: version)
            if version == .v2,
               let flag = try? exchange(LarkProtocol.V2.getPerformanceMode.rawValue, on: hid, version: version).first {
                status.performanceMode = flag == 1
            }
            return status
        }
    }

    /// The receiver's firmware version, e.g. "1.0.2.12".
    func firmwareVersion(of device: HollylandDevice) -> String? {
        try? withControlInterface(of: device) { hid, version in
            let reply = version == .v2
                ? try exchange(LarkProtocol.V2.getVersion.rawValue, payload: [0], on: hid, version: version)
                : try exchange(LarkProtocol.V1.getVersion.rawValue, on: hid, version: version)
            return LarkProtocol.firmwareVersion(from: reply, version: version)
        }
    }

    /// Applies one setting and checks the receiver accepted it.
    func apply(_ setting: LarkSetting, to device: HollylandDevice) throws {
        try withControlInterface(of: device) { hid, version in
            let commands = setting.commands(for: version)
            guard !commands.isEmpty else { throw HIDError.unsupported }
            for (command, payload) in commands {
                let reply: [UInt8]
                do {
                    reply = try exchange(command, payload: payload, on: hid, version: version, isSet: true)
                } catch HIDError.noReply where setting == .reboot || version == .v1 {
                    // A rebooting receiver drops off USB before it answers, and some V1 firmware
                    // applies changes without acknowledging them.
                    continue
                }
                guard let code = reply.first, code != 0 else { continue }
                throw code == 0xFF ? HIDError.refusedNoMic : HIDError.refused(code)
            }
        }
    }

    // MARK: Device access

    private func withControlInterface<T>(of device: HollylandDevice,
                                         _ body: (IOHIDDevice, LarkProtocolVersion) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        guard let model = device.model else { throw HIDError.unsupported }
        guard let hid = controlInterface(of: device, version: model.protocolVersion) else { throw HIDError.notConnected }
        let openResult = IOHIDDeviceOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw HIDError.transferFailed(step: "open", code: openResult) }
        defer { IOHIDDeviceClose(hid, IOOptionBits(kIOHIDOptionsTypeNone)) }
        return try body(hid, model.protocolVersion)
    }

    /// The HID interface that carries the control protocol: the one whose reports fit a whole frame.
    private func controlInterface(of device: HollylandDevice, version: LarkProtocolVersion) -> IOHIDDevice? {
        let sizeKey = version == .v2 ? kIOHIDMaxFeatureReportSizeKey : kIOHIDMaxOutputReportSizeKey
        return hidDevices().first { hid in
            locationID(of: hid) == device.locationID
                && intProperty(hid, kIOHIDProductIDKey) == device.productID
                && intProperty(hid, sizeKey) >= LarkProtocol.reportSize - 1
        }
    }

    private func hidDevices() -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    private func locationID(of device: IOHIDDevice) -> Int { intProperty(device, kIOHIDLocationIDKey) }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0
    }

    // MARK: Exchanges

    /// One request/reply round trip.
    private func exchange(_ command: UInt8, payload: [UInt8] = [], on device: IOHIDDevice,
                          version: LarkProtocolVersion, isSet: Bool = false) throws -> [UInt8] {
        switch version {
        case .v2: return try featureExchange(command, payload: payload, on: device)
        case .v1: return try interruptExchange(command, payload: payload, on: device, timeout: isSet ? 0.5 : 2)
        }
    }

    /// V2: SET_REPORT the frame as a feature report, then GET_REPORT until the matching reply.
    private func featureExchange(_ command: UInt8, payload: [UInt8], on device: IOHIDDevice) throws -> [UInt8] {
        let reportID = LarkProtocol.reportID(for: .v2)
        let request = LarkProtocol.request(.v2, command: command, payload: payload)
        let setResult = IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), request, request.count)
        guard setResult == kIOReturnSuccess else { throw HIDError.transferFailed(step: "request", code: setResult) }

        // The reply is usually ready immediately; give slow firmware a few tries.
        for attempt in 0..<5 {
            if attempt > 0 { usleep(20_000) }
            var buffer = [UInt8](repeating: 0, count: LarkProtocol.reportSize)
            var length = CFIndex(buffer.count)
            let getResult = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(reportID), &buffer, &length)
            guard getResult == kIOReturnSuccess else { throw HIDError.transferFailed(step: "read", code: getResult) }
            if let reply = LarkProtocol.payload(of: Array(buffer.prefix(length)), command: command, version: .v2) {
                return reply
            }
        }
        throw HIDError.noReply
    }

    /// V1: write the frame as an output report, then wait for the matching input report.
    private func interruptExchange(_ command: UInt8, payload: [UInt8], on device: IOHIDDevice,
                                   timeout: TimeInterval) throws -> [UInt8] {
        let collector = InputCollector()
        let context = Unmanaged.passUnretained(collector).toOpaque()
        let callback: IOHIDReportCallback = { context, _, _, _, _, report, length in
            guard let context else { return }
            Unmanaged<InputCollector>.fromOpaque(context).takeUnretainedValue()
                .receive(Array(UnsafeBufferPointer(start: report, count: length)))
        }
        IOHIDDeviceRegisterInputReportCallback(device, collector.buffer, LarkProtocol.reportSize, callback, context)
        defer { IOHIDDeviceRegisterInputReportCallback(device, collector.buffer, LarkProtocol.reportSize, nil, nil) }

        let reportID = LarkProtocol.reportID(for: .v1)
        let request = LarkProtocol.request(.v1, command: command, payload: payload)
        let setResult = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(reportID), request, request.count)
        guard setResult == kIOReturnSuccess else { throw HIDError.transferFailed(step: "request", code: setResult) }

        let deadline = Date().addingTimeInterval(timeout)
        while let report = collector.next(before: deadline) {
            if let reply = LarkProtocol.payload(of: report, command: command, version: .v1) {
                return reply
            }
        }
        throw HIDError.noReply
    }
}

/// Buffers input reports delivered on the main run loop for a waiting background thread.
private final class InputCollector: @unchecked Sendable {
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: LarkProtocol.reportSize)
    private let lock = NSLock()
    private let available = DispatchSemaphore(value: 0)
    private var reports: [[UInt8]] = []

    deinit { buffer.deallocate() }

    func receive(_ report: [UInt8]) {
        lock.withLock { reports.append(report) }
        available.signal()
    }

    func next(before deadline: Date) -> [UInt8]? {
        let wait = deadline.timeIntervalSinceNow
        guard wait > 0, available.wait(timeout: .now() + wait) == .success else { return nil }
        return lock.withLock { reports.removeFirst() }
    }
}
