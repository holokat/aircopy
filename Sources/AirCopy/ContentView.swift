import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var historyFilter: HistoryFilter = .all

    var body: some View {
        ZStack {
            AirCopyTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                header

                HStack(alignment: .top, spacing: 12) {
                    sidebar
                        .frame(width: 320)

                    historyPanel
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(14)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
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
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AirCopy")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(coordinator.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .lineLimit(1)
                }
            }

            Spacer()

            statusPill("Sync", value: coordinator.syncModeSummary, emphasized: coordinator.syncEnabled)
            statusPill("Peers", value: "\(coordinator.connectedPeerCount) trusted", emphasized: coordinator.connectedPeerCount > 0)
            statusPill("Images", value: coordinator.imageSyncEnabled ? "On" : "Paused", emphasized: coordinator.imageSyncEnabled)

            Toggle("Sync", isOn: $coordinator.syncEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(AirCopyTheme.buttonTint(for: colorScheme))

            Toggle("Images", isOn: $coordinator.imageSyncEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(AirCopyTheme.highlight(for: colorScheme))
                .help("Pause or resume image sync.")

            secondaryHeaderButton(title: "10m", systemImage: "timer") {
                coordinator.startTemporarySync()
            }
            .help("Enable sync for 10 minutes.")

            if coordinator.temporarySyncUntil != nil {
                secondaryHeaderButton(title: "Cancel", systemImage: "pause.circle") {
                    coordinator.cancelTemporarySync()
                }
                .help("Cancel temporary sync.")
            }

            appearanceSwitcher

            headerActionButton(title: "Clear This Mac", systemImage: "trash") {
                coordinator.clearClipboard()
            }

            headerActionButton(title: "Clear History", systemImage: "xmark.bin") {
                coordinator.clearHistory()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .airCopyPanel(cornerRadius: 16)
    }

    private var appearanceSwitcher: some View {
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
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: Capsule())
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                syncPanel
                devicesPanel
                privacyPanel
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var syncPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "Sync Controls", subtitle: "Temporary sync, image pause, and local state.")

            infoRow(symbol: "desktopcomputer", title: "This Mac", value: coordinator.localDeviceName)
            infoRow(symbol: "lock.shield", title: "Transport", value: "Encrypted")
            infoRow(symbol: "clock.arrow.circlepath", title: "Mode", value: coordinator.syncModeSummary)
            infoRow(symbol: "square.stack.3d.up.fill", title: "History", value: "\(coordinator.clipboardHistory.count) items")

            HStack(spacing: 8) {
                quickPanelButton("Sync 10m", systemImage: "timer") {
                    coordinator.startTemporarySync()
                }

                quickPanelButton(coordinator.imageSyncEnabled ? "Pause Images" : "Resume Images", systemImage: "photo") {
                    coordinator.imageSyncEnabled.toggle()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "Trusted Macs", subtitle: "Approve devices, send directly, and check delivery state.")

            if coordinator.peerDevices.isEmpty {
                emptyPanelCopy("No nearby Macs yet", detail: "Keep AirCopy open on your other Macs and approve them here.")
            } else {
                ForEach(coordinator.peerDevices) { peer in
                    PeerDeviceCard(peer: peer)
                        .environmentObject(coordinator)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader(title: "Privacy", subtitle: "Protected apps and clipboard exclusions.")

            infoRow(symbol: "shield.lefthalf.filled", title: "Password managers", value: "Never synced")
            infoRow(symbol: "app.badge", title: "Frontmost app", value: coordinator.frontmostApplicationName)
            infoRow(symbol: "nosign", title: "Custom exclusions", value: "\(coordinator.customExclusionCount)")

            quickPanelButton("Exclude Frontmost App", systemImage: "eye.slash") {
                coordinator.addFrontmostApplicationToExclusions()
            }

            if coordinator.excludedApplications.isEmpty {
                emptyPanelCopy("No custom app exclusions", detail: "Add the frontmost app whenever you want AirCopy to ignore its clipboard.")
            } else {
                VStack(spacing: 8) {
                    ForEach(coordinator.excludedApplications) { exclusion in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exclusion.appName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                                Text(exclusion.bundleID)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                            }

                            Spacer()

                            Button("Remove") {
                                coordinator.removeExcludedApplication(exclusion)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.warning(for: colorScheme))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            AirCopyTheme.insetFill(for: colorScheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("History")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text("Search, filter, pin, favorite, resend, and open items.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }

                Spacer()

                TextField("Search history", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            Picker("History Filter", selection: $historyFilter) {
                ForEach(HistoryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            let items = coordinator.filteredHistory(searchText: searchText, filter: historyFilter)

            if items.isEmpty {
                Spacer(minLength: 0)
                emptyPanelCopy("No clips match this view", detail: "Try a different search or filter, or copy a new item.")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            HistoryItemCard(item: item)
                                .environmentObject(coordinator)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
    }

    private func panelHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
            Text(subtitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
        }
    }

    private func statusPill(_ title: String, value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(emphasized ? AirCopyTheme.primaryText(for: colorScheme) : AirCopyTheme.secondaryText(for: colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: Capsule())
    }

    private func infoRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                .frame(width: 16)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
        }
    }

    private func emptyPanelCopy(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func quickPanelButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
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

    private func secondaryHeaderButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: Capsule())
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

private struct PeerDeviceCard: View {
    let peer: PeerDeviceState

    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: peer.isConnected ? "checkmark.shield.fill" : "desktopcomputer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peer.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(peer.statusSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }

                Spacer()

                if let lastReceiptState = peer.lastReceiptState {
                    Label(lastReceiptState.title, systemImage: lastReceiptState.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
            }

            if let lastReceiptText = peer.lastReceiptText {
                Text(lastReceiptText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                switch peer.trustState {
                case .pending:
                    actionButton("Trust", systemImage: "checkmark.shield") {
                        coordinator.trustPeer(peer.id)
                    }
                    actionButton("Block", systemImage: "hand.raised") {
                        coordinator.blockPeer(peer.id)
                    }
                case .trusted:
                    if peer.isConnected {
                        actionButton("Send Current", systemImage: "paperplane") {
                            coordinator.sendCurrentClipboard(to: peer.id)
                        }
                    }
                    actionButton("Block", systemImage: "hand.raised") {
                        coordinator.blockPeer(peer.id)
                    }
                case .blocked:
                    actionButton("Trust", systemImage: "checkmark.shield") {
                        coordinator.trustPeer(peer.id)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconColor: Color {
        switch peer.trustState {
        case .trusted:
            return peer.isConnected ? AirCopyTheme.success(for: colorScheme) : AirCopyTheme.accent(for: colorScheme)
        case .pending:
            return AirCopyTheme.warning(for: colorScheme)
        case .blocked:
            return AirCopyTheme.error(for: colorScheme)
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(colorScheme == .light ? 0.9 : 0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct HistoryItemCard: View {
    let item: ClipboardHistoryItem

    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                previewBlock

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                            .lineLimit(1)

                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AirCopyTheme.warning(for: colorScheme))
                        }

                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(AirCopyTheme.highlight(for: colorScheme))
                        }
                    }

                    Text(item.previewText)
                        .font(item.kind == .code ? .system(size: 11, weight: .medium, design: .monospaced) : .system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .lineLimit(item.kind == .code ? 3 : 2)

                    HStack(spacing: 4) {
                        Text(item.kind.title)
                        Text("•")
                        Text(item.detailText)
                        Text("•")
                        Text(item.source)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        coordinator.restoreHistoryItem(item)
                    } label: {
                        Label("Copy Again", systemImage: coordinator.recentlyCopiedHistoryItemID == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)

                    HStack(spacing: 6) {
                        Button {
                            coordinator.togglePin(for: item)
                        } label: {
                            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        }
                        .buttonStyle(.plain)

                        Button {
                            coordinator.toggleFavorite(for: item)
                        } label: {
                            Image(systemName: item.isFavorite ? "star.fill" : "star")
                        }
                        .buttonStyle(.plain)

                        Menu {
                            if coordinator.trustedConnectedPeers.isEmpty {
                                Text("No trusted connected Macs")
                            } else {
                                ForEach(coordinator.trustedConnectedPeers) { peer in
                                    Button(peer.displayName) {
                                        coordinator.sendHistoryItem(item, to: peer.id)
                                    }
                                }
                            }

                            if item.kind == .image {
                                Button("Open Image") {
                                    coordinator.openImage(for: item)
                                }
                            }
                        } label: {
                            Image(systemName: "paperplane")
                        }
                        .menuStyle(.borderlessButton)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                }
            }

            if !item.deviceReceipts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(item.deviceReceipts.prefix(3)) { receipt in
                        Label(receipt.deviceName, systemImage: receipt.state.symbolName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(receiptColor(for: receipt.state))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                AirCopyTheme.insetFill(for: colorScheme),
                                in: Capsule()
                            )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var previewBlock: some View {
        switch item.kind {
        case .image:
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .code:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: item.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.payload.languageHint?.uppercased() ?? "CODE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(AirCopyTheme.highlight(for: colorScheme))
            .frame(width: 64, height: 64)
            .background(AirCopyTheme.codeBlockFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .link, .browserTab:
            previewIcon(symbol: item.symbolName, color: AirCopyTheme.highlight(for: colorScheme))
        case .file, .folder:
            previewIcon(symbol: item.symbolName, color: AirCopyTheme.warning(for: colorScheme))
        case .text:
            previewIcon(symbol: item.symbolName, color: AirCopyTheme.accent(for: colorScheme))
        }
    }

    private func previewIcon(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 64, height: 64)
            .background(AirCopyTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func receiptColor(for state: DeliveryState) -> Color {
        switch state {
        case .pending:
            return AirCopyTheme.warning(for: colorScheme)
        case .delivered:
            return AirCopyTheme.accent(for: colorScheme)
        case .clipboardUpdated:
            return AirCopyTheme.success(for: colorScheme)
        case .failed:
            return AirCopyTheme.error(for: colorScheme)
        case .skipped:
            return AirCopyTheme.secondaryText(for: colorScheme)
        }
    }
}
