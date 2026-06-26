import AppKit
import SwiftUI

struct ACMainWindow: View {
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var toast: ACToastCenter
    @EnvironmentObject private var updater: SparkleUpdater

    @State private var query = ""
    @State private var typeFilter: ClipTypeFilter = .all
    @State private var deviceFilter: String?
    @State private var pinnedOnly = false
    @State private var sort: ClipSort = .recent
    @State private var selectedID: UUID?
    @State private var sortOpen = false
    @State private var addMacPresented = false
    @State private var copiedID: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                titlebar
                Divider().overlay(ACColor.border08)
                bodyContent
            }
            .background(ACColor.surface)

            ACToastOverlay(toast: toast)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Pin the titlebar flush to the window top; the hidden native title bar
        // can otherwise leave a top safe-area inset (empty gap above the row).
        .ignoresSafeArea(.container, edges: .top)
        .background(TitlebarConfigurator())
        .onExitCommand {
            if sortOpen { sortOpen = false }
            else if selectedID != nil { selectedID = nil }
            else if addMacPresented { addMacPresented = false }
            else if coordinator.settingsPresented { coordinator.settingsPresented = false }
        }
        .sheet(isPresented: $coordinator.settingsPresented) {
            ACSettingsSheet()
                .environmentObject(coordinator)
                .environmentObject(settings)
                .environmentObject(toast)
                .environmentObject(updater)
                .preferredColorScheme(coordinator.effectiveColorScheme)
        }
        .sheet(isPresented: $addMacPresented) {
            ACAddMacSheet(isPresented: $addMacPresented)
                .environmentObject(coordinator)
                .environmentObject(toast)
                .preferredColorScheme(coordinator.effectiveColorScheme)
        }
    }

    // MARK: - Titlebar

    private var titlebar: some View {
        HStack(spacing: 9) {
            MacTrafficLights()
                .padding(.leading, 4)
                .padding(.trailing, 12)

            ACLogoTile(size: 24, corner: 7, glyph: 14)
            Text("AirCopy")
                .font(ACFont.sans(14, weight: .semibold))
                .foregroundStyle(ACColor.ink)

            Spacer()

            HStack(spacing: 7) {
                Circle().fill(ACColor.success).frame(width: 7, height: 7)
                Text(syncSummary)
                    .font(ACFont.sans(12, weight: .medium))
                    .foregroundStyle(ACColor.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(ACColor.controlPill, in: Capsule())
            .acBorder(ACColor.border06, radius: 100)

            Button { coordinator.settingsPresented = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
                    .foregroundStyle(ACColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(ACColor.controlPill, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(ACColor.titlebar)
    }

    // MARK: - Body

    private var bodyContent: some View {
        HStack(spacing: 0) {
            ACSidebar(
                devices: sidebarDevices,
                selectedDeviceID: deviceFilter,
                syncShort: syncShort,
                onSelect: { id in deviceFilter = (deviceFilter == id) ? nil : id },
                onToggle: toggleDeviceSync,
                onAddMac: { addMacPresented = true; sortOpen = false }
            )

            mainColumn

            if let item = selectedItem {
                ACDetailPanel(
                    item: item,
                    image: item.image ?? thumbnail(for: item),
                    sendTargets: sendTargets(for: item),
                    onClose: { selectedID = nil },
                    onCopy: { copy(item) },
                    onPin: { coordinator.togglePin(for: item) },
                    onDelete: { delete(item) },
                    onSend: { id in send(item, to: id) }
                )
                .transition(.move(edge: .trailing))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: selectedID)
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            toolbarRow1
                // Lift row 1 (and its sort-popover overlay) above the rows below.
                .zIndex(sortOpen ? 2 : 0)
            Divider().overlay(ACColor.border06)
            toolbarRow2
            Divider().overlay(ACColor.border06)
            grid
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar row 1

    private var toolbarRow1: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(ACColor.textTertiary)
                TextField("Search clips, links, text…", text: $query)
                    .textFieldStyle(.plain)
                    .font(ACFont.sans(13.5))
                    .foregroundStyle(ACColor.ink)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .frame(maxWidth: 420)
            .background(ACColor.controlSearch, in: RoundedRectangle(cornerRadius: 11))
            .acBorder(ACColor.border06, radius: 11)

            Spacer()

            Text(countLabel)
                .font(ACFont.sans(12.5).monospacedDigit())
                .foregroundStyle(ACColor.textTertiary)

            sortControl
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
    }

    private var sortControl: some View {
        Button { sortOpen.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ACColor.textSecondary)
                Text(sort.label)
                    .font(ACFont.sans(13, weight: .medium))
                    .foregroundStyle(ACColor.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ACColor.controlSearch, in: RoundedRectangle(cornerRadius: 11))
            .acBorder(ACColor.border06, radius: 11)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if sortOpen { sortPopover.offset(y: 46) }
        }
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SORT BY")
                .font(ACFont.sans(10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(ACColor.textTertiary)
                .padding(.horizontal, 9)
                .padding(.top, 6)
                .padding(.bottom, 5)
            ForEach(ClipSort.allCases) { option in
                Button {
                    sort = option
                    sortOpen = false
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ACColor.accent)
                            .opacity(sort == option ? 1 : 0)
                            .frame(width: 14)
                        Text(option.label)
                            .font(ACFont.sans(13, weight: .medium))
                            .foregroundStyle(sort == option ? ACColor.accent : ACColor.textMuted)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(sort == option ? ACColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .frame(width: 172)
        .background(ACColor.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .acBorder(ACColor.border10, radius: 13)
        .shadow(color: Color(hex: 0x0A0F28, alpha: 0.32), radius: 25, x: 0, y: 18)
        .fixedSize()
        .zIndex(40)
    }

    // MARK: - Toolbar row 2

    private var toolbarRow2: some View {
        HStack {
            // type segments
            HStack(spacing: 2) {
                ForEach(ClipTypeFilter.allCases) { seg in
                    let active = typeFilter == seg
                    Button {
                        typeFilter = seg
                        pinnedOnly = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: seg.symbol)
                                .font(.system(size: 11, weight: .medium))
                            Text(seg.label)
                                .font(ACFont.sans(12.5, weight: .medium))
                        }
                        .foregroundStyle(active ? ACColor.accent : ACColor.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(active ? ACColor.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: active ? Color(hex: 0x141E3C, alpha: 0.14) : .clear, radius: 1.5, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(ACColor.controlTrack, in: RoundedRectangle(cornerRadius: 11))

            Spacer()

            // All / Pinned group
            HStack(spacing: 2) {
                pinnedGroupButton(label: "All", systemImage: "square.stack.3d.up", active: !pinnedOnly, count: nil) {
                    pinnedOnly = false
                }
                pinnedGroupButton(label: "Pinned", systemImage: "pin", active: pinnedOnly, count: pinnedCount) {
                    pinnedOnly = true
                }
            }
            .padding(3)
            .background(ACColor.controlTrack, in: RoundedRectangle(cornerRadius: 11))
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private func pinnedGroupButton(label: String, systemImage: String, active: Bool, count: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .medium))
                Text(label).font(ACFont.sans(12.5, weight: .medium))
                if let count {
                    Text("\(count)")
                        .font(ACFont.sans(10.5).monospacedDigit())
                        .foregroundStyle(active ? ACColor.accent.opacity(0.7) : ACColor.textTertiary)
                }
            }
            .foregroundStyle(active ? ACColor.accent : ACColor.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(active ? ACColor.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: active ? Color(hex: 0x141E3C, alpha: 0.14) : .clear, radius: 1.5, x: 0, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grid

    private var grid: some View {
        ZStack {
            ACColor.grid
            if filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 232), spacing: 14)], alignment: .leading, spacing: 14) {
                        ForEach(filteredItems) { item in
                            ACClipCard(
                                item: item,
                                deviceName: item.senderName,
                                isSelected: selectedID == item.id,
                                isCopied: copiedID == item.id,
                                thumbnail: thumbnail(for: item),
                                onOpen: { selectedID = item.id },
                                onCopy: { copy(item) },
                                onPin: { coordinator.togglePin(for: item) }
                            )
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Dismiss the sort popover on any tap in the grid area.
        .overlay {
            if sortOpen {
                Color.clear.contentShape(Rectangle()).onTapGesture { sortOpen = false }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color(hex: 0xC2C6CF))
            Text(syncingDeviceCount == 0 ? "No devices syncing" : "No clips match")
                .font(ACFont.sans(15, weight: .medium))
                .foregroundStyle(ACColor.textSecondary2)
            Text(syncingDeviceCount == 0 ? "Turn on sync for a device in the sidebar." : "Try a different search or filter.")
                .font(ACFont.sans(13))
                .foregroundStyle(ACColor.textTertiary)
        }
        .padding(.bottom, 40)
    }

    // MARK: - Derived data

    private var trustedPeers: [PeerDeviceState] {
        coordinator.peerDevices.filter { $0.trustState == .trusted }
    }

    private var peerByID: [String: PeerDeviceState] {
        Dictionary(uniqueKeysWithValues: trustedPeers.map { ($0.id, $0) })
    }

    private var peerByName: [String: PeerDeviceState] {
        Dictionary(trustedPeers.map { ($0.displayName, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func deviceID(for item: ClipboardHistoryItem) -> String {
        if item.senderName == coordinator.localDeviceName { return "local" }
        if let peer = peerByName[item.senderName] { return peer.id }
        return "ext:" + item.senderName
    }

    // The full clipboard history is always shown. A device's auto-sync toggle
    // only governs whether new clips are *sent* to/from it — it must not hide
    // clips already in history (doing so made received clips vanish when a
    // toggle flipped or a peer's connection flapped). Filtering by device is
    // explicit, via tapping a device in the sidebar (`deviceFilter`).
    private var total: Int { coordinator.clipboardHistory.count }
    private var pinnedCount: Int { coordinator.clipboardHistory.filter(\.isPinned).count }

    private var filteredItems: [ClipboardHistoryItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var items = coordinator.clipboardHistory.filter { item in
            if pinnedOnly && !item.isPinned { return false }
            if !typeFilter.matches(item.cardKind) { return false }
            if let dev = deviceFilter, deviceID(for: item) != dev { return false }
            if !q.isEmpty {
                let hay = (item.payload.searchableText + " " + item.senderName).lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }
        switch sort {
        case .recent:
            items.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                return lhs.date > rhs.date
            }
        case .oldest:
            items.sort { $0.date < $1.date }
        case .device:
            items.sort { lhs, rhs in
                if lhs.senderName != rhs.senderName { return lhs.senderName < rhs.senderName }
                return lhs.date > rhs.date
            }
        case .type:
            items.sort { lhs, rhs in
                if typeRank(lhs) != typeRank(rhs) { return typeRank(lhs) < typeRank(rhs) }
                return lhs.date > rhs.date
            }
        }
        return items
    }

    private func typeRank(_ item: ClipboardHistoryItem) -> Int {
        switch item.cardKind {
        case .color: return 0
        case .image: return 1
        case .link: return 2
        case .text: return 3
        }
    }

    private var sidebarDevices: [ACSidebarDevice] {
        var counts: [String: Int] = [:]
        for item in coordinator.clipboardHistory {
            counts[deviceID(for: item), default: 0] += 1
        }
        var rows: [ACSidebarDevice] = [
            ACSidebarDevice(
                id: "local",
                name: coordinator.localDeviceName,
                isThis: true,
                symbol: deviceSFSymbolName(for: coordinator.localDeviceName),
                syncOn: coordinator.syncEnabled,
                clipCount: counts["local"] ?? 0
            )
        ]
        for peer in trustedPeers {
            rows.append(
                ACSidebarDevice(
                    id: peer.id,
                    name: peer.displayName,
                    isThis: false,
                    symbol: peer.deviceSymbolName,
                    syncOn: peer.isAutoSyncEnabled,
                    clipCount: counts[peer.id] ?? 0
                )
            )
        }
        return rows
    }

    private var syncingDeviceCount: Int { sidebarDevices.filter(\.syncOn).count }
    private var syncSummary: String { "\(syncingDeviceCount) of \(sidebarDevices.count) syncing" }
    private var syncShort: String { "\(syncingDeviceCount)/\(sidebarDevices.count) on" }

    private var countLabel: String {
        filteredItems.count == total ? "\(total) clips" : "\(filteredItems.count) of \(total)"
    }

    private var selectedItem: ClipboardHistoryItem? {
        guard let id = selectedID else { return nil }
        return coordinator.clipboardHistory.first { $0.id == id }
    }

    private func thumbnail(for item: ClipboardHistoryItem) -> NSImage? {
        coordinator.imageThumbnail(for: item) ?? item.image
    }

    private func sendTargets(for item: ClipboardHistoryItem) -> [ACSendTarget] {
        let ownerID = deviceID(for: item)
        return trustedPeers
            .filter { $0.id != ownerID }
            .map { ACSendTarget(id: $0.id, name: $0.displayName, symbol: $0.deviceSymbolName, enabled: $0.isAutoSyncEnabled) }
    }

    // MARK: - Actions

    private func toggleDeviceSync(_ id: String) {
        if id == "local" {
            coordinator.syncEnabled.toggle()
            toast.show(coordinator.syncEnabled ? "This Mac syncing" : "This Mac paused", accent: coordinator.syncEnabled ? ACColor.success : ACColor.textTertiary)
        } else if let peer = peerByID[id] {
            coordinator.setAutoSyncEnabled(!peer.isAutoSyncEnabled, for: id)
            toast.show(!peer.isAutoSyncEnabled ? "\(peer.displayName) syncing" : "\(peer.displayName) paused")
        }
    }

    private func copy(_ item: ClipboardHistoryItem) {
        coordinator.restoreHistoryItem(item)
        toast.show("Copied to clipboard")
        let id = item.id
        copiedID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedID == id { copiedID = nil }
        }
    }

    private func delete(_ item: ClipboardHistoryItem) {
        coordinator.deleteHistoryItem(item)
        selectedID = nil
        toast.show("Clip deleted", accent: ACColor.danger)
    }

    private func send(_ item: ClipboardHistoryItem, to id: String) {
        coordinator.sendHistoryItem(item, to: id)
        let name = peerByID[id]?.displayName ?? "device"
        toast.show("Sent to \(name)")
    }
}

/// Dark rounded-square logo tile with the white "sync" glyph.
struct ACLogoTile: View {
    var size: CGFloat = 24
    var corner: CGFloat = 7
    var glyph: CGFloat = 14

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(ACColor.darkTile)
            ACSyncGlyph().frame(width: glyph, height: glyph)
        }
        .frame(width: size, height: size)
    }
}

/// Two filled nodes joined by an arc (from the design's SVG logo).
struct ACSyncGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let p1 = CGPoint(x: 9.0 / 32 * w, y: 22.0 / 32 * h)
            let p2 = CGPoint(x: 23.0 / 32 * w, y: 10.0 / 32 * h)
            ZStack {
                Path { path in
                    path.move(to: p1)
                    path.addCurve(
                        to: p2,
                        control1: CGPoint(x: 9.0 / 32 * w, y: 14.5 / 32 * h),
                        control2: CGPoint(x: 23.0 / 32 * w, y: 17.0 / 32 * h)
                    )
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2.4 / 32 * w, lineCap: .round))
                Circle().fill(.white).frame(width: 6.8 / 32 * w, height: 6.8 / 32 * w).position(p1)
                Circle().fill(.white).frame(width: 6.8 / 32 * w, height: 6.8 / 32 * w).position(p2)
            }
        }
    }
}
