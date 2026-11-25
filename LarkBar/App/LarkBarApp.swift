import SwiftUI

@main
struct LarkBarApp: App {
    @State private var store: ReceiverStore
    @AppStorage(MenuBarStyle.storageKey) private var menuBarStyle = MenuBarStyle.battery

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
            MenuBarLabel(store: store, style: menuBarStyle)
        }
        .menuBarExtraStyle(.window)
    }
}
