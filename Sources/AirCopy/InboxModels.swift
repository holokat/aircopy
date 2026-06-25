import Foundation

enum IncomingClipboardState: String, Codable, Hashable {
    case pending
    case accepted
    case rejected

    var title: String {
        switch self {
        case .pending:
            return "Needs Review"
        case .accepted:
            return "Copied"
        case .rejected:
            return "Rejected"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "tray.and.arrow.down"
        case .accepted:
            return "checkmark.circle.fill"
        case .rejected:
            return "xmark.circle"
        }
    }
}

struct IncomingClipboardItem: Identifiable, Hashable {
    let message: ClipboardMessage
    let receivedAt: Date
    var state: IncomingClipboardState

    var id: UUID { message.id }
    var senderID: String { message.senderID }
    var senderName: String { message.senderName }
    var payload: ClipboardPayload { message.payload }
    var sentAt: Date { message.sentAt }
}
