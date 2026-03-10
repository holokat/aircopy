import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AirCopyTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header

                HStack(alignment: .top, spacing: 12) {
                    connectionPanel
                        .frame(width: 260)

                    recentClipsPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let icon = coordinator.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: coordinator.menuBarSymbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("AirCopy")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .lineLimit(1)

                Text(coordinator.statusText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Sync")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(1)

                Toggle("", isOn: $coordinator.syncEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(AirCopyTheme.buttonTint(for: colorScheme))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AirCopyTheme.insetFill(for: colorScheme), in: Capsule())

            HStack(spacing: 6) {
                ForEach(AppearancePreference.allCases) { preference in
                    Button {
                        coordinator.appearancePreference = preference
                    } label: {
                        Image(systemName: appearanceSymbol(for: preference))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                coordinator.appearancePreference == preference
                                    ? Color.white
                                    : AirCopyTheme.primaryText(for: colorScheme)
                            )
                            .frame(width: 16, height: 16)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .background(
                                coordinator.appearancePreference == preference
                                    ? AirCopyTheme.buttonTint(for: colorScheme)
                                    : AirCopyTheme.insetFill(for: colorScheme),
                                in: Capsule()
                            )
                    }
                    .help(preference.title)
                    .accessibilityLabel(preference.title)
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(AirCopyTheme.insetFill(for: colorScheme).opacity(0.9), in: Capsule())

            headerActionButton(
                title: "Clear Clipboard",
                systemImage: "trash"
            ) {
                coordinator.clearClipboard()
            }

            headerActionButton(
                title: "Clear History",
                systemImage: "xmark.bin"
            ) {
                coordinator.clearHistory()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .airCopyPanel(cornerRadius: 16)
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connection")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .lineLimit(1)

            compactInfoRow(symbol: "desktopcomputer", title: "This Mac", value: coordinator.localDeviceName)
            compactInfoRow(symbol: "dot.radiowaves.left.and.right", title: "Nearby", value: "\(coordinator.discoveredPeerCount)")
            compactInfoRow(symbol: "link", title: "Peers", value: "\(coordinator.connectedPeerCount)")
            compactInfoRow(symbol: "square.stack.3d.up.fill", title: "Saved", value: "\(coordinator.clipboardHistory.count)")

            if !coordinator.connectedPeerLabels.isEmpty {
                Divider()
                    .overlay(AirCopyTheme.divider(for: colorScheme))

                Text("Connected Macs")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .lineLimit(1)

                ForEach(coordinator.connectedPeerLabels, id: \.self) { label in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.success(for: colorScheme))
                        Text(label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private var recentClipsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Clips")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .lineLimit(1)

                Spacer()

                Text("Select any item to restore it to the clipboard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if coordinator.clipboardHistory.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No recent clips yet")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                        .lineLimit(1)
                    Text("Copy text or an image and it will appear here.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(coordinator.clipboardHistory) { item in
                        Button {
                            coordinator.restoreHistoryItem(item)
                        } label: {
                            CompactClipRow(
                                item: item,
                                isCopied: coordinator.recentlyCopiedHistoryItemID == item.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private func compactInfoRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                .frame(width: 16)

            Text("\(title): \(value)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }

    private func headerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(AirCopyTheme.buttonTint(for: colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func appearanceSymbol(for preference: AppearancePreference) -> String {
        switch preference {
        case .automatic:
            return "clock"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

}

private struct CompactClipRow: View {
    let item: ClipboardHistoryItem
    let isCopied: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            leadingView

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Text(item.kind == .text ? "Text" : "Image")
                    Text("•")
                    Text(item.source)
                    Text("•")
                    Text(item.detailText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
            }

            Spacer()

            Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCopied ? AirCopyTheme.success(for: colorScheme) : AirCopyTheme.accent(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var leadingView: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                .frame(width: 56, height: 56)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}
