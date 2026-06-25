import Foundation
import UniformTypeIdentifiers

extension ClipboardAttachment {
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
