import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator

    private let rowWidth: CGFloat = 268

    var body: some View {
        Button {
            coordinator.showMainWindow()
        } label: {
            menuRowLabel("Open AirCopy", systemImage: "macwindow")
        }

        Button {
            coordinator.showSettings()
        } label: {
            menuRowLabel("Open Settings", systemImage: "gearshape")
        }

        Divider()

        Toggle(isOn: $coordinator.syncEnabled) {
            menuRowLabel(coordinator.syncEnabled ? "Sync to All On" : "Sync to All Off", systemImage: "bolt.horizontal.circle")
        }

        Toggle(isOn: $coordinator.imageSyncEnabled) {
            menuRowLabel(coordinator.imageSyncEnabled ? "Image Sync On" : "Image Sync Paused", systemImage: "photo")
        }

        Button {
            coordinator.startTemporarySync()
        } label: {
            menuRowLabel("Sync for 10 Minutes", systemImage: "timer")
        }

        Divider()

        if let latest = coordinator.latestClipboardItem {
            Button {
                coordinator.restoreHistoryItem(latest)
            } label: {
                menuRowLabel("Copy Latest Again", systemImage: "doc.on.doc")
            }

            if latest.kind == .image {
                Button {
                    coordinator.openImage(for: latest)
                } label: {
                    menuRowLabel("Open Latest Image", systemImage: "photo.on.rectangle")
                }
            }

            Menu("Send Latest To") {
                if coordinator.trustedConnectedPeers.isEmpty {
                    Text("No trusted connected Macs")
                } else {
                    ForEach(coordinator.trustedConnectedPeers) { peer in
                        Button(peer.displayName) {
                            coordinator.sendCurrentClipboard(to: peer.id)
                        }
                    }
                }
            }

            Button(latest.isPinned ? "Unpin Latest Item" : "Pin Latest Item") {
                coordinator.togglePin(for: latest)
            }

            Button(latest.isFavorite ? "Unfavorite Latest Item" : "Favorite Latest Item") {
                coordinator.toggleFavorite(for: latest)
            }
        } else {
            statusMenuRow("No latest item yet", symbol: "square.stack.3d.up.slash")
        }

        Divider()

        statusMenuRow("This Mac: \(coordinator.localDeviceName)", symbol: "desktopcomputer")
        statusMenuRow("Trusted peers: \(coordinator.connectedPeerCount)", symbol: "checkmark.shield")
        statusMenuRow("Sync: \(coordinator.syncModeSummary)", symbol: "clock.arrow.circlepath")

        if let firstPending = coordinator.peerDevices.first(where: { $0.trustState == .pending }) {
            Button("Trust \(firstPending.displayName)") {
                coordinator.trustPeer(firstPending.id)
            }
        }

        Divider()

        Menu("Recent Clips") {
            if coordinator.clipboardHistory.isEmpty {
                Text("No recent clips yet")
            } else {
                ForEach(coordinator.clipboardHistory.prefix(8)) { item in
                    Button(item.title) {
                        coordinator.restoreHistoryItem(item)
                    }
                }
            }
        }

        Divider()

        Button {
            coordinator.clearClipboard()
        } label: {
            menuRowLabel("Clear Only This Device", systemImage: "trash")
        }

        Button {
            coordinator.clearHistory()
        } label: {
            menuRowLabel("Clear Local History", systemImage: "xmark.bin")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func statusMenuRow(_ text: String, symbol: String) -> some View {
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
