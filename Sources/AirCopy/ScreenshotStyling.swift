import AppKit
import Foundation
import Vision

enum ScreenshotBackgroundPreset: String, CaseIterable, Codable, Identifiable {
    case aurora
    case rose
    case sunrise
    case lagoon
    case twilight
    case desktop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aurora:
            return "Aurora"
        case .rose:
            return "Rose"
        case .sunrise:
            return "Sunrise"
        case .lagoon:
            return "Lagoon"
        case .twilight:
            return "Twilight"
        case .desktop:
            return "Desktop"
        }
    }

    var previewColors: [NSColor] {
        switch self {
        case .aurora:
            return [
                NSColor(calibratedRed: 0.31, green: 0.84, blue: 0.97, alpha: 1),
                NSColor(calibratedRed: 0.67, green: 0.59, blue: 0.97, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.39, blue: 0.76, alpha: 1)
            ]
        case .rose:
            return [
                NSColor(calibratedRed: 0.88, green: 0.40, blue: 0.61, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.48, alpha: 1),
                NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.61, alpha: 1)
            ]
        case .sunrise:
            return [
                NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.45, alpha: 1),
                NSColor(calibratedRed: 0.97, green: 0.81, blue: 0.58, alpha: 1),
                NSColor(calibratedRed: 0.99, green: 0.89, blue: 0.78, alpha: 1)
            ]
        case .lagoon:
            return [
                NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.84, alpha: 1),
                NSColor(calibratedRed: 0.27, green: 0.58, blue: 0.94, alpha: 1),
                NSColor(calibratedRed: 0.58, green: 0.48, blue: 0.96, alpha: 1)
            ]
        case .twilight:
            return [
                NSColor(calibratedRed: 0.29, green: 0.23, blue: 0.60, alpha: 1),
                NSColor(calibratedRed: 0.64, green: 0.28, blue: 0.70, alpha: 1),
                NSColor(calibratedRed: 0.95, green: 0.45, blue: 0.65, alpha: 1)
            ]
        case .desktop:
            return [
                NSColor(calibratedWhite: 0.90, alpha: 1),
                NSColor(calibratedWhite: 0.75, alpha: 1),
                NSColor(calibratedWhite: 0.60, alpha: 1)
            ]
        }
    }
}

enum ScreenshotAspectRatioPreset: String, CaseIterable, Codable, Identifiable {
    case automatic
    case square
    case fourThree
    case threeTwo
    case sixteenNine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Auto"
        case .square:
            return "1:1"
        case .fourThree:
            return "4:3"
        case .threeTwo:
            return "3:2"
        case .sixteenNine:
            return "16:9"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .automatic:
            return nil
        case .square:
            return 1
        case .fourThree:
            return 4.0 / 3.0
        case .threeTwo:
            return 3.0 / 2.0
        case .sixteenNine:
            return 16.0 / 9.0
        }
    }
}

enum ScreenshotOutputSizePreset: String, CaseIterable, Codable, Identifiable {
    case automatic
    case share
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return "Auto"
        case .share:
            return "Share"
        case .large:
            return "Large"
        }
    }

    var maxDimension: CGFloat {
        switch self {
        case .automatic:
            return 2200
        case .share:
            return 1600
        case .large:
            return 3000
        }
    }
}

struct ScreenshotStyleSettings: Codable, Hashable {
    var isEnabled = false
    var backgroundPreset: ScreenshotBackgroundPreset = .aurora
    var aspectRatioPreset: ScreenshotAspectRatioPreset = .automatic
    var outputSizePreset: ScreenshotOutputSizePreset = .automatic
    var insetFraction = 0.12
    var cornerRadius = 28.0
    var shadowStrength = 0.58
    var redactEmailAddresses = false
    var showWatermark = false
    var watermarkText = "AirCopy"
}

@MainActor
enum ScreenshotStyleRenderer {
    private static var backgroundPreviewCache: [String: NSImage] = [:]

