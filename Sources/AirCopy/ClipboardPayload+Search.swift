import Foundation

extension ClipboardPayload {
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
}
