import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var historyFilter: HistoryFilter = .all

    private var pendingPeers: [PeerDeviceState] {
        coordinator.peerDevices.filter { $0.trustState == .pending }
    }

    private var trustedPeers: [PeerDeviceState] {
        coordinator.peerDevices.filter { $0.trustState == .trusted }
    }

    private var alwaysSyncBinding: Binding<Bool> {
        Binding(
            get: { coordinator.syncEnabled && coordinator.temporarySyncUntil == nil },
            set: { newValue in
                if newValue {
                    coordinator.syncEnabled = true
                    coordinator.cancelTemporarySync()
                } else {
                    coordinator.syncEnabled = false
                }
            }
        )
    }

    var body: some View {
        ZStack {
            AirCopyTheme.background(for: colorScheme)
                .ignoresSafeArea()

            HStack(alignment: .top, spacing: 12) {
                deviceRail
                    .frame(width: 308)

                historyPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
        }
        .sheet(isPresented: $coordinator.settingsPresented) {
            AirCopySettingsView()
                .environmentObject(coordinator)
                .preferredColorScheme(coordinator.effectiveColorScheme)
        }
    }

    private var deviceRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sidebarHeader

                if !pendingPeers.isEmpty {
                    deviceSection(
                        title: "Pending Approval",
                        subtitle: "Approve nearby Macs before they can sync."
                    ) {
                        ForEach(pendingPeers) { peer in
                            MainPeerCard(peer: peer)
                                .environmentObject(coordinator)
                        }
                    }
                }

                deviceSection(
                    title: "Your Macs",
                    subtitle: "Connected and trusted devices for direct sending."
                ) {
                    if trustedPeers.isEmpty {
                        emptyPanelCopy(
                            "No trusted Macs yet",
                            detail: "Open AirCopy on your other Macs, then approve them here."
                        )
                    } else {
                        ForEach(trustedPeers) { peer in
                            MainPeerCard(peer: peer)
                                .environmentObject(coordinator)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("AirCopy")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(coordinator.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .lineLimit(2)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sync to All")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(coordinator.syncModeSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            coordinator.syncEnabled
                                ? AirCopyTheme.syncTint(for: colorScheme)
                                : AirCopyTheme.secondaryText(for: colorScheme)
                        )
                }

                Spacer()

                Toggle("Sync to All", isOn: alwaysSyncBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(AirCopyTheme.syncTint(for: colorScheme))
            }

            HStack(spacing: 8) {
                miniStat(title: "Trusted", value: "\(trustedPeers.count)")
                miniStat(title: "History", value: "\(coordinator.clipboardHistory.count)")
            }

            Button {
                coordinator.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
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
                    .frame(width: 240)
            }

            HStack(alignment: .center, spacing: 10) {
                Picker("History Filter", selection: $historyFilter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                Spacer(minLength: 8)

                Button(action: coordinator.clearNonRetainedHistory) {
                    Text("Clear History")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            coordinator.hasClearableHistory
                                ? AirCopyTheme.secondaryText(for: colorScheme)
                                : AirCopyTheme.secondaryText(for: colorScheme).opacity(0.6)
                        )
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(
                            AirCopyTheme.insetFill(for: colorScheme).opacity(coordinator.hasClearableHistory ? 1 : 0.75),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    AirCopyTheme.divider(for: colorScheme).opacity(colorScheme == .light ? 0.85 : 0.55),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!coordinator.hasClearableHistory)
            }

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

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func deviceSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 16)
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
}

private struct MainPeerCard: View {
    let peer: PeerDeviceState

    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: peer.deviceSymbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(peer.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                        Spacer(minLength: 8)

                        if showsManageButton {
                            settingsIconButton
                        }
                    }

                    statusBlock
                }
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
                case .blocked:
                    EmptyView()
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
            return AirCopyTheme.accent(for: colorScheme)
        case .pending:
            return AirCopyTheme.warning(for: colorScheme)
        case .blocked:
            return AirCopyTheme.error(for: colorScheme)
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(peer.statusSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))

                if peer.trustState == .trusted, peer.isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.success(for: colorScheme))
                }
            }

            if let lastReceiptText = peer.lastReceiptText, !lastReceiptText.isEmpty {
                Text(lastReceiptText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }
        }
    }

    private var showsManageButton: Bool {
        switch peer.trustState {
        case .trusted, .blocked:
            return true
        case .pending:
            return false
        }
    }

    private var settingsIconButton: some View {
        Button(action: coordinator.showSettings) {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(colorScheme == .light ? 0.82 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open device settings")
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

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sync
    case privacy
    case devices
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .sync:
            return "Sync"
        case .privacy:
            return "Privacy"
        case .devices:
            return "Devices"
        case .advanced:
            return "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            return "gearshape"
        case .sync:
            return "arrow.triangle.2.circlepath"
        case .privacy:
            return "lock.shield"
        case .devices:
            return "desktopcomputer"
        case .advanced:
            return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Basic app preferences and appearance."
        case .sync:
            return "How AirCopy behaves while syncing."
        case .privacy:
            return "What AirCopy should never send."
        case .devices:
            return "Trust and review nearby Macs."
        case .advanced:
            return "Rare and destructive actions."
        }
    }
}

