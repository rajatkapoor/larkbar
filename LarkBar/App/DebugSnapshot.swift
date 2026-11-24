#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only: `LarkBar --snapshot /path/out.png [--expanded]` renders the menu window to a
/// PNG once the receiver has been read, then quits. Used to check layout without clicking the menu.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(store: ReceiverStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
        let output = URL(fileURLWithPath: arguments[index + 1])
        UserDefaults.standard.set(arguments.contains("--expanded"), forKey: "showReceiverSettings")

        Task { @MainActor in
            store.isMenuOpen = true
            try? await Task.sleep(for: .seconds(3))
            let light = arguments.contains("--light")
            let host = NSHostingView(rootView: MenuContentView(store: store)
                .background(Color(nsColor: light ? .white : NSColor(white: 0.17, alpha: 1))))
            host.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
            let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(1))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: output)
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
