import AppKit
import Foundation

enum ClipboardPayloadKind: String, Codable, Hashable {
    case text
    case image

    var title: String {
        switch self {
        case .text:
            return "Text Clip"
        case .image:
            return "Image Clip"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .image:
            return "photo.on.rectangle.angled"
        }
    }
}

struct ClipboardPayload: Codable, Hashable {
    let kind: ClipboardPayloadKind
    let text: String?
    let imageData: Data?

    init(text: String) {
        self.kind = .text
        self.text = text
        self.imageData = nil
    }

    init(imageData: Data) {
        self.kind = .image
        self.text = nil
        self.imageData = imageData
    }

    var previewText: String {
        switch kind {
        case .text:
            let normalized = (text ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if normalized.count <= 160 {
                return normalized
            }

            let index = normalized.index(normalized.startIndex, offsetBy: 157)
            return "\(normalized[..<index])..."
        case .image:
            if let size = imageSize {
                return "\(Int(size.width)) × \(Int(size.height)) PNG"
            }
            return "PNG image"
        }
    }

    var image: NSImage? {
        guard let imageData else { return nil }
        return NSImage(data: imageData)
    }

    var imageSize: NSSize? {
        image?.size
    }
}

struct ClipboardMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let payload: ClipboardPayload
    let sentAt: Date
}

struct ClipboardHistoryItem: Identifiable, Hashable {
    let id: UUID
    let payload: ClipboardPayload
    let source: String
    let senderName: String
    let date: Date

    var kind: ClipboardPayloadKind {
        payload.kind
    }

    var title: String {
        switch payload.kind {
        case .text:
            let preview = payload.previewText
            return preview.isEmpty ? "Empty text clip" : preview
        case .image:
            return payload.previewText
        }
    }

    var symbolName: String {
        payload.kind.symbolName
    }

    var previewText: String {
        payload.previewText
    }

    var image: NSImage? {
        payload.image
    }

    var detailText: String {
        switch payload.kind {
        case .text:
            let count = payload.text?.count ?? 0
            return count == 1 ? "1 character" : "\(count) characters"
        case .image:
            return payload.previewText
        }
    }
}