private struct AirCopySettingsView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 190)
                .padding(16)
                .background(AirCopyTheme.panelFill(for: colorScheme))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedSection.title)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                            Text(selectedSection.subtitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        }

                        Spacer()

                        Button("Done") {
                            dismiss()
                        }
                    }

                    settingsDetail
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AirCopyTheme.background(for: colorScheme))
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SettingsSection.allCases) { section in
                let isSelected = selectedSection == section

                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.symbolName)
                            .foregroundStyle(
                                isSelected
                                    ? Color.white
                                    : AirCopyTheme.accent(for: colorScheme)
                            )
                            .frame(width: 16)
                        Text(section.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(
                                isSelected
                                    ? Color.white
                                    : AirCopyTheme.primaryText(for: colorScheme)
                            )
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        isSelected
                            ? AirCopyTheme.buttonTint(for: colorScheme)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch selectedSection {
        case .general:
            settingsGroup(title: "Appearance", subtitle: "Keep visual preferences out of the main workflow.") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Theme")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Picker("Theme", selection: $coordinator.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            settingsGroup(title: "Device", subtitle: "Read-only device context.") {
                settingsRow(title: "This Mac", value: coordinator.localDeviceName)
                settingsRow(title: "Frontmost App", value: coordinator.frontmostApplicationName)
                settingsRow(title: "Trusted Macs", value: "\(coordinator.peerDevices.filter { $0.trustState == .trusted }.count)")
            }

        case .sync:
            settingsGroup(title: "Sync Behavior", subtitle: "Primary sync decisions belong here, not in the main workspace.") {
                Toggle("Sync clipboard to all trusted Macs", isOn: $coordinator.syncEnabled)
                    .tint(AirCopyTheme.syncTint(for: colorScheme))
                Toggle("Sync images", isOn: $coordinator.imageSyncEnabled)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Temporary Sync")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    HStack(spacing: 8) {
                        settingsActionButton("Sync for 10 Minutes", systemImage: "timer") {
                            coordinator.startTemporarySync()
                        }

                        if coordinator.temporarySyncUntil != nil {
                            settingsActionButton("Cancel Temporary Sync", systemImage: "pause.circle") {
                                coordinator.cancelTemporarySync()
                            }
                        }
                    }

                    if let until = coordinator.temporarySyncUntil {
                        Text("Ends \(until.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    }
                }
            }

        case .privacy:
            settingsGroup(title: "Privacy Rules", subtitle: "Protect sensitive sources and exclude noisy apps.") {
                settingsRow(title: "Password managers", value: "Always blocked from sync")
                settingsRow(title: "Frontmost app", value: coordinator.frontmostApplicationName)

                settingsActionButton("Exclude Frontmost App", systemImage: "eye.slash") {
                    coordinator.addFrontmostApplicationToExclusions()
                }
            }

            settingsGroup(title: "Excluded Apps", subtitle: "AirCopy ignores clipboard changes from these apps.") {
                if coordinator.excludedApplications.isEmpty {
                    settingsEmptyState("No custom exclusions yet")
                } else {
                    ForEach(coordinator.excludedApplications) { exclusion in
                        HStack(spacing: 10) {
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
                        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }

        case .devices:
            settingsGroup(title: "Trust Rules", subtitle: "Keep approval and device management together.") {
                Toggle("Require approval for new Macs", isOn: $coordinator.requireDeviceApproval)
            }

            settingsGroup(title: "Known Macs", subtitle: "Approve, block, and review nearby devices.") {
                if coordinator.peerDevices.isEmpty {
                    settingsEmptyState("No Macs discovered yet")
                } else {
                    ForEach(coordinator.peerDevices) { peer in
                        SettingsPeerRow(peer: peer)
                            .environmentObject(coordinator)
                    }
                }
            }

        case .advanced:
            settingsGroup(title: "Local Cleanup", subtitle: "These actions affect only this Mac.") {
                HStack(spacing: 8) {
                    settingsActionButton("Clear This Mac Clipboard", systemImage: "trash") {
                        coordinator.clearClipboard()
                    }

                    settingsActionButton("Clear Local History", systemImage: "xmark.bin") {
                        coordinator.clearHistory()
                    }
                }
            }
        }
    }

    private func settingsGroup<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .airCopyPanel(cornerRadius: 18)
    }

    private func settingsRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .lineLimit(1)
        }
    }

    private func settingsActionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingsEmptyState(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsPeerRow: View {
    let peer: PeerDeviceState

    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: peer.deviceSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                HStack(spacing: 4) {
                    Text(peer.statusSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))

                    if peer.trustState == .trusted, peer.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AirCopyTheme.success(for: colorScheme))
                    }
                }
            }

            Spacer()

            if peer.trustState == .trusted, peer.isConnected {
                rowActionButton("Send Current") {
                    coordinator.sendCurrentClipboard(to: peer.id)
                }
            }

            switch peer.trustState {
            case .pending:
                rowActionButton("Trust") {
                    coordinator.trustPeer(peer.id)
                }
                rowActionButton("Block") {
                    coordinator.blockPeer(peer.id)
                }
            case .trusted:
                rowActionButton("Block") {
                    coordinator.blockPeer(peer.id)
                }
            case .blocked:
                rowActionButton("Trust") {
                    coordinator.trustPeer(peer.id)
                }
            }
        }
        .padding(10)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var iconColor: Color {
        switch peer.trustState {
        case .trusted:
            return AirCopyTheme.accent(for: colorScheme)
        case .pending:
            return AirCopyTheme.warning(for: colorScheme)
        case .blocked:
            return AirCopyTheme.error(for: colorScheme)
        }
    }

    private func rowActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(colorScheme == .light ? 0.9 : 0.08), in: Capsule())
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
