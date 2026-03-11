import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardPayloadKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case text
    case code
    case link
    case browserTab
    case image
    case file
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text:
            return "Text"
        case .code:
            return "Code"
        case .link:
            return "Link"
        case .browserTab:
            return "Browser Tab"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .folder:
            return "Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .code:
            return "curlybraces"
        case .link:
            return "link"
        case .browserTab:
            return "safari"
        case .image:
            return "photo.on.rectangle.angled"
        case .file:
            return "doc"
        case .folder:
            return "folder"
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case link
    case file
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .image:
            return "Images"
        case .link:
            return "Links"
        case .file:
            return "Files"
        case .code:
            return "Code"
        }
    }

    func matches(_ kind: ClipboardPayloadKind) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return kind == .text
        case .image:
            return kind == .image
        case .link:
            return kind == .link || kind == .browserTab
        case .file:
            return kind == .file || kind == .folder
        case .code:
            return kind == .code
        }
    }
}

enum PeerTrustState: String, Codable, Hashable {
    case pending
    case trusted
    case blocked

    var title: String {
        switch self {
        case .pending:
            return "Approval Needed"
        case .trusted:
            return "Trusted"
        case .blocked:
            return "Blocked"
        }
    }
}

enum DeliveryState: String, Codable, Hashable {
    case pending
    case delivered
    case clipboardUpdated
    case failed
    case skipped

    var title: String {
        switch self {
        case .pending:
            return "Sending"
        case .delivered:
            return "Delivered"
        case .clipboardUpdated:
            return "Ready"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "clock"
        case .delivered:
            return "tray.and.arrow.down"
        case .clipboardUpdated:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .skipped:
            return "slash.circle"
        }
    }
}

enum ClipboardReceiptKind: String, Codable, Hashable {
    case delivered
    case clipboardUpdated
}

struct ClipboardAttachment: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let originalPath: String
    let isDirectory: Bool
    let byteCount: Int64?
    let typeIdentifier: String?
    let inlineData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        originalPath: String,
        isDirectory: Bool,
        byteCount: Int64? = nil,
        typeIdentifier: String? = nil,
        inlineData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.originalPath = originalPath
        self.isDirectory = isDirectory
        self.byteCount = byteCount
        self.typeIdentifier = typeIdentifier
        self.inlineData = inlineData
    }

    var fileExtension: String {
        URL(fileURLWithPath: originalPath).pathExtension.lowercased()
    }

    var byteCountLabel: String? {
        guard let byteCount else { return nil }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var isImageLike: Bool {
        if let typeIdentifier,
           let contentType = UTType(typeIdentifier),
           contentType.conforms(to: .image) {
            return true
        }

        if let typeIdentifier,
           typeIdentifier.lowercased() == "public.svg-image" {
            return true
        }

        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "heif",
            "tif", "tiff", "bmp", "avif", "jxl", "icns"
        ]

        return imageExtensions.contains(fileExtension)
    }
}

struct ClipboardPayload: Codable, Hashable {
    let kind: ClipboardPayloadKind
    let text: String?
    let imageData: Data?
    let imageWidth: Int?
    let imageHeight: Int?
    let urlString: String?
    let linkTitle: String?
    let attachments: [ClipboardAttachment]
    let languageHint: String?
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let createdAt: Date

    init(
        kind: ClipboardPayloadKind,
        text: String? = nil,
        imageData: Data? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        urlString: String? = nil,
        linkTitle: String? = nil,
        attachments: [ClipboardAttachment] = [],
        languageHint: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        createdAt: Date = Date()
    ) {
        self.kind = kind
        self.text = text
        self.imageData = imageData
        let resolvedImageDimensions: (width: Int?, height: Int?)
        if kind == .image, let imageData, imageWidth == nil || imageHeight == nil {
            resolvedImageDimensions = Self.imageDimensions(from: imageData)
        } else {
            resolvedImageDimensions = (imageWidth, imageHeight)
        }
        self.imageWidth = resolvedImageDimensions.width
        self.imageHeight = resolvedImageDimensions.height
        self.urlString = urlString
        self.linkTitle = linkTitle
        self.attachments = attachments
        self.languageHint = languageHint
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.createdAt = createdAt
    }

    init(text: String, sourceAppBundleID: String? = nil, sourceAppName: String? = nil) {
        self.init(kind: .text, text: text, sourceAppBundleID: sourceAppBundleID, sourceAppName: sourceAppName)
    }

