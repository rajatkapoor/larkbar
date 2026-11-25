import SwiftUI

/// What the menu bar item shows.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    /// Just the mic icon.
    case icon
    /// The icon and each mic's battery percentage.
    case battery
    /// The icon and one small battery bar per mic, stacked.
    case bars

    var id: String { rawValue }
    static let storageKey = "menuBarStyle"

    var title: String {
        switch self {
        case .icon: return "Icon"
        case .battery: return "Battery"
        case .bars: return "Bars"
        }
    }
}

/// The menu bar item, driven by the receiver's state.
struct MenuBarLabel: View {
    let store: ReceiverStore
    let style: MenuBarStyle

    var body: some View {
        MenuBarIcon(style: style, symbol: symbol, batteries: store.status?.connectedTransmitters.map(\.battery) ?? [])
            .accessibilityLabel(accessibilityText)
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
        let on = store.status?.connectedTransmitters ?? []
        guard !on.isEmpty else { return "LarkBar" }
        return "LarkBar, " + on.map { "\($0.name) battery \($0.battery) percent" }.joined(separator: ", ")
    }
}

/// The icon itself, also used for the previews in the menu bar style chooser.
///
/// A menu bar label only displays one image and one text, so the bars style draws the mic and the
/// bars together into a single image.
struct MenuBarIcon: View {
    let style: MenuBarStyle
    let symbol: String
    /// Battery percentage of each mic that's on.
    let batteries: [Int]

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch style {
        case .bars where !batteries.isEmpty:
            Image(nsImage: MenuBarBarsImage.make(symbol: symbol, batteries: batteries, dark: colorScheme == .dark))
        case .battery where !batteries.isEmpty:
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(batteries.map { "\($0)%" }.joined(separator: " "))
                    .monospacedDigit()
            }
        default:
            Image(systemName: symbol)
        }
    }
}

/// Draws the mic symbol with one battery bar per mic beside it.
enum MenuBarBarsImage {
    static func make(symbol: String, batteries: [Int], dark: Bool) -> NSImage {
        let height: CGFloat = 18
        let glyphSize = NSSize(width: 16, height: height)
        let barWidth: CGFloat = 22
        let barHeight: CGFloat = batteries.count > 2 ? 2.5 : 4
        let gap: CGFloat = batteries.count > 2 ? 1.5 : 2.5
        let foreground = dark ? NSColor.white : NSColor.black.withAlphaComponent(0.85)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)

        let size = NSSize(width: glyphSize.width + 3 + barWidth, height: height)
        let image = NSImage(size: size, flipped: false) { _ in
            if let glyph {
                let rect = NSRect(x: (glyphSize.width - glyph.size.width) / 2, y: (height - glyph.size.height) / 2,
                                  width: glyph.size.width, height: glyph.size.height)
                glyph.draw(in: rect)
                foreground.set()
                rect.fill(using: .sourceAtop)
            }
            let stack = CGFloat(batteries.count) * barHeight + CGFloat(batteries.count - 1) * gap
            var y = (height + stack) / 2 - barHeight
            for battery in batteries {
                let x = glyphSize.width + 3
                let radius = barHeight / 2
                foreground.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: barWidth, height: barHeight),
                             xRadius: radius, yRadius: radius).fill()
                color(for: battery).setFill()
                let filled = max(barHeight, barWidth * CGFloat(min(battery, 100)) / 100)
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: filled, height: barHeight),
                             xRadius: radius, yRadius: radius).fill()
                y -= barHeight + gap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func color(for battery: Int) -> NSColor {
        if battery <= 20 { return .systemRed }
        if battery <= 40 { return .systemYellow }
        return .systemGreen
    }
}
