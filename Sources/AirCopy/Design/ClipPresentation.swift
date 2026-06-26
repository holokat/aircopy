import AppKit
import SwiftUI

// The redesign renders four card types: text, image, link, color.
// This bridges the richer backend payload kinds onto that model.
enum ClipCardKind {
    case text
    case image
    case link
    case color
}

enum ClipTypeFilter: String, CaseIterable, Identifiable {
    case all, text, image, link, color
    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "All"
        case .text: return "Text"
        case .image: return "Images"
        case .link: return "Links"
        case .color: return "Colors"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .color: return "paintpalette"
        }
    }

    func matches(_ kind: ClipCardKind) -> Bool {
        switch self {
        case .all: return true
        case .text: return kind == .text
        case .image: return kind == .image
        case .link: return kind == .link
        case .color: return kind == .color
        }
    }
}

enum ClipSort: String, CaseIterable, Identifiable {
    case recent, oldest, device, type
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "Recent"
        case .oldest: return "Oldest"
        case .device: return "Device"
        case .type: return "Type"
        }
    }
}

extension ClipboardHistoryItem {
    var cardKind: ClipCardKind {
        if payload.kind == .image || payload.isImageFileAttachment { return .image }
        if payload.kind == .link || payload.kind == .browserTab { return .link }
        if Self.hexColor(from: payload) != nil { return .color }
        return .text
    }

    /// Hex string when the clip is a bare color value (e.g. "#0A6CFF").
    var colorHex: String? { Self.hexColor(from: payload) }

    var isMonospaced: Bool {
        if payload.kind == .code { return true }
        guard let text = payload.text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Heuristic: short single-line strings full of code-ish characters.
        let codeish = CharacterSet(charactersIn: "{}();=<>/\\$|`#")
        if trimmed.rangeOfCharacter(from: codeish) != nil, !trimmed.contains(" \n") { return true }
        return false
    }

    var textPreview: String {
        payload.text ?? payload.plainTextRepresentation
    }

    var linkTitleText: String {
        payload.linkTitle ?? payload.title
    }

    var linkURLText: String {
        payload.urlString ?? payload.text ?? ""
    }

    var linkDomain: String {
        guard let urlString = payload.urlString,
              let host = URL(string: urlString)?.host(percentEncoded: false) else {
            return linkURLText
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    var faviconLetter: String {
        String(linkDomain.prefix(1)).uppercased()
    }

    var imageFilename: String {
        if let name = payload.attachments.first?.name { return name }
        return payload.title.isEmpty ? "Image" : payload.title
    }

    var typeLabel: String {
        switch cardKind {
        case .text: return "Text snippet"
        case .image: return "Image"
        case .link: return "Link"
        case .color: return "Color"
        }
    }

    /// Detail-panel "extra" metadata row (label + value).
    var extraMetadata: (label: String, value: String) {
        switch cardKind {
        case .text:
            let count = (payload.text ?? "").count
            return ("Length", "\(count) char\(count == 1 ? "" : "s")")
        case .image:
            if let bytes = payload.imageData?.count {
                return ("Size", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
            }
            return ("Size", payload.previewText)
        case .link:
            return ("Domain", linkDomain)
        case .color:
            return ("Format", "HEX")
        }
    }

    var relativeAgo: String { ACRelativeTime.string(for: date) }

    static func hexColor(from payload: ClipboardPayload) -> String? {
        guard payload.kind == .text || payload.kind == .code, let raw = payload.text else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else { return nil }
        let body = String(trimmed.dropFirst())
        let valid = body.count == 3 || body.count == 6 || body.count == 8
        guard valid, body.allSatisfy({ $0.isHexDigit }) else { return nil }
        return trimmed.uppercased()
    }
}

enum ACRelativeTime {
    static func string(for date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(seconds / 86400)
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

extension Color {
    /// Parse a "#RRGGBB" / "#RGB" / "#RRGGBBAA" string.
    init?(hexString: String) {
        var body = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("#") { body.removeFirst() }
        if body.count == 3 {
            body = body.map { "\($0)\($0)" }.joined()
        }
        guard body.count == 6 || body.count == 8, let value = UInt32(body.prefix(6), radix: 16) else { return nil }
        self.init(hex: value)
    }

    /// Pick a readable foreground (white/ink) for a given hex background.
    static func readableInk(onHex hexString: String) -> Color {
        var body = hexString
        if body.hasPrefix("#") { body.removeFirst() }
        if body.count == 3 { body = body.map { "\($0)\($0)" }.joined() }
        guard body.count >= 6, let value = UInt32(body.prefix(6), radix: 16) else { return ACColor.ink }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >> 8) & 0xFF)
        let b = Double(value & 0xFF)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 150 ? .white : ACColor.ink
    }
}
