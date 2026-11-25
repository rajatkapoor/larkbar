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
            if let fake = arguments.firstIndex(of: "--fake") {
                // --fake <stereo|mono> <mics on>: made-up mics and voice levels, for layout checks.
                let stereo = arguments[fake + 1] == "stereo"
                store.debugShowFakeReceiver(channelMode: stereo ? .stereo : .mono, micsOn: Int(arguments[fake + 2]) ?? 1)
                store.meter.debugSetLevels([0.72, 0.35])
                UserDefaults.standard.set(true, forKey: "showVoiceLevels")
                try? await Task.sleep(for: .milliseconds(300))
                // Also render the menu bar label in each battery style next to the snapshot.
                for style in MenuBarStyle.allCases {
                    let label = NSHostingView(rootView: MenuBarLabel(store: store, style: style)
                        .padding(4).background(Color(nsColor: NSColor(white: 0.17, alpha: 1))))
                    label.appearance = NSAppearance(named: .darkAqua)
                    label.setFrameSize(label.fittingSize)
                    if let rep = label.bitmapImageRepForCachingDisplay(in: label.bounds) {
                        label.cacheDisplay(in: label.bounds, to: rep)
                        let url = output.deletingPathExtension().appendingPathExtension("label-\(style.rawValue).png")
                        try? rep.representation(using: .png, properties: [:])?.write(to: url)
                    }
                }
            }
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
