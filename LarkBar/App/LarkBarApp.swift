import SwiftUI

@main
struct LarkBarApp: App {
    @State private var store: ReceiverStore
    @AppStorage(MenuBarStyle.storageKey) private var menuBarStyle = MenuBarStyle.battery

    init() {
        let store = ReceiverStore()
        store.start()
        _store = State(initialValue: store)
        _ = Updater.shared // start Sparkle's daily update checks
        #if DEBUG
        DebugSnapshot.runIfRequested(store: store)
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store, style: menuBarStyle)
        }
        .menuBarExtraStyle(.window)
    }
}
