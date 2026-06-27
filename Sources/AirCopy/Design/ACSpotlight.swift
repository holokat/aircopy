import AppKit
import SwiftUI

// MARK: - Spotlight palette (always dark, like macOS Spotlight)

private enum SP {
    static let ink = Color.white
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.34)
    static let accent = Color(hex: 0x3B82FF)
    static let rowSelected = Color.white.opacity(0.07)
    static let fill = Color.white.opacity(0.05)
    static let fillStrong = Color.white.opacity(0.08)
    static let hairline = Color.black.opacity(0.32)
    static let border = Color.black.opacity(0.55)
    static let chip = Color.white.opacity(0.08)
}

/// Filter tabs in the order shown in the design.
private let spotlightFilters: [ClipTypeFilter] = [.all, .text, .link, .image, .color]

// MARK: - Model

@MainActor
final class SpotlightModel: ObservableObject {
    @Published var query = "" { didSet { selectedIndex = 0 } }
    @Published var typeFilter: ClipTypeFilter = .all { didSet { selectedIndex = 0 } }
    @Published var selectedIndex = 0

    weak var coordinator: AirCopyCoordinator?
    var onClose: (() -> Void)?

    func reset() {
        query = ""
        typeFilter = .all
        selectedIndex = 0
    }

    func results() -> [ClipboardHistoryItem] {
        guard let coordinator else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return coordinator.clipboardHistory.filter { item in
            guard typeFilter.matches(item.cardKind) else { return false }
            if q.isEmpty { return true }
            return (item.payload.searchableText + " " + item.senderName).lowercased().contains(q)
        }
    }

    func count(for filter: ClipTypeFilter) -> Int {
        guard let coordinator else { return 0 }
        return coordinator.clipboardHistory.filter { filter.matches($0.cardKind) }.count
    }

    func selected() -> ClipboardHistoryItem? {
        let r = results()
        return r.indices.contains(selectedIndex) ? r[selectedIndex] : nil
    }

    // Keyboard actions (driven by the panel's key monitor).
    func moveDown() { selectedIndex = min(selectedIndex + 1, max(results().count - 1, 0)) }
    func moveUp() { selectedIndex = max(selectedIndex - 1, 0) }

    func copySelected() {
        guard let item = selected() else { return }
        coordinator?.restoreHistoryItem(item)
        onClose?()
    }

    func copy(_ item: ClipboardHistoryItem) {
        coordinator?.restoreHistoryItem(item)
        onClose?()
    }

    /// ⌘1…⌘9 quick copy of the Nth visible result (1-based).
    func quickCopy(_ number: Int) {
        let r = results()
        let idx = number - 1
        guard r.indices.contains(idx) else { return }
        coordinator?.restoreHistoryItem(r[idx])
        onClose?()
    }

    func send(_ item: ClipboardHistoryItem, to deviceID: String) {
        coordinator?.sendHistoryItem(item, to: deviceID)
    }
}

// MARK: - View

struct ACSpotlightView: View {
    @ObservedObject var model: SpotlightModel
    @EnvironmentObject private var coordinator: AirCopyCoordinator
    @FocusState private var searchFocused: Bool

