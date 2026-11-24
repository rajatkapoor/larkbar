import Foundation
import Observation
import OSLog

/// What LarkBar knows about the plugged-in receiver, kept fresh by plug notifications and polling.
@MainActor
@Observable
final class ReceiverStore {
    enum State: Equatable {
        /// No Hollyland device is plugged in.
        case noDevice
        /// A Hollyland device LarkBar doesn't know how to control yet.
        case unsupported(HollylandDevice)
        /// A known receiver, before its first status read.
        case connecting(HollylandDevice)
        case connected(HollylandDevice, ReceiverStatus)
        case failed(HollylandDevice, String)
    }

    private(set) var state: State = .noDevice
    private(set) var firmwareVersion: String?
    /// Last failed change, shown until the next successful one.
    private(set) var changeError: String?
    /// Changes still in flight. Polling pauses so it can't overwrite them with stale values.
    private(set) var pendingChanges = 0

    /// Polls quickly while the menu is open so mics powering on or off show up promptly.
    var isMenuOpen = false {
        didSet { if isMenuOpen { Task { await refresh() } } }
    }

    private static let logger = Logger(subsystem: "com.ubiqapps.larkbar", category: "Receiver")
    private let hid = HollylandHID()
    private var isRefreshing = false
    private var pollTask: Task<Void, Never>?

    init() {
        hid.onDevicesChanged = { [weak self] in
            Task { await self?.refresh() }
        }
    }

    var device: HollylandDevice? {
        switch state {
        case .noDevice: return nil
        case let .unsupported(device), let .connecting(device),
             let .connected(device, _), let .failed(device, _): return device
        }
    }

    var status: ReceiverStatus? {
        if case let .connected(_, status) = state { return status }
        return nil
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval: Duration = (self?.isMenuOpen ?? false) ? .seconds(2) : .seconds(30)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Applies a change, showing it immediately and rolling back to the receiver's real state if
    /// it's refused.
    func apply(_ setting: LarkSetting) {
        guard case let .connected(device, current) = state else { return }
        if setting != .reboot {
            state = .connected(device, current.applying(setting))
        }
        pendingChanges += 1
        let hid = hid
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
                Result { try hid.apply(setting, to: device) }
            }.value
            pendingChanges -= 1
            switch result {
            case .success:
                changeError = nil
            case let .failure(error):
                Self.logger.error("Change failed: \(error.localizedDescription, privacy: .public)")
                changeError = error.localizedDescription
            }
            if setting == .reboot {
                firmwareVersion = nil
                try? await Task.sleep(for: .seconds(3))
            }
            if pendingChanges == 0 {
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !isRefreshing, pendingChanges == 0 else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let hid = hid
        let devices = await Task.detached(priority: .utility) { hid.devices() }.value
        // Prefer a receiver we can control over some other Hollyland accessory.
        guard let device = devices.first(where: { $0.model != nil }) ?? devices.first else {
            state = .noDevice
            firmwareVersion = nil
            changeError = nil
            return
        }
        guard device.model != nil else {
            state = .unsupported(device)
            return
        }
        if self.device != device {
            state = .connecting(device)
            firmwareVersion = nil
            changeError = nil
        }

        let result = await Task.detached(priority: .utility) { () -> Result<ReceiverStatus, Error> in
            Result { try hid.status(of: device) }
        }.value
        // A change may have started while the read was in flight; its optimistic state wins.
        guard pendingChanges == 0 else { return }

        switch result {
        case let .success(status):
            state = .connected(device, status)
            if firmwareVersion == nil {
                firmwareVersion = await Task.detached(priority: .utility) { hid.firmwareVersion(of: device) }.value
            }
        case let .failure(error):
            if case HollylandHID.HIDError.notConnected = error {
                state = .noDevice
            } else {
                Self.logger.error("Status failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(device, error.localizedDescription)
            }
        }
    }
}
