import AppKit
import Observation
import Sparkle

/// Sparkle auto-update. The feed (SUFeedURL in Info.plist) is appcast.xml on the latest GitHub
/// release of this repo. Every update zip is EdDSA-signed (SUPublicEDKey), so Sparkle refuses
/// anything not signed with our key. Checks run once a day, plus "Check for Updates…" in the menu.
@MainActor
@Observable
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    /// Set when a check finds a newer version, so the menu can show it.
    private(set) var availableVersion: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    private override init() {
        super.init()
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }

    // MARK: SPUStandardUserDriverDelegate

    // LarkBar has no Dock icon: bring Sparkle's window forward for scheduled checks too.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        Task { @MainActor in NSApp.activate(ignoringOtherApps: true) }
        return true
    }
}
