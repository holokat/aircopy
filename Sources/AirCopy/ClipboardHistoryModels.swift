import AppKit
import Foundation

struct ClipboardHistoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    let fingerprint: String
    let payload: ClipboardPayload
    var source: String
    var senderName: String
    var date: Date
    var isPinned: Bool
    var isFavorite: Bool
    var deviceReceipts: [DeviceReceipt]
    var lastSyncAt: Date?
    var wasDeliveredRemotely: Bool

    init(
        id: UUID = UUID(),
        payload: ClipboardPayload,
        source: String,
        senderName: String,
        date: Date,
        isPinned: Bool = false,
        isFavorite: Bool = false,
        deviceReceipts: [DeviceReceipt] = [],
        lastSyncAt: Date? = nil,
        wasDeliveredRemotely: Bool = false
    ) {
        self.id = id
        self.fingerprint = payload.fingerprint
        self.payload = payload
        self.source = source
        self.senderName = senderName
        self.date = date
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.deviceReceipts = deviceReceipts
        self.lastSyncAt = lastSyncAt
        self.wasDeliveredRemotely = wasDeliveredRemotely
    }

    var kind: ClipboardPayloadKind {
        payload.kind
    }

    var title: String {
        payload.title
    }

    var symbolName: String {
        payload.symbolName
    }

    var previewText: String {
        payload.previewText
    }

    var image: NSImage? {
        payload.image
    }

    var detailText: String {
        payload.detailText
    }

    var primaryReceipt: DeviceReceipt? {
        deviceReceipts.sorted { $0.date > $1.date }.first
    }
}
