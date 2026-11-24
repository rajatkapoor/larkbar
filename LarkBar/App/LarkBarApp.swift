import SwiftUI

@main
struct LarkBarApp: App {
    @State private var store: ReceiverStore
    @AppStorage("showBatteryInMenuBar") private var showBatteryInMenuBar = true

    init() {
        let store = ReceiverStore()
        store.start()
        _store = State(initialValue: store)
        #if DEBUG
        DebugSnapshot.runIfRequested(store: store)
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store, showBattery: showBatteryInMenuBar)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon: a mic, with the lowest mic battery next to it when mics are on.
struct MenuBarLabel: View {
    let store: ReceiverStore
    let showBattery: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if showBattery, let lowest {
                Text("\(lowest.battery)%")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText)
    }

    private var lowest: Transmitter? {
        store.status?.connectedTransmitters.min { $0.battery < $1.battery }
    }

    private var symbol: String {
        switch store.state {
        case .noDevice, .unsupported: return "mic.slash"
        case .connecting, .failed: return "mic"
        case let .connected(_, status):
            if status.transmitters.contains(where: \.isLow) { return "mic.badge.xmark" }
            return status.connectedTransmitters.isEmpty ? "mic" : "mic.fill"
        }
    }

    private var accessibilityText: String {
        guard let lowest else { return "LarkBar" }
        return "LarkBar, lowest mic battery \(lowest.battery) percent"
    }
}
