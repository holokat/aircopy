import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator

    private let rowWidth: CGFloat = 248

    var body: some View {
        Button {
            coordinator.showMainWindow()
        } label: {
            menuRowLabel("Open AirCopy", systemImage: "macwindow")
        }

        Divider()

        Toggle(isOn: $coordinator.syncEnabled) {
            menuRowLabel(coordinator.syncEnabled ? "Clipboard Sync On" : "Clipboard Sync Off", systemImage: "bolt.horizontal.circle")
        }

        Button {
            coordinator.clearClipboard()
        } label: {
            menuRowLabel("Clear Current Clipboard", systemImage: "trash")
        }

        Button {
            coordinator.clearHistory()
        } label: {
            menuRowLabel("Clear Clip History", systemImage: "xmark.bin")
        }

        Divider()

        statusMenuRow("This Mac: \(coordinator.localDeviceName)", symbol: "desktopcomputer")
        statusMenuRow("Nearby Macs: \(coordinator.discoveredPeerCount)", symbol: "dot.radiowaves.left.and.right")
        statusMenuRow("Connected Peers: \(coordinator.connectedPeerCount)", symbol: "link")

        Divider()

        if coordinator.clipboardHistory.isEmpty {
            statusMenuRow("No recent clips yet", symbol: "square.stack.3d.up.slash")
        } else {
            ForEach(coordinator.clipboardHistory) { item in
                Button {
                    coordinator.restoreHistoryItem(item)
                } label: {
                    clipMenuRow(item)
                }
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func statusMenuRow(_ text: String, symbol: String) -> some View {
        Button {
            coordinator.showMainWindow()
        } label: {
            Label {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: rowWidth - 28, alignment: .leading)
            } icon: {
                Image(systemName: symbol)
                    .frame(width: 16)
            }
            .frame(width: rowWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func clipLeadingView(_ item: ClipboardHistoryItem) -> some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: item.symbolName)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func clipMenuRow(_ item: ClipboardHistoryItem) -> some View {
        HStack(spacing: 10) {
            clipLeadingView(item)

            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: rowWidth - 44, alignment: .leading)

            Spacer(minLength: 0)
        }
        .frame(width: rowWidth, alignment: .leading)
    }

    private func menuRowLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .frame(width: rowWidth, alignment: .leading)
    }
}
