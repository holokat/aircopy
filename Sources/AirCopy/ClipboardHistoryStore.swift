import Foundation

enum ClipboardHistoryStore {
    static func sorted(_ history: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        history.sorted(by: sort)
    }

    static func filtered(
        _ history: [ClipboardHistoryItem],
        searchText: String,
        filter: HistoryFilter
    ) -> [ClipboardHistoryItem] {
        history
            .filter { item in
                guard filter.matches(item.kind) else { return false }
                guard !searchText.isEmpty else { return true }
                return item.payload.searchableText.contains(searchText.lowercased())
            }
            .sorted(by: sort)
    }

    static func hasClearableItems(_ history: [ClipboardHistoryItem]) -> Bool {
        history.contains { !$0.isPinned && !$0.isFavorite }
    }

    static func clearNonRetainedItems(_ history: inout [ClipboardHistoryItem]) -> Int {
        let removedCount = history.reduce(into: 0) { count, item in
            if !item.isPinned && !item.isFavorite {
                count += 1
            }
        }

        history.removeAll { !$0.isPinned && !$0.isFavorite }
        return removedCount
    }

    @discardableResult
    static func sortAndTrim(_ history: inout [ClipboardHistoryItem], maxItems: Int) -> Set<String> {
        history.sort(by: sort)

        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }

        return Set(history.map(\.fingerprint))
    }

    static func record(
        payload: ClipboardPayload,
        source: String,
        senderName: String,
        date: Date,
        deliveredRemotely: Bool,
        history: inout [ClipboardHistoryItem],
        pinnedFingerprints: Set<String>,
        favoriteFingerprints: Set<String>,
        maxItems: Int
    ) -> ClipboardHistoryItem {
        let existing = history.first(where: { $0.fingerprint == payload.fingerprint })

        let item = ClipboardHistoryItem(
            id: existing?.id ?? UUID(),
            payload: payload,
            source: source,
            senderName: senderName,
            date: date,
            isPinned: existing?.isPinned ?? pinnedFingerprints.contains(payload.fingerprint),
            isFavorite: existing?.isFavorite ?? favoriteFingerprints.contains(payload.fingerprint),
            deviceReceipts: existing?.deviceReceipts ?? [],
            lastSyncAt: deliveredRemotely ? date : existing?.lastSyncAt,
            wasDeliveredRemotely: deliveredRemotely || (existing?.wasDeliveredRemotely ?? false)
        )

        history.removeAll { $0.fingerprint == payload.fingerprint }
        history.append(item)
        sortAndTrim(&history, maxItems: maxItems)
        return item
    }

    static func updateItem(
        id: UUID,
        source: String,
        senderName: String,
        date: Date,
        history: inout [ClipboardHistoryItem],
        maxItems: Int
    ) -> Bool {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return false }
        history[index].source = source
        history[index].senderName = senderName
        history[index].date = date
        sortAndTrim(&history, maxItems: maxItems)
        return true
    }

    static func sort(_ lhs: ClipboardHistoryItem, _ rhs: ClipboardHistoryItem) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned && !rhs.isPinned
        }

        if lhs.isFavorite != rhs.isFavorite {
            return lhs.isFavorite && !rhs.isFavorite
        }

        return lhs.date > rhs.date
    }
}
