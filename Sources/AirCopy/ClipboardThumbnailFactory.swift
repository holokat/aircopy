import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardThumbnailFactory {
    static func thumbnailImage(from imageData: Data, maxPixelSize: Int) -> NSImage? {
        guard let thumbnailData = thumbnailData(from: imageData, maxPixelSize: maxPixelSize) else {
            return nil
        }

        return NSImage(data: thumbnailData)
    }

    private static func thumbnailData(from imageData: Data, maxPixelSize: Int) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else {
            return nil
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, thumbnailImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