    static func styledImageData(
        from imageData: Data,
        settings: ScreenshotStyleSettings,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> Data {
        guard settings.isEnabled,
              let image = NSImage(data: imageData),
              shouldStyleClipboardImage(image, sourceAppBundleID: sourceAppBundleID, sourceAppName: sourceAppName),
              let rendered = renderImage(sourceImage: image, settings: settings),
              let pngData = pngData(from: rendered) else {
            return imageData
        }

        return pngData
    }

    static func previewImage(using settings: ScreenshotStyleSettings) -> NSImage? {
        renderImage(sourceImage: sampleScreenshotImage(), settings: settings, force: true)
    }

    static func backgroundPreviewImage(
        for preset: ScreenshotBackgroundPreset,
        size: NSSize = NSSize(width: 92, height: 68)
    ) -> NSImage? {
        let cacheKey = "\(preset.rawValue)-\(Int(size.width))x\(Int(size.height))"
        if let cached = backgroundPreviewCache[cacheKey] {
            return cached
        }

        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        drawBackground(preset: preset, in: rect)
        image.unlockFocus()
        backgroundPreviewCache[cacheKey] = image
        return image
    }

    private static func shouldStyleClipboardImage(
        _ image: NSImage,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) -> Bool {
        let lowercasedBundleID = sourceAppBundleID?.lowercased() ?? ""
        let lowercasedName = sourceAppName?.lowercased() ?? ""

        if lowercasedBundleID.contains("screencaptureui")
            || lowercasedBundleID.contains("screenshot")
            || lowercasedBundleID.contains("preview") {
            return true
        }

        if lowercasedName.contains("screenshot") || lowercasedName.contains("screen capture") {
            return true
        }

        let size = image.size
        let minDimension = min(size.width, size.height)
        let maxDimension = max(size.width, size.height)
        guard minDimension >= 300, maxDimension >= 700 else { return false }

        let ratio = max(size.width / max(size.height, 1), size.height / max(size.width, 1))
        return ratio <= 2.5
    }

    private static func renderImage(
        sourceImage: NSImage,
        settings: ScreenshotStyleSettings,
        force: Bool = false
    ) -> NSImage? {
        guard let cgImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let clampedInset = max(0.06, min(settings.insetFraction, 0.24))
        let clampedCornerRadius = max(8, min(settings.cornerRadius, 44))
        let clampedShadow = max(0, min(settings.shadowStrength, 1))

        let unscaledMargin = max(min(sourceSize.width, sourceSize.height) * clampedInset, 52)
        var canvasSize = CGSize(
            width: sourceSize.width + (unscaledMargin * 2),
            height: sourceSize.height + (unscaledMargin * 2)
        )

        if let targetRatio = settings.aspectRatioPreset.ratio {
            canvasSize = expandedSize(containing: canvasSize, targetAspectRatio: targetRatio)
        }

        let outputScale = min(1, settings.outputSizePreset.maxDimension / max(canvasSize.width, canvasSize.height))
        let scaledCanvasSize = CGSize(width: floor(canvasSize.width * outputScale), height: floor(canvasSize.height * outputScale))
        let scaledMargin = floor(unscaledMargin * outputScale)
        let canvasRect = CGRect(origin: .zero, size: scaledCanvasSize)
        let availableRect = canvasRect.insetBy(dx: scaledMargin, dy: scaledMargin)
        let screenshotRect = aspectFitRect(for: sourceSize, in: availableRect)
        let outerRadius = min(32, min(scaledCanvasSize.width, scaledCanvasSize.height) * 0.09)
        let renderedImage = NSImage(size: NSSize(width: scaledCanvasSize.width, height: scaledCanvasSize.height))

        renderedImage.lockFocus()
        drawBackground(
            preset: settings.backgroundPreset,
            in: NSRect(origin: .zero, size: renderedImage.size)
        )

        let screenshotPath = NSBezierPath(
            roundedRect: screenshotRect,
            xRadius: clampedCornerRadius * outputScale,
            yRadius: clampedCornerRadius * outputScale
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18 + (clampedShadow * 0.22))
        shadow.shadowBlurRadius = 18 + (clampedShadow * 28)
        shadow.shadowOffset = NSSize(width: 0, height: -(10 + (clampedShadow * 10)))
        shadow.set()
        screenshotPath.addClip()
        sourceImage.draw(in: screenshotRect)

        if settings.redactEmailAddresses {
            drawEmailRedactions(in: screenshotRect, sourceImage: cgImage)
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.12).setStroke()
        screenshotPath.lineWidth = max(1, outputScale * 1.5)
        screenshotPath.stroke()

        if settings.showWatermark {
            drawWatermark(
                text: settings.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "AirCopy"
                    : settings.watermarkText,
                in: canvasRect,
                outerRadius: outerRadius
            )
        }

        if force {
            let framePath = NSBezierPath(
                roundedRect: canvasRect.insetBy(dx: 1, dy: 1),
                xRadius: outerRadius,
                yRadius: outerRadius
            )
            NSColor.white.withAlphaComponent(0.06).setStroke()
            framePath.lineWidth = 2
            framePath.stroke()
        }

        renderedImage.unlockFocus()
        return renderedImage
    }

    private static func drawBackground(preset: ScreenshotBackgroundPreset, in rect: NSRect) {
        if preset == .desktop, drawDesktopWallpaper(in: rect) {
            drawAmbientHighlights(colors: preset.previewColors, in: rect)
            return
        }

        let gradient = NSGradient(colors: preset.previewColors) ?? NSGradient(
            starting: preset.previewColors.first ?? .black,
            ending: preset.previewColors.last ?? .white
        )
        gradient?.draw(in: rect, angle: preset == .sunrise ? 28 : 142)
        drawAmbientHighlights(colors: preset.previewColors, in: rect)
    }

    private static func drawDesktopWallpaper(in rect: NSRect) -> Bool {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let wallpaper = NSImage(contentsOf: url) else {
            return false
        }

        wallpaper.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        return true
    }

    private static func drawAmbientHighlights(colors: [NSColor], in rect: NSRect) {
        let glowRects = [
            CGRect(
                x: rect.minX - rect.width * 0.08,
                y: rect.midY - rect.height * 0.18,
                width: rect.width * 0.62,
                height: rect.height * 0.72
            ),
            CGRect(
                x: rect.maxX - rect.width * 0.44,
                y: rect.minY - rect.height * 0.04,
                width: rect.width * 0.56,
                height: rect.height * 0.66
            ),
            CGRect(
                x: rect.midX - rect.width * 0.18,
                y: rect.maxY - rect.height * 0.42,
                width: rect.width * 0.48,
                height: rect.height * 0.52
            )
        ]

        let glowColors = [
            colors.first?.withAlphaComponent(0.28) ?? NSColor.white.withAlphaComponent(0.22),
            colors.last?.withAlphaComponent(0.30) ?? NSColor.white.withAlphaComponent(0.18),
            NSColor.white.withAlphaComponent(0.14)
        ]

        for (index, glowRect) in glowRects.enumerated() {
            let color = glowColors[min(index, glowColors.count - 1)]
            let gradient = NSGradient(
                starting: color,
                ending: color.withAlphaComponent(0.01)
            )

            let path = NSBezierPath(ovalIn: glowRect)
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            gradient?.draw(
                fromCenter: NSPoint(x: glowRect.midX, y: glowRect.midY),
                radius: 0,
                toCenter: NSPoint(x: glowRect.midX, y: glowRect.midY),
                radius: max(glowRect.width, glowRect.height) * 0.58,
                options: []
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static func drawWatermark(text: String, in canvasRect: CGRect, outerRadius: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let padding = CGSize(width: 12, height: 8)
        let watermarkRect = CGRect(
            x: canvasRect.maxX - textSize.width - (padding.width * 2) - max(18, outerRadius * 0.55),
            y: canvasRect.minY + max(18, outerRadius * 0.55),
            width: textSize.width + (padding.width * 2),
            height: textSize.height + (padding.height * 2)
        )

        let badgePath = NSBezierPath(
            roundedRect: watermarkRect,
            xRadius: watermarkRect.height / 2,
            yRadius: watermarkRect.height / 2
        )
        NSColor.black.withAlphaComponent(0.28).setFill()
        badgePath.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        let textOrigin = CGPoint(
            x: watermarkRect.midX - (textSize.width / 2),
            y: watermarkRect.midY - (textSize.height / 2)
        )
        attributedString.draw(at: textOrigin)
    }

    private static func drawEmailRedactions(in screenshotRect: CGRect, sourceImage: CGImage) {
        let emailRegex = try? NSRegularExpression(
            pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        )
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: sourceImage, options: [:])
        try? handler.perform([request])

        guard let observations = request.results else { return }

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first,
                  let emailRegex else {
                continue
            }

            let text = candidate.string
            let matches = emailRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            for match in matches {
                guard let range = Range(match.range, in: text),
                      let matchBounds = try? candidate.boundingBox(for: range)?.boundingBox else {
                    continue
                }

                let paddingX = max(4, screenshotRect.width * 0.004)
                let paddingY = max(3, screenshotRect.height * 0.004)
                let redactionRect = CGRect(
                    x: screenshotRect.minX + (matchBounds.minX * screenshotRect.width) - paddingX,
                    y: screenshotRect.minY + (matchBounds.minY * screenshotRect.height) - paddingY,
                    width: (matchBounds.width * screenshotRect.width) + (paddingX * 2),
                    height: (matchBounds.height * screenshotRect.height) + (paddingY * 2)
                ).integral

                guard redactionRect.width > 4, redactionRect.height > 4 else { continue }
                drawPixelatedRedaction(in: redactionRect)
            }
        }
    }

    private static func drawPixelatedRedaction(in rect: CGRect) {
        let clippingPath = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        clippingPath.addClip()

        NSColor(calibratedWhite: 0.08, alpha: 0.98).setFill()
        rect.fill()

        let baseTileSize = max(6, min(14, rect.height / 3.2))
        let tileSize = floor(baseTileSize)
        let palette: [NSColor] = [
            NSColor(calibratedWhite: 0.20, alpha: 1),
            NSColor(calibratedWhite: 0.28, alpha: 1),
            NSColor(calibratedWhite: 0.36, alpha: 1),
            NSColor(calibratedWhite: 0.46, alpha: 1)
        ]

        var rowIndex = 0
        var y = rect.minY
        while y < rect.maxY {
            var columnIndex = 0
            var x = rect.minX
            while x < rect.maxX {
                let tileRect = CGRect(
                    x: x,
                    y: y,
                    width: min(tileSize, rect.maxX - x),
                    height: min(tileSize, rect.maxY - y)
                )

                let paletteIndex = abs((rowIndex * 3) + (columnIndex * 5)) % palette.count
                palette[paletteIndex].setFill()
                tileRect.fill()

                x += tileSize
                columnIndex += 1
            }

            y += tileSize
            rowIndex += 1
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        clippingPath.lineWidth = 1
        clippingPath.stroke()
    }

    private static func sampleScreenshotImage() -> NSImage {
        let size = NSSize(width: 1520, height: 960)
        let image = NSImage(size: size)

        image.lockFocus()
        let canvasRect = NSRect(origin: .zero, size: size)
        NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.00, alpha: 1).setFill()
        canvasRect.fill()

        let postRect = NSRect(x: 196, y: 136, width: 1128, height: 676)
        let postPath = NSBezierPath(roundedRect: postRect, xRadius: 32, yRadius: 32)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        NSColor.white.setFill()
        postPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let avatarRect = NSRect(x: postRect.minX + 40, y: postRect.maxY - 112, width: 66, height: 66)
        let avatarGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.48, green: 0.58, blue: 0.97, alpha: 1),
            NSColor(calibratedRed: 0.72, green: 0.42, blue: 0.92, alpha: 1)
        ])
        avatarGradient?.draw(in: avatarRect, relativeCenterPosition: .zero)
        NSColor.white.withAlphaComponent(0.16).setStroke()
        NSBezierPath(ovalIn: avatarRect).stroke()

        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.20, alpha: 1)
        ]
        NSAttributedString(string: "Ava Chen", attributes: nameAttributes)
            .draw(at: CGPoint(x: avatarRect.maxX + 20, y: avatarRect.maxY - 10))

        let handleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.44, green: 0.49, blue: 0.58, alpha: 1)
        ]
        NSAttributedString(string: "@avachenshares", attributes: handleAttributes)
            .draw(at: CGPoint(x: avatarRect.maxX + 20, y: avatarRect.minY + 10))

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.22, alpha: 1)
        ]
        NSAttributedString(
            string: "AirCopy makes Mac screenshots feel share-ready the second you capture them.",
            attributes: bodyAttributes
        )
        .draw(in: NSRect(x: postRect.minX + 40, y: postRect.maxY - 232, width: 1000, height: 120))

        let mediaRect = NSRect(x: postRect.minX + 40, y: postRect.minY + 118, width: postRect.width - 80, height: 320)
        let mediaPath = NSBezierPath(roundedRect: mediaRect, xRadius: 26, yRadius: 26)
        NSColor(calibratedRed: 0.94, green: 0.96, blue: 1.00, alpha: 1).setFill()
        mediaPath.fill()

        let appCardRect = NSRect(x: mediaRect.minX + 40, y: mediaRect.minY + 52, width: 422, height: 216)
        let appCardPath = NSBezierPath(roundedRect: appCardRect, xRadius: 24, yRadius: 24)
        let appCardGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 0.26, green: 0.34, blue: 0.52, alpha: 1)
        ])
        appCardGradient?.draw(in: appCardRect, angle: 128)
        NSColor.white.withAlphaComponent(0.12).setStroke()
        appCardPath.stroke()

        let cardTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 23, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        NSAttributedString(string: "AirCopy for Mac", attributes: cardTitleAttributes)
            .draw(at: CGPoint(x: appCardRect.minX + 24, y: appCardRect.maxY - 60))

        let cardBodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.86)
        ]
        NSAttributedString(
            string: "Screenshot. Sync. Paste on the other Mac.",
            attributes: cardBodyAttributes
        )
        .draw(in: NSRect(x: appCardRect.minX + 24, y: appCardRect.maxY - 122, width: 360, height: 52))

        let badgeRect = NSRect(x: appCardRect.minX + 24, y: appCardRect.minY + 26, width: 144, height: 38)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 19, yRadius: 19)
        NSColor.white.withAlphaComponent(0.14).setFill()
        badgePath.fill()
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        NSAttributedString(string: "Styled capture", attributes: badgeAttributes)
            .draw(at: CGPoint(x: badgeRect.minX + 18, y: badgeRect.minY + 10))

        let statCardRect = NSRect(x: mediaRect.maxX - 296, y: mediaRect.minY + 52, width: 240, height: 216)
        let statCardPath = NSBezierPath(roundedRect: statCardRect, xRadius: 24, yRadius: 24)
        NSColor.white.withAlphaComponent(0.78).setFill()
        statCardPath.fill()

        let statTitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.19, green: 0.24, blue: 0.35, alpha: 1)
        ]
        let statValueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 38, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.39, blue: 0.83, alpha: 1)
        ]
        NSAttributedString(string: "Shares", attributes: statTitleAttributes)
            .draw(at: CGPoint(x: statCardRect.minX + 24, y: statCardRect.maxY - 54))
        NSAttributedString(string: "2.4k", attributes: statValueAttributes)
            .draw(at: CGPoint(x: statCardRect.minX + 24, y: statCardRect.maxY - 118))
        NSAttributedString(string: "faster than moving files around", attributes: handleAttributes)
            .draw(in: NSRect(x: statCardRect.minX + 24, y: statCardRect.minY + 34, width: 180, height: 42))

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.50, alpha: 1)
        ]
        NSAttributedString(string: "Drag less. Share faster. Keep screenshots in flow.", attributes: footerAttributes)
            .draw(at: CGPoint(x: postRect.minX + 42, y: postRect.minY + 48))

        image.unlockFocus()
        return image
    }

    private static func aspectFitRect(for size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }

        let scale = min(rect.width / size.width, rect.height / size.height)
        let fittedSize = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - (fittedSize.width / 2),
            y: rect.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private static func expandedSize(containing size: CGSize, targetAspectRatio: CGFloat) -> CGSize {
        let currentAspectRatio = size.width / max(size.height, 1)
        if abs(currentAspectRatio - targetAspectRatio) < 0.001 {
            return size
        }

        if currentAspectRatio < targetAspectRatio {
            return CGSize(width: size.height * targetAspectRatio, height: size.height)
        }

        return CGSize(width: size.width, height: size.width / targetAspectRatio)
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
