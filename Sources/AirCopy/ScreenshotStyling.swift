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
    var importSystemScreenshots = false
    var watchedFolderPath: String? = nil
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

enum ScreenshotStyleRenderer {
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

    static func backgroundPreviewImage(for preset: ScreenshotBackgroundPreset, size: NSSize = NSSize(width: 92, height: 68)) -> NSImage? {
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        drawBackground(preset: preset, in: rect)
        image.unlockFocus()
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
            let framePath = NSBezierPath(roundedRect: canvasRect.insetBy(dx: 1, dy: 1), xRadius: outerRadius, yRadius: outerRadius)
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
            CGRect(x: rect.minX - rect.width * 0.08, y: rect.midY - rect.height * 0.18, width: rect.width * 0.62, height: rect.height * 0.72),
            CGRect(x: rect.maxX - rect.width * 0.44, y: rect.minY - rect.height * 0.04, width: rect.width * 0.56, height: rect.height * 0.66),
            CGRect(x: rect.midX - rect.width * 0.18, y: rect.maxY - rect.height * 0.42, width: rect.width * 0.48, height: rect.height * 0.52)
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
            gradient?.draw(fromCenter: NSPoint(x: glowRect.midX, y: glowRect.midY), radius: 0, toCenter: NSPoint(x: glowRect.midX, y: glowRect.midY), radius: max(glowRect.width, glowRect.height) * 0.58, options: [])
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

        let badgePath = NSBezierPath(roundedRect: watermarkRect, xRadius: watermarkRect.height / 2, yRadius: watermarkRect.height / 2)
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
            guard let text = observation.topCandidates(1).first?.string,
                  let emailRegex,
                  emailRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
                continue
            }

            let bounds = observation.boundingBox
            let redactionRect = CGRect(
                x: screenshotRect.minX + (bounds.minX * screenshotRect.width) - 6,
                y: screenshotRect.minY + (bounds.minY * screenshotRect.height) - 4,
                width: (bounds.width * screenshotRect.width) + 12,
                height: (bounds.height * screenshotRect.height) + 8
            )

            let path = NSBezierPath(roundedRect: redactionRect, xRadius: 8, yRadius: 8)
            NSColor(calibratedWhite: 0.08, alpha: 0.84).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private static func sampleScreenshotImage() -> NSImage {
        let size = NSSize(width: 1520, height: 960)
        let image = NSImage(size: size)

        image.lockFocus()
        let canvasRect = NSRect(origin: .zero, size: size)
        NSColor(calibratedRed: 0.95, green: 0.96, blue: 0.98, alpha: 1).setFill()
        canvasRect.fill()

        let windowRect = NSRect(x: 84, y: 90, width: 1352, height: 780)
        let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: 28, yRadius: 28)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 22
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.set()
        NSColor.white.setFill()
        windowPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 0.92, green: 0.94, blue: 0.98, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: windowRect.minX, y: windowRect.maxY - 68, width: windowRect.width, height: 68)).fill()

        let dots = [
            NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.27, alpha: 1),
            NSColor(calibratedRed: 0.23, green: 0.80, blue: 0.42, alpha: 1)
        ]

        for (index, color) in dots.enumerated() {
            color.setFill()
            let dotRect = NSRect(x: windowRect.minX + 26 + CGFloat(index * 20), y: windowRect.maxY - 44, width: 12, height: 12)
            NSBezierPath(ovalIn: dotRect).fill()
        }

        let sidebarRect = NSRect(x: windowRect.minX, y: windowRect.minY, width: 244, height: windowRect.height - 68)
        NSColor(calibratedRed: 0.14, green: 0.17, blue: 0.24, alpha: 1).setFill()
        NSBezierPath(roundedRect: sidebarRect, xRadius: 24, yRadius: 24).fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.21, alpha: 1)
        ]
        NSAttributedString(string: "Beautiful screenshots, instantly.", attributes: titleAttributes)
            .draw(at: CGPoint(x: windowRect.minX + 300, y: windowRect.maxY - 150))

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .medium),
            .foregroundColor: NSColor(calibratedRed: 0.40, green: 0.45, blue: 0.54, alpha: 1)
        ]
        NSAttributedString(string: "AirCopy can frame, soften, and clean up your clipboard screenshots before you share them.", attributes: bodyAttributes)
            .draw(in: NSRect(x: windowRect.minX + 300, y: windowRect.maxY - 250, width: 860, height: 120))

        let heroCardRect = NSRect(x: windowRect.minX + 300, y: windowRect.minY + 150, width: 470, height: 290)
        let heroCardPath = NSBezierPath(roundedRect: heroCardRect, xRadius: 28, yRadius: 28)
        NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.30, alpha: 1).setFill()
        heroCardPath.fill()

        let metricAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        NSAttributedString(string: "Clipboard sync", attributes: metricAttributes)
            .draw(at: CGPoint(x: heroCardRect.minX + 34, y: heroCardRect.maxY - 72))
        NSAttributedString(string: "81 Likes", attributes: metricAttributes)
            .draw(at: CGPoint(x: heroCardRect.minX + 34, y: heroCardRect.maxY - 136))
        NSAttributedString(string: "53 Comments", attributes: bodyAttributes)
            .draw(at: CGPoint(x: heroCardRect.minX + 34, y: heroCardRect.maxY - 196))
        NSAttributedString(string: "k@example.com", attributes: bodyAttributes)
            .draw(at: CGPoint(x: heroCardRect.minX + 34, y: heroCardRect.maxY - 252))

        let chartRect = NSRect(x: heroCardRect.maxX + 56, y: heroCardRect.minY + 16, width: 450, height: 258)
        let chartPath = NSBezierPath(roundedRect: chartRect, xRadius: 24, yRadius: 24)
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 1.00, alpha: 1).setFill()
        chartPath.fill()

        let linePath = NSBezierPath()
        linePath.move(to: CGPoint(x: chartRect.minX + 28, y: chartRect.minY + 62))
        linePath.curve(
            to: CGPoint(x: chartRect.maxX - 30, y: chartRect.maxY - 56),
            controlPoint1: CGPoint(x: chartRect.minX + 120, y: chartRect.minY + 24),
            controlPoint2: CGPoint(x: chartRect.maxX - 140, y: chartRect.maxY - 10)
        )
        linePath.lineWidth = 8
        NSColor(calibratedRed: 0.43, green: 0.46, blue: 0.95, alpha: 1).setStroke()
        linePath.stroke()

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
