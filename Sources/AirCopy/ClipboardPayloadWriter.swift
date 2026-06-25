import AppKit
import Foundation

enum ClipboardPayloadWriter {
    @discardableResult
    static func writePayloadToGeneralPasteboard(_ payload: ClipboardPayload) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch payload.kind {
        case .text, .code:
            pasteboard.setString(payload.text ?? "", forType: .string)
        case .link, .browserTab:
            writeLinkPayload(payload, to: pasteboard)
        case .image:
            writeImagePayload(payload, to: pasteboard)
        case .file, .folder:
            writeAttachments(payload.attachments, to: pasteboard)
        }

        return pasteboard.changeCount
    }

    static func temporaryFileURL(for filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aircopy-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let safeName = filename.isEmpty ? UUID().uuidString : filename
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func writeLinkPayload(_ payload: ClipboardPayload, to pasteboard: NSPasteboard) {
        if let urlString = payload.urlString, let url = URL(string: urlString) {
            _ = pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(urlString, forType: .string)

            if let linkTitle = payload.linkTitle {
                pasteboard.setString(linkTitle, forType: NSPasteboard.PasteboardType("public.url-name"))
            }
        } else if let text = payload.text {
            pasteboard.setString(text, forType: .string)
        }
    }

    private static func writeImagePayload(_ payload: ClipboardPayload, to pasteboard: NSPasteboard) {
        if let data = payload.imageData, let image = NSImage(data: data) {
            if !pasteboard.writeObjects([image]) {
                pasteboard.setData(data, forType: .png)
            }
        }
    }

    private static func writeAttachments(_ attachments: [ClipboardAttachment], to pasteboard: NSPasteboard) {
        let urls = attachments.compactMap { attachment in
            if let inlineData = attachment.inlineData, !attachment.isDirectory {
                return try? temporaryFileURL(for: attachment.name, data: inlineData)
            }

            let url = URL(fileURLWithPath: attachment.originalPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        if !urls.isEmpty {
            _ = pasteboard.writeObjects(urls as [NSURL])
        }

        let pathListing = attachments.map(\.originalPath).joined(separator: "\n")
        if !pathListing.isEmpty {
            pasteboard.setString(pathListing, forType: .string)
        }
    }
}