    private var items: [ClipboardHistoryItem] { model.results() }
    private var trustedPeers: [PeerDeviceState] {
        coordinator.peerDevices.filter { $0.trustState == .trusted }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider().overlay(SP.hairline)
            filterTabs
            Divider().overlay(SP.hairline)
            if items.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    resultsList
                    Rectangle().fill(SP.hairline).frame(width: 1)
                    detailPanel
                        .frame(width: 286)
                }
            }
            Divider().overlay(SP.hairline)
            footer
        }
        .frame(width: 720, height: 496)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: 0x101015, alpha: 0.55))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SP.border, lineWidth: 1)
        )
        .onAppear { searchFocused = true }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 13) {
            ACLogoTile(size: 30, corner: 9, glyph: 16)
            TextField("Search your clipboard across every Mac…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(SP.ink)
                .focused($searchFocused)
            HStack(spacing: 5) {
                keyCap("⌥")
                keyCap("Space")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
    }

    // MARK: Filter tabs

    private var filterTabs: some View {
        HStack(spacing: 7) {
            ForEach(spotlightFilters) { filter in
                let active = model.typeFilter == filter
                Button { model.typeFilter = filter } label: {
                    HStack(spacing: 6) {
                        Text(filter.label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(active ? SP.accent : SP.textSecondary)
                        Text("\(model.count(for: filter))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(active ? SP.accent.opacity(0.8) : SP.textTertiary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(active ? SP.accent.opacity(0.16) : SP.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
    }

    // MARK: Results list

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        resultRow(item, index: index)
                            .id(index)
                            .onTapGesture { model.selectedIndex = index }
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selectedIndex) { _, idx in
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(idx, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func resultRow(_ item: ClipboardHistoryItem, index: Int) -> some View {
        let selected = index == model.selectedIndex
        return HStack(spacing: 12) {
            rowIcon(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(item))
                    .font(item.cardKind == .text || item.cardKind == .color ? .system(size: 13.5, design: .monospaced) : .system(size: 13.5, weight: .medium))
                    .foregroundStyle(SP.ink)
                    .lineLimit(1)
                Text(rowSubtitle(item))
                    .font(.system(size: 11.5))
                    .foregroundStyle(SP.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if selected {
                keyCap("↵")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(selected ? SP.rowSelected : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(selected ? SP.accent.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowIcon(_ item: ClipboardHistoryItem) -> some View {
        switch item.cardKind {
        case .color:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hexString: item.colorHex ?? "#000000") ?? .black)
                .frame(width: 30, height: 30)
        case .image:
            Group {
                if let img = coordinator.imageThumbnail(for: item) ?? item.image {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x2A3380), Color(hex: 0x6A3FB0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .link:
            iconTile("link", tint: SP.accent)
        case .text:
            iconTile("text.alignleft", tint: SP.accent)
        }
    }

    private func iconTile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func rowTitle(_ item: ClipboardHistoryItem) -> String {
        switch item.cardKind {
        case .text: return item.textPreview.replacingOccurrences(of: "\n", with: " ")
        case .link: return item.linkTitleText
        case .image: return item.imageFilename
        case .color: return item.colorHex ?? item.textPreview
        }
    }

    private func rowSubtitle(_ item: ClipboardHistoryItem) -> String {
        if item.cardKind == .link, !item.linkDomain.isEmpty {
            return "\(item.linkDomain) · \(item.relativeAgo)"
        }
        return "\(item.senderName) · \(item.relativeAgo)"
    }

    // MARK: Detail panel

    @ViewBuilder
    private var detailPanel: some View {
        if let item = model.selected() {
            VStack(alignment: .leading, spacing: 14) {
                detailPreview(item)
                detailMetadata(item)
                Button { model.copy(item) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc").font(.system(size: 12, weight: .semibold))
                        Text("Copy to clipboard").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        keyCap("↵")
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(SP.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)

                if !trustedPeers.isEmpty {
                    Text("SEND TO DEVICE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(SP.textTertiary)
                        .padding(.top, 2)
                    ForEach(trustedPeers) { peer in
                        Button { model.send(item, to: peer.id) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: peer.deviceSymbolName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(peer.isAutoSyncEnabled ? SP.textSecondary : SP.textTertiary)
                                    .frame(width: 18)
                                Text(peer.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(peer.isAutoSyncEnabled ? SP.ink : SP.textTertiary)
                                Spacer()
                                if !peer.isAutoSyncEnabled {
                                    Text("off").font(.system(size: 11)).foregroundStyle(SP.textTertiary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(SP.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func detailPreview(_ item: ClipboardHistoryItem) -> some View {
        Group {
            switch item.cardKind {
            case .image:
                if let img = coordinator.imageThumbnail(for: item) ?? item.image {
                    Image(nsImage: img).interpolation(.high).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x2A3380), Color(hex: 0x6A3FB0)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            case .color:
                ZStack {
                    Color(hexString: item.colorHex ?? "#000000") ?? .black
                    Text(item.colorHex ?? "")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.readableInk(onHex: item.colorHex ?? "#000000"))
                }
            default:
                ScrollView {
                    Text(detailText(item))
                        .font(item.cardKind == .text ? .system(size: 13, design: .monospaced) : .system(size: 13))
                        .foregroundStyle(SP.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                }
            }
        }
        .frame(height: 96)
        .frame(maxWidth: .infinity)
        .background(SP.fill)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailText(_ item: ClipboardHistoryItem) -> String {
        switch item.cardKind {
        case .link: return "\(item.linkTitleText)\n\(item.linkURLText)"
        default: return item.textPreview
        }
    }

    private func detailMetadata(_ item: ClipboardHistoryItem) -> some View {
        VStack(spacing: 0) {
            metaRow("From", item.senderName)
            Divider().overlay(SP.hairline)
            metaRow("Captured", item.relativeAgo)
            Divider().overlay(SP.hairline)
            metaRow(item.extraMetadata.label, item.extraMetadata.value)
        }
        .background(SP.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(SP.textTertiary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(SP.textSecondary).lineLimit(1)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
    }

    // MARK: Footer + misc

    private var footer: some View {
        HStack(spacing: 16) {
            footerHint([("↑", nil), ("↓", "navigate")])
            footerHint([("↵", "copy")])
            footerHint([("⌘", nil), ("1-9", "quick copy")])
            footerHint([("esc", "close")])
            Spacer()
            Text("\(items.count) result\(items.count == 1 ? "" : "s")")
                .font(.system(size: 11.5)).foregroundStyle(SP.textTertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
    }

    private func footerHint(_ parts: [(String, String?)]) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                keyCap(part.0)
                if let label = part.1 {
                    Text(label).font(.system(size: 11.5)).foregroundStyle(SP.textTertiary)
                }
            }
        }
    }

    private func keyCap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(SP.textSecondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(SP.chip, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(SP.textTertiary)
            Text(model.query.isEmpty ? "No clips yet" : "No clips match “\(model.query)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SP.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
