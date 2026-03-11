import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchText = ""
    @State private var historyFilter: HistoryFilter = .all
    @State private var previewedHistoryItem: ClipboardHistoryItem?

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
                    coordinator.setSyncToAllEnabled(true)
                } else {
                    coordinator.setSyncToAllEnabled(false)
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
        .sheet(item: $previewedHistoryItem) { item in
            HistoryPreviewSheet(item: item)
                .preferredColorScheme(coordinator.effectiveColorScheme)
        }
    }

    private var deviceRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                sidebarHeader
                syncControlPanel

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

    private var syncControlPanel: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sync to All")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                Text(coordinator.syncModeSummary)
                    .font(.system(size: 11, weight: .medium))
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
        .padding(14)
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
                            HistoryItemCard(item: item) {
                                previewedHistoryItem = item
                            }
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
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if peer.trustState == .trusted {
                            autoSyncToggle
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

            if let statusDetail {
                Text(statusDetail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    .lineLimit(2)
            }
        }
    }

    private var statusDetail: String? {
        if peer.trustState == .trusted, !peer.isAutoSyncEnabled {
            return "Manual only"
        }

        return peer.lastReceiptText
    }

    private var autoSyncToggle: some View {
        Toggle("Include \(peer.displayName) in auto-sync", isOn: autoSyncBinding)
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(AirCopyTheme.syncTint(for: colorScheme))
            .accessibilityLabel("Include \(peer.displayName) in auto-sync")
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { peer.isAutoSyncEnabled },
            set: { coordinator.setAutoSyncEnabled($0, for: peer.id) }
        )
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
    case screenshots
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
        case .screenshots:
            return "Screenshots"
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
        case .screenshots:
            return "camera.viewfinder"
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
        case .screenshots:
            return "Capture and style screenshots before they sync."
        case .privacy:
            return "What AirCopy should never send."
        case .devices:
            return "Trust and review nearby Macs."
        case .advanced:
            return "Rare and destructive actions."
        }
    }
}

private enum ScreenshotControlsSection: String, CaseIterable, Identifiable {
    case look
    case frame
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .look:
            return "Look"
        case .frame:
            return "Frame"
        case .privacy:
            return "Privacy"
        }
    }
}

