import CryptoKit
import Foundation
import ImageIO

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
