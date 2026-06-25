import Foundation
import UniformTypeIdentifiers

enum SaveReceivedPayloadResult {
    case skipped
    case saved(String)
    case failed(String)
}

struct ReceivedItemDiskSettings {
    var baseDirectoryPath: String
    var saveItems: Bool
    var saveImages: Bool
    var saveText: Bool
    var saveFiles: Bool
}

enum ReceivedItemDiskStore {
    static var defaultBaseDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("AirCopy", isDirectory: true)
    }

    static func baseDirectoryURL(for path: String) -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath = trimmedPath.isEmpty ? defaultBaseDirectory.path : trimmedPath
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    static func save(
        payload: ClipboardPayload,
        date: Date,
        settings: ReceivedItemDiskSettings
    ) -> SaveReceivedPayloadResult {
        guard settings.saveItems else { return .skipped }
        let baseDirectory = baseDirectoryURL(for: settings.baseDirectoryPath)

        do {
            switch payload.kind {
            case .image:
                guard settings.saveImages, let imageData = payload.imageData else { return .skipped }
                let folder = try subdirectoryURL(named: "Images", in: baseDirectory)
                let stem = fileStem(from: payload.title, fallback: "Image-\(timestampString(from: date))")
                let destination = uniqueFileURL(in: folder, preferredStem: stem, pathExtension: "png")
                try imageData.write(to: destination, options: .atomic)
                return .saved("Saved to Images.")

            case .text, .code, .link, .browserTab:
                guard settings.saveText else { return .skipped }
                let contents = payload.plainTextRepresentation
                guard let data = contents.data(using: .utf8), !data.isEmpty else { return .skipped }
                let folder = try subdirectoryURL(named: "Text", in: baseDirectory)
                let stem = fileStem(from: payload.title, fallback: "Text-\(timestampString(from: date))")
                let destination = uniqueFileURL(
                    in: folder,
                    preferredStem: stem,
                    pathExtension: textFileExtension(for: payload)
                )
                try data.write(to: destination, options: .atomic)
                return .saved("Saved to Text.")

            case .file, .folder:
                guard settings.saveFiles else { return .skipped }
                guard let summary = try saveAttachmentsToDisk(payload.attachments, baseDirectory: baseDirectory) else {
                    return .skipped
                }
                return .saved(summary)
            }
        } catch {
            return .failed("Could not save a copy: \(error.localizedDescription)")
        }
    }

    private static func saveAttachmentsToDisk(
        _ attachments: [ClipboardAttachment],
        baseDirectory: URL
    ) throws -> String? {
        guard !attachments.isEmpty else { return nil }

        let folder = try subdirectoryURL(named: "Files", in: baseDirectory)
        var savedCount = 0
        var skippedCount = 0

        for attachment in attachments {
            if try saveAttachment(attachment, to: folder) {
                savedCount += 1
            } else {
                skippedCount += 1
            }
        }

        if savedCount == 0, skippedCount > 0 {
            return "Some file references could not be saved."
        }

        if skippedCount > 0 {
            return "Saved \(savedCount) file\(savedCount == 1 ? "" : "s"). Some references were skipped."
        }

        return savedCount == 1 ? "Saved to Files." : "Saved \(savedCount) files to Files."
    }

    private static func saveAttachment(_ attachment: ClipboardAttachment, to folder: URL) throws -> Bool {
        if let inlineData = attachment.inlineData, !attachment.isDirectory {
            let destination = uniqueFileURL(
                in: folder,
                preferredStem: attachmentFileStem(for: attachment),
                pathExtension: fileExtension(for: attachment)
            )
            try inlineData.write(to: destination, options: .atomic)
            return true
        }

        let sourceURL = URL(fileURLWithPath: attachment.originalPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }

        let destination = uniqueFileURL(
            in: folder,
            preferredStem: attachment.isDirectory
                ? attachmentDirectoryStem(for: attachment)
                : attachmentFileStem(for: attachment),
            pathExtension: attachment.isDirectory ? nil : fileExtension(for: attachment)
        )
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return true
    }

    private static func subdirectoryURL(named folderName: String, in baseDirectory: URL) throws -> URL {
        let directory = baseDirectory.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func uniqueFileURL(in directory: URL, preferredStem: String, pathExtension: String?) -> URL {
        let stem = preferredStem.isEmpty ? "AirCopy" : preferredStem
        let sanitizedExtension = (pathExtension ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var candidate = directory.appendingPathComponent(stem)
        if !sanitizedExtension.isEmpty {
            candidate.appendPathExtension(sanitizedExtension)
        }

        guard !FileManager.default.fileExists(atPath: candidate.path) else {
            var suffix = 2
            while true {
                var numbered = directory.appendingPathComponent("\(stem)-\(suffix)")
                if !sanitizedExtension.isEmpty {
                    numbered.appendPathExtension(sanitizedExtension)
                }

                if !FileManager.default.fileExists(atPath: numbered.path) {
                    return numbered
                }

                suffix += 1
            }
        }

        return candidate
    }

    private static func fileStem(from rawValue: String, fallback: String) -> String {
        let cleaned = rawValue
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let base = cleaned.isEmpty ? fallback : cleaned
        return String(base.prefix(60))
    }

    private static func fileExtension(for attachment: ClipboardAttachment) -> String? {
        if !attachment.fileExtension.isEmpty {
            return attachment.fileExtension
        }

        if let typeIdentifier = attachment.typeIdentifier,
           let contentType = UTType(typeIdentifier),
           let preferredExtension = contentType.preferredFilenameExtension {
            return preferredExtension
        }

        return nil
    }

    private static func attachmentFileStem(for attachment: ClipboardAttachment) -> String {
        let rawName = URL(fileURLWithPath: attachment.name).deletingPathExtension().lastPathComponent
        return fileStem(from: rawName, fallback: "File")
    }

    private static func attachmentDirectoryStem(for attachment: ClipboardAttachment) -> String {
        fileStem(from: attachment.name, fallback: "Folder")
    }

    private static func textFileExtension(for payload: ClipboardPayload) -> String {
        guard payload.kind == .code else { return "txt" }

        switch payload.languageHint?.lowercased() {
        case "swift":
            return "swift"
        case "javascript":
            return "js"
        case "html":
            return "html"
        case "css":
            return "css"
        case "sql":
            return "sql"
        case "json":
            return "json"
        case "bash":
            return "sh"
        default:
            return "txt"
        }
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
