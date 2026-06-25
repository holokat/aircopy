import AppKit
import Foundation

extension ClipboardPayload {
    var title: String {
        switch kind {
        case .text:
            return previewText.isEmpty ? "Empty text clip" : previewText
        case .code:
            if let languageHint {
                return "\(languageHint.capitalized) snippet"
            }
            return "Code snippet"
        case .link:
            return linkTitle ?? hostDisplay ?? urlString ?? "Link"
        case .browserTab:
            return linkTitle ?? hostDisplay ?? "Browser tab"
        case .image:
            return previewText
        case .file, .folder:
            if attachments.count == 1, let first = attachments.first {
                return first.name
            }
            return "\(attachments.count) \(kind == .folder ? "items" : "files")"
        }
    }

    var previewText: String {
        switch kind {
        case .text:
            return normalizedText(limit: 160)
        case .code:
            let condensed = (text ?? "")
                .replacingOccurrences(of: "\t", with: "    ")
                .split(separator: "\n")
                .prefix(3)
                .map(String.init)
                .joined(separator: "  ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return condensed.isEmpty ? "Code snippet" : condensed
        case .link:
            return urlDisplay ?? "Link"
        case .browserTab:
            return urlDisplay ?? linkTitle ?? "Browser tab"
        case .image:
            if let imageWidth, let imageHeight {
                return "\(imageWidth) × \(imageHeight) image"
            }
            return "Image"
        case .file:
            return attachmentSummary
        case .folder:
            return attachmentSummary
        }
    }

    var detailText: String {
        switch kind {
        case .text:
            let count = text?.count ?? 0
            return count == 1 ? "1 character" : "\(count) characters"
        case .code:
            let lineCount = max(1, text?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0)
            if let languageHint {
                return "\(languageHint.capitalized) • \(lineCount) lines"
            }
            return "\(lineCount) lines"
        case .link:
            return hostDisplay ?? "URL"
        case .browserTab:
            return [linkTitle, hostDisplay].compactMap { $0 }.joined(separator: " • ")
        case .image:
            return previewText
        case .file, .folder:
            if attachments.count == 1, let first = attachments.first {
                return [first.isDirectory ? "Folder" : "File", first.byteCountLabel].compactMap { $0 }.joined(separator: " • ")
            }
            return attachmentSummary
        }
    }

    var symbolName: String {
        if isImageFileAttachment {
            return ClipboardPayloadKind.image.symbolName
        }

        return kind.symbolName
    }

    var image: NSImage? {
        if let imageData {
            return NSImage(data: imageData)
        }

        guard isImageFileAttachment,
              attachments.count == 1,
              let attachment = attachments.first,
              let inlineData = attachment.inlineData else {
            return nil
        }

        return NSImage(data: inlineData)
    }

    var imageSize: NSSize? {
        if let imageWidth, let imageHeight {
            return NSSize(width: imageWidth, height: imageHeight)
        }
        return image?.size
    }

    var plainTextRepresentation: String {
        switch kind {
        case .text, .code:
            return text ?? ""
        case .link, .browserTab:
            return urlString ?? text ?? ""
        case .image:
            return previewText
        case .file, .folder:
            return attachments.map(\.originalPath).joined(separator: "\n")
        }
    }

    var isImageFileAttachment: Bool {
        kind == .file && !attachments.isEmpty && attachments.allSatisfy(\.isImageLike)
    }

    private var attachmentSummary: String {
        let label = kind == .folder ? "folder" : "file"
        if attachments.count == 1 {
            if let first = attachments.first {
                return [first.name, first.byteCountLabel].compactMap { $0 }.joined(separator: " • ")
            }
            return "1 \(label)"
        }
        return "\(attachments.count) \(label)s"
    }

    private var hostDisplay: String? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    private var urlDisplay: String? {
        guard let urlString, let url = URL(string: urlString) else { return urlString }
        let host = url.host(percentEncoded: false) ?? url.absoluteString
        let path = url.path.isEmpty ? "" : url.path
        return path.isEmpty ? host : "\(host)\(path)"
    }

    private func normalizedText(limit: Int) -> String {
        let normalized = (text ?? "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count <= limit {
            return normalized
        }

        let index = normalized.index(normalized.startIndex, offsetBy: max(0, limit - 3))
        return "\(normalized[..<index])..."
    }
}
