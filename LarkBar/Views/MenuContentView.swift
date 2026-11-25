import SwiftUI

/// The window that drops down from the menu bar icon.
struct MenuContentView: View {
    let store: ReceiverStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch store.state {
                case .noDevice:
                    NoDeviceView()
                case let .unsupported(device):
                    UnsupportedDeviceView(device: device)
                case let .connecting(device):
                    DeviceHeader(device: device, firmware: nil)
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                case let .failed(device, message):
                    DeviceHeader(device: device, firmware: store.firmwareVersion)
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Text("Try unplugging the receiver and plugging it back in.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case let .connected(device, status):
                    DeviceHeader(device: device, firmware: store.firmwareVersion)
                    ReceiverControls(store: store, model: device.model ?? .larkA1, status: status)
                }
            }
            .padding(14)

            Divider()
            FooterMenu(micsOn: store.status?.connectedTransmitters ?? [])
                .padding(5)
        }
        .frame(width: 340)
        .onAppear { store.isMenuOpen = true }
        .onDisappear { store.isMenuOpen = false }
    }
}

// MARK: Header

private struct DeviceHeader: View {
    let device: HollylandDevice
    let firmware: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if device.model?.isVerified == false {
                Text("Experimental")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                    .help("LarkBar hasn't been tested with this receiver yet. Please report what works.")
            }
        }
        .padding(.bottom, 4)
    }

    private var subtitle: String {
        var parts = ["USB receiver"]
        if let firmware { parts.append("Firmware \(firmware)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: Empty states

private struct NoDeviceView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Lark receiver connected")
                .font(.headline)
            Text("Plug a Hollyland \(LarkModel.all.map(\.name).formatted(.list(type: .or))) USB receiver into this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct UnsupportedDeviceView: View {
    let device: HollylandDevice
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(device.productName)
                .font(.headline)
            Text("This Hollyland device (\(device.usbID)) isn't supported yet. If it's a Lark receiver, request support and include its device info.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? "Copied" : "Copy Device Info") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(deviceInfo, forType: .string)
                    copied = true
                }
                Link("Request Support", destination: AppLinks.newIssue)
            }
            .controlSize(.small)
        }
    }

    private var deviceInfo: String {
        """
        Product: \(device.productName)
        USB ID: \(device.usbID)
        LarkBar: \(AppLinks.version)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }
}
