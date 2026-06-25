import Foundation

enum ClipboardReceiptKind: String, Codable, Hashable {
    case delivered
    case clipboardUpdated
    case skipped
}

struct ClipboardMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let payload: ClipboardPayload
    let sentAt: Date
}

struct ClipboardReceipt: Codable, Hashable {
    let messageID: UUID
    let recipientID: String
    let recipientName: String
    let kind: ClipboardReceiptKind
    let sentAt: Date
}

struct PeerPresence: Codable, Hashable {
    let senderID: String
    let senderName: String
    let sentAt: Date
}

struct AirCopyWireMessage: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case clipboard
        case receipt
        case presence
    }

    let kind: Kind
    let clipboard: ClipboardMessage?
    let receipt: ClipboardReceipt?
    let presence: PeerPresence?

    static func clipboard(_ message: ClipboardMessage) -> AirCopyWireMessage {
        AirCopyWireMessage(kind: .clipboard, clipboard: message, receipt: nil, presence: nil)
    }

    static func receipt(_ receipt: ClipboardReceipt) -> AirCopyWireMessage {
        AirCopyWireMessage(kind: .receipt, clipboard: nil, receipt: receipt, presence: nil)
    }

    static func presence(_ presence: PeerPresence) -> AirCopyWireMessage {
        AirCopyWireMessage(kind: .presence, clipboard: nil, receipt: nil, presence: presence)
    }
}
