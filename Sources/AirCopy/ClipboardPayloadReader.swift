import AppKit
import Foundation

enum ClipboardPayloadReader {
    static func readPayload(
        from pasteboard: NSPasteboard,
        maxInlineAttachmentBytes: Int64,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        if let imagePayload = imagePayload(
            from: pasteboard,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return imagePayload
        }

        if let attachmentPayload = attachmentPayload(
            from: pasteboard,
            maxInlineAttachmentBytes: maxInlineAttachmentBytes,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return attachmentPayload
        }

        if let urlPayload = urlPayload(
            from: pasteboard,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        ) {
            return urlPayload
        }

        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if looksLikeURL(trimmed) {
            return ClipboardPayload(
                urlString: trimmed,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        if let language = detectCodeLanguage(in: text) {
            return ClipboardPayload(
                code: text,
                languageHint: language,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        return ClipboardPayload(
            text: text,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func imagePayload(
        from pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        guard containsDirectImagePayload(in: pasteboard),
              let imageData = pngData(from: pasteboard),
              !imageData.isEmpty else {
            return nil
        }

        return ClipboardPayload(
            imageData: imageData,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func containsDirectImagePayload(in pasteboard: NSPasteboard) -> Bool {
        if let types = pasteboard.types,
           types.contains(where: { $0 == .png || $0 == .tiff }) {
            return true
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           !images.isEmpty {
            return true
        }

        return false
    }

    private static func attachmentPayload(
        from pasteboard: NSPasteboard,
        maxInlineAttachmentBytes: Int64,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return nil }
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return nil }

        let attachments = fileURLs.compactMap { fileURL -> ClipboardAttachment? in
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .nameKey,
                    .contentTypeKey
                ])

                let isDirectory = values.isDirectory ?? false
                let fileSize = values.fileSize.map(Int64.init)
                let inlineData: Data?

                if !isDirectory, let fileSize, fileSize <= maxInlineAttachmentBytes {
                    inlineData = try? Data(contentsOf: fileURL)
                } else {
                    inlineData = nil
                }

                return ClipboardAttachment(
                    name: values.name ?? fileURL.lastPathComponent,
                    originalPath: fileURL.path,
                    isDirectory: isDirectory,
                    byteCount: fileSize,
                    typeIdentifier: values.contentType?.identifier,
                    inlineData: inlineData
                )
            } catch {
                return ClipboardAttachment(
                    name: fileURL.lastPathComponent,
                    originalPath: fileURL.path,
                    isDirectory: false
                )
            }
        }

        guard !attachments.isEmpty else { return nil }
        return ClipboardPayload(
            attachments: attachments,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private static func urlPayload(
        from pasteboard: NSPasteboard,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> ClipboardPayload? {
        let urlNameType = NSPasteboard.PasteboardType("public.url-name")

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first(where: { !$0.isFileURL }) {
            let linkTitle = pasteboard.string(forType: urlNameType)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let browserTab = (linkTitle?.isEmpty == false) && linkTitle != url.absoluteString
            return ClipboardPayload(
                urlString: url.absoluteString,
                linkTitle: linkTitle,
                browserTab: browserTab,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }

        return nil
    }

    private static func looksLikeURL(_ text: String) -> Bool {
        guard let url = URL(string: text) else { return false }
        return url.scheme?.hasPrefix("http") == true && url.host(percentEncoded: false) != nil
    }

    private static func detectCodeLanguage(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineCount = trimmed.split(separator: "\n", omittingEmptySubsequences: false).count

        if let data = trimmed.data(using: .utf8),
           (trimmed.hasPrefix("{") || trimmed.hasPrefix("[")),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return "json"
        }

        guard lineCount > 1 || trimmed.contains("{") || trimmed.contains(";") else { return nil }

        let lowercased = trimmed.lowercased()

        if lowercased.contains("import swiftui") || lowercased.contains("func ") || lowercased.contains("struct ") {
            return "swift"
        }

        if lowercased.contains("const ") || lowercased.contains("function ") || lowercased.contains("=>") {
            return "javascript"
        }

        if lowercased.hasPrefix("#!/bin/") || lowercased.contains("echo ") || lowercased.contains("export ") {
            return "bash"
        }

        if lowercased.contains("<html") || lowercased.contains("<div") || lowercased.contains("</") {
            return "html"
        }

        if lowercased.contains("{") && lowercased.contains(":") && lowercased.contains(";") {
            return "css"
        }

        if lowercased.contains("select ") || lowercased.contains(" from ") {
            return "sql"
        }

        if lineCount > 1 && (trimmed.contains("{") || trimmed.contains("}") || trimmed.contains("let ") || trimmed.contains("=")) {
            return "code"
        }

        return nil
    }

    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiffData) {
            return pngData(from: image)
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage],
           let image = images.first {
            return pngData(from: image)
        }

        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
