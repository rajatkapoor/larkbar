import ServiceManagement
import SwiftUI

enum AppLinks {
    static let repository = URL(string: "https://github.com/rajatkapoor/larkbar")!
    static let newIssue = URL(string: "https://github.com/rajatkapoor/larkbar/issues/new")!

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// Menu-style rows at the bottom of the window: app preferences, links and Quit.
struct FooterMenu: View {
    @AppStorage("showBatteryInMenuBar") private var showBatteryInMenuBar = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuToggleRow(title: "Show Battery in Menu Bar", isOn: $showBatteryInMenuBar)
            MenuToggleRow(title: "Open at Login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
            }
            Divider().padding(.vertical, 4)
            MenuButtonRow(title: "LarkBar on GitHub", trailing: AppLinks.version) {
                NSWorkspace.shared.open(AppLinks.repository)
            }
            MenuButtonRow(title: "Quit LarkBar", trailing: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct MenuToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        MenuButtonRow(title: title, trailing: nil, leadingCheck: isOn) { isOn.toggle() }
    }
}

/// A row that looks and highlights like a native menu item.
private struct MenuButtonRow: View {
    let title: String
    let trailing: String?
    var leadingCheck: Bool? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(leadingCheck ? 1 : 0)
                        .frame(width: 12)
                }
                Text(title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .foregroundStyle(isHovered ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