    init(
        code: String,
        languageHint: String?,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            kind: .code,
            text: code,
            languageHint: languageHint,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    init(
        imageData: Data,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(kind: .image, imageData: imageData, sourceAppBundleID: sourceAppBundleID, sourceAppName: sourceAppName)
    }

    init(
        urlString: String,
        linkTitle: String? = nil,
        browserTab: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            kind: browserTab ? .browserTab : .link,
            text: browserTab ? (linkTitle ?? urlString) : urlString,
            urlString: urlString,
            linkTitle: linkTitle,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    init(
        attachments: [ClipboardAttachment],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        let containsNonDirectories = attachments.contains(where: { !$0.isDirectory })
        self.init(
            kind: containsNonDirectories ? .file : .folder,
            attachments: attachments,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    var fingerprint: String {
        let digest = SHA256.hash(data: fingerprintData)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

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

    var searchableText: String {
        [
            kind.title,
            title,
            previewText,
            detailText,
            text,
            linkTitle,
            urlString,
            sourceAppName,
            sourceAppBundleID,
            attachments.map(\.name).joined(separator: " ")
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: "\n")
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

    private var fingerprintData: Data {
        var parts = [
            kind.rawValue,
            text ?? "",
            urlString ?? "",
            linkTitle ?? "",
            languageHint ?? "",
            sourceAppBundleID ?? "",
            sourceAppName ?? ""
        ]

        parts.append(
            attachments.map {
                [$0.name, $0.originalPath, $0.isDirectory.description, $0.byteCount.map(String.init) ?? "", $0.typeIdentifier ?? ""]
                    .joined(separator: "|")
            }.joined(separator: "||")
        )

        let header = parts.joined(separator: "\u{1f}")
        var data = Data(header.utf8)

        if let imageData {
            data.append(imageData)
        }

        for attachment in attachments {
            if let inlineData = attachment.inlineData {
                data.append(inlineData)
            }
        }

        return data
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

    private static func imageDimensions(from data: Data) -> (width: Int?, height: Int?) {
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        return (width, height)
    }
}

struct DeviceReceipt: Identifiable, Codable, Hashable {
    let id: String
    let deviceID: String
    var deviceName: String
    var state: DeliveryState
    var date: Date

    init(deviceID: String, deviceName: String, state: DeliveryState, date: Date = Date()) {
        self.id = deviceID
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.state = state
        self.date = date
    }
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

struct AirCopyWireMessage: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case clipboard
        case receipt
    }

    let kind: Kind
    let clipboard: ClipboardMessage?
    let receipt: ClipboardReceipt?

    static func clipboard(_ message: ClipboardMessage) -> AirCopyWireMessage {
        AirCopyWireMessage(kind: .clipboard, clipboard: message, receipt: nil)
    }

    static func receipt(_ receipt: ClipboardReceipt) -> AirCopyWireMessage {
        AirCopyWireMessage(kind: .receipt, clipboard: nil, receipt: receipt)
    }
}

struct PeerInvitationContext: Codable, Hashable {
    let deviceID: String
    let deviceName: String
}

struct PeerDeviceState: Identifiable, Hashable {
    let id: String
    var displayName: String
    var trustState: PeerTrustState
    var isDiscovered: Bool
    var isConnected: Bool
    var isAutoSyncEnabled: Bool
    var lastSeenAt: Date?
    var lastSyncAt: Date?
    var lastReceiptState: DeliveryState?
    var lastReceiptText: String?
    var lastClipboardSummary: String?
    var encryptedTransport: Bool

    var deviceSymbolName: String {
        let normalizedName = displayName.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        if normalizedName.contains("macbook") || normalizedName.contains("laptop") || normalizedName.contains("notebook") {
            return "laptopcomputer"
        }

        return "desktopcomputer"
    }

    var statusSummary: String {
        if isConnected {
            return trustState == .trusted ? "Connected" : trustState.title
        }

        if isDiscovered {
            return trustState.title
        }

        return "Offline"
    }
}

struct AppExclusion: Identifiable, Codable, Hashable {
    let id: String
    let bundleID: String
    var appName: String

    init(bundleID: String, appName: String) {
        self.id = bundleID
        self.bundleID = bundleID
        self.appName = appName
    }
}

struct ClipboardHistoryItem: Identifiable, Hashable {
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