private struct AirCopySettingsView: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSection: SettingsSection = .general
    @State private var selectedScreenshotControls: ScreenshotControlsSection = .look

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

            settingsGroup(title: "Saved Copies", subtitle: "Optionally keep received items as files on this Mac.") {
                Toggle("Save received items to disk", isOn: $coordinator.saveReceivedItemsToDiskEnabled)

                if coordinator.saveReceivedItemsToDiskEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Images", isOn: $coordinator.saveReceivedImagesToDisk)
                        Toggle("Text", isOn: $coordinator.saveReceivedTextToDisk)
                        Toggle("Files", isOn: $coordinator.saveReceivedFilesToDisk)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Base Folder")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                            Text(coordinator.savedItemsDirectoryDisplayPath)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                                .textSelection(.enabled)

                            HStack(spacing: 8) {
                                settingsActionButton("Choose Folder", systemImage: "folder") {
                                    coordinator.chooseSavedItemsDirectory()
                                }

                                settingsActionButton("Open Folder", systemImage: "arrow.up.right.square") {
                                    coordinator.openSavedItemsDirectory()
                                }
                            }

                            Text("AirCopy creates Images, Text, and Files subfolders automatically.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        }
                    }
                }
            }

            settingsGroup(title: "Device", subtitle: "Read-only device context.") {
                settingsRow(title: "This Mac", value: coordinator.localDeviceName)
                settingsRow(title: "Frontmost App", value: coordinator.frontmostApplicationName)
                settingsRow(title: "Trusted Macs", value: "\(coordinator.peerDevices.filter { $0.trustState == .trusted }.count)")
            }

        case .sync:
            settingsGroup(title: "Sync Behavior", subtitle: "Primary sync decisions belong here, not in the main workspace.") {
                Toggle(
                    "Sync clipboard to all trusted Macs",
                    isOn: Binding(
                        get: { coordinator.syncEnabled },
                        set: { coordinator.setSyncToAllEnabled($0) }
                    )
                )
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

            settingsGroup(title: "Standard Screenshots", subtitle: "Make normal macOS screenshot shortcuts behave like live AirCopy items.") {
                Toggle("AirCopy handles Cmd-Shift-3 and Cmd-Shift-4", isOn: $coordinator.captureStandardScreenshotShortcutsEnabled)
                    .tint(AirCopyTheme.syncTint(for: colorScheme))

                settingsRow(title: "Shortcut Status", value: coordinator.screenshotShortcutCaptureStatusText)
                settingsRow(
                    title: "Screen Recording",
                    value: coordinator.screenshotScreenRecordingPermissionGranted ? "Allowed" : "Needed"
                )

                if coordinator.captureStandardScreenshotShortcutsEnabled && !coordinator.screenshotShortcutCapturePermissionGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AirCopy needs Accessibility permission to intercept the standard screenshot keys before macOS handles them.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        settingsActionButton("Open Accessibility Settings", systemImage: "hand.raised") {
                            coordinator.openAccessibilityPrivacySettings()
                        }
                    }
                }

                if !coordinator.screenshotScreenRecordingPermissionGranted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AirCopy also needs Screen Recording permission to capture pixels directly instead of waiting for the system screenshot file path.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        settingsActionButton("Open Screen Recording Settings", systemImage: "rectangle.inset.filled.and.person.filled") {
                            coordinator.openScreenRecordingPrivacySettings()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture Now")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    HStack(spacing: 8) {
                        settingsActionButton("Selection", systemImage: "crop") {
                            coordinator.captureSelectionScreenshot()
                        }

                        settingsActionButton("Full Screen", systemImage: "rectangle.expand.vertical") {
                            coordinator.captureFullScreenScreenshot()
                        }
                    }
                }

                Toggle("Import saved macOS screenshots as a fallback", isOn: $coordinator.importSystemScreenshotsEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Watched Folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(coordinator.screenshotImportFolderDisplayPath)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .textSelection(.enabled)

                    Text("AirCopy automatically watches your current macOS screenshot location and imports new screenshots into clipboard history and sync when the system saves a file instead of copying it.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .screenshots:
            settingsGroup(title: "Screenshot Styling", subtitle: "Frame AirCopy screenshots without a long settings page.") {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Style AirCopy screenshots", isOn: $coordinator.screenshotStyleSettings.isEnabled)

                    ScreenshotStylePreviewCard(
                        image: coordinator.screenshotStylePreviewImage,
                        isEnabled: coordinator.screenshotStyleSettings.isEnabled
                    )

                    Picker("Screenshot Controls", selection: $selectedScreenshotControls) {
                        ForEach(ScreenshotControlsSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)

                    screenshotControlsDetail
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

    @ViewBuilder
    private var screenshotControlsDetail: some View {
        switch selectedScreenshotControls {
        case .look:
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Background")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    ScreenshotBackgroundPresetStrip(
                        selection: $coordinator.screenshotStyleSettings.backgroundPreset
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if coordinator.screenshotStyleSettings.backgroundPreset == .desktop {
                        Text("Desktop uses this Mac’s current wallpaper.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    compactPickerCard(title: "Aspect Ratio") {
                        Picker("Aspect Ratio", selection: $coordinator.screenshotStyleSettings.aspectRatioPreset) {
                            ForEach(ScreenshotAspectRatioPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    compactPickerCard(title: "Output Size") {
                        Picker("Output Size", selection: $coordinator.screenshotStyleSettings.outputSizePreset) {
                            ForEach(ScreenshotOutputSizePreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }

        case .frame:
            VStack(alignment: .leading, spacing: 10) {
                ScreenshotStyleSliderRow(
                    title: "Inset",
                    value: $coordinator.screenshotStyleSettings.insetFraction,
                    range: 0.06...0.24,
                    valueLabel: "\(Int(coordinator.screenshotStyleSettings.insetFraction * 100))%"
                )

                ScreenshotStyleSliderRow(
                    title: "Radius",
                    value: $coordinator.screenshotStyleSettings.cornerRadius,
                    range: 8...44,
                    valueLabel: "\(Int(coordinator.screenshotStyleSettings.cornerRadius)) px"
                )

                ScreenshotStyleSliderRow(
                    title: "Shadow",
                    value: $coordinator.screenshotStyleSettings.shadowStrength,
                    range: 0...1,
                    valueLabel: "\(Int(coordinator.screenshotStyleSettings.shadowStrength * 100))%"
                )
            }

        case .privacy:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Redact email addresses", isOn: $coordinator.screenshotStyleSettings.redactEmailAddresses)
                Toggle("Show watermark", isOn: $coordinator.screenshotStyleSettings.showWatermark)

                if coordinator.screenshotStyleSettings.showWatermark {
                    TextField("Watermark text", text: $coordinator.screenshotStyleSettings.watermarkText)
                        .textFieldStyle(.roundedBorder)
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

    private func compactPickerCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private struct ScreenshotStylePreviewCard: View {
    let image: NSImage?
    let isEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 208)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AirCopyTheme.insetFill(for: colorScheme))
                        .frame(height: 188)
                        .overlay {
                            Text("Preview unavailable")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                        }
                }
            }
            .background(AirCopyTheme.insetFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(
                isEnabled
                    ? "New screenshots will use this look before they sync or save."
                    : "Preview is live while you tune it. Turn on styling above when you are ready to apply it."
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
        }
    }
}

private struct ScreenshotBackgroundPresetStrip: View {
    @Binding var selection: ScreenshotBackgroundPreset

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
            ForEach(ScreenshotBackgroundPreset.allCases) { preset in
                let isSelected = selection == preset

                Button {
                    selection = preset
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if let previewImage = ScreenshotStyleRenderer.backgroundPreviewImage(for: preset) {
                                Image(nsImage: previewImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AirCopyTheme.insetFill(for: colorScheme))
                            }
                        }
                        .frame(width: 92, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 6) {
                            Text(preset.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                            Spacer(minLength: 0)

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AirCopyTheme.highlight(for: colorScheme))
                            }
                        }
                    }
                    .padding(8)
                    .frame(width: 112, alignment: .leading)
                    .background(
                        isSelected
                            ? AirCopyTheme.panelFill(for: colorScheme)
                            : AirCopyTheme.insetFill(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected
                                    ? AirCopyTheme.highlight(for: colorScheme).opacity(0.42)
                                    : Color.clear,
                                lineWidth: 1.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            }
        }
    }
}

private struct ScreenshotStyleSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueLabel: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                Spacer()

                Text(valueLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AirCopyTheme.highlight(for: colorScheme))
            }

            Slider(value: $value, in: range)
                .tint(AirCopyTheme.highlight(for: colorScheme))
        }
    }
}

private struct HistoryItemCard: View {
    let item: ClipboardHistoryItem
    let onPreview: (() -> Void)?

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

                    previewTextView

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

                HStack(spacing: 6) {
                    actionIconButton(
                        systemImage: coordinator.recentlyCopiedHistoryItemID == item.id ? "checkmark" : "doc.on.doc",
                        accessibilityLabel: "Copy this history item again"
                    ) {
                        coordinator.restoreHistoryItem(id: item.id)
                    }

                    actionIconButton(
                        systemImage: item.isPinned ? "pin.fill" : "pin",
                        accessibilityLabel: item.isPinned ? "Unpin this item" : "Pin this item"
                    ) {
                        coordinator.togglePin(for: item)
                    }

                    actionIconButton(
                        systemImage: item.isFavorite ? "star.fill" : "star",
                        accessibilityLabel: item.isFavorite ? "Unfavorite this item" : "Favorite this item"
                    ) {
                        coordinator.toggleFavorite(for: item)
                    }

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
                    .accessibilityLabel("Send this history item")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
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
    private var previewTextView: some View {
        if historyLinkURL != nil {
            Button(action: openHistoryLink) {
                Text(item.previewText)
                    .font(.system(size: 11, weight: .medium))
                    .underline()
                    .foregroundStyle(AirCopyTheme.accent(for: colorScheme))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(item.title)")
        } else {
            Text(item.previewText)
                .font(item.kind == .code ? .system(size: 11, weight: .medium, design: .monospaced) : .system(size: 11, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .lineLimit(item.kind == .code ? 3 : 2)
        }
    }

    @ViewBuilder
    private var previewBlock: some View {
        if isPreviewable, let onPreview {
            Button(action: onPreview) {
                previewThumbnail
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(item.title)")
        } else {
            previewThumbnail
        }
    }

    @ViewBuilder
    private var previewThumbnail: some View {
        if item.payload.isImageFileAttachment, let image = item.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
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
            previewIcon(
                symbol: item.symbolName,
                color: item.payload.isImageFileAttachment
                    ? AirCopyTheme.highlight(for: colorScheme)
                    : AirCopyTheme.warning(for: colorScheme)
            )
        case .text:
            previewIcon(symbol: item.symbolName, color: AirCopyTheme.accent(for: colorScheme))
        }
        }
    }

    private var isPreviewable: Bool {
        item.kind == .text || item.kind == .code || item.kind == .image || item.payload.isImageFileAttachment
    }

    private var historyLinkURL: URL? {
        guard item.kind == .link || item.kind == .browserTab,
              let urlString = item.payload.urlString,
              let url = URL(string: urlString) else {
            return nil
        }

        return url
    }

    private func previewIcon(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 64, height: 64)
            .background(AirCopyTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func actionIconButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func openHistoryLink() {
        guard let historyLinkURL else { return }
        NSWorkspace.shared.open(historyLinkURL)
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

private struct HistoryPreviewSheet: View {
    let item: ClipboardHistoryItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))

                    Text(item.detailText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AirCopyTheme.insetFill(for: colorScheme), in: Capsule())
            }

            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 460)
        .background(AirCopyTheme.background(for: colorScheme))
    }

    @ViewBuilder
    private var previewContent: some View {
        if item.kind == .image || item.payload.isImageFileAttachment, let image = item.image {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AirCopyTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else if item.kind == .text || item.kind == .code {
            ScrollView {
                Text(item.payload.text ?? item.previewText)
                    .font(
                        item.kind == .code
                            ? .system(size: 13, weight: .medium, design: .monospaced)
                            : .system(size: 14, weight: .regular)
                    )
                    .foregroundStyle(AirCopyTheme.primaryText(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .background(
                item.kind == .code
                    ? AirCopyTheme.codeBlockFill(for: colorScheme)
                    : AirCopyTheme.panelFill(for: colorScheme),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        } else {
            Text("Preview is only available for images and text.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AirCopyTheme.secondaryText(for: colorScheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .background(AirCopyTheme.panelFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
