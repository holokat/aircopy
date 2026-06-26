import AppKit
import SwiftUI

// MARK: - Design tokens for the AirCopy redesign.
//
// Every token is appearance-aware: it carries a light and a dark value and
// resolves automatically against the window's effective color scheme (driven
// by `.preferredColorScheme` from the user's Appearance preference). The light
// values are the original pixel-perfect handoff colors, untouched; the dark
// values are a hand-tuned counterpart for the dark-mode design.

enum ACColor {
    // Accent
    static let accent = dyn(light: 0x0A6CFF, dark: 0x3B82FF)
    static let accentSoft = dyn(light: 0x0A6CFF, lightAlpha: 0.08, dark: 0x3B82FF, darkAlpha: 0.16)
    static let accentSoft12 = dyn(light: 0x0A6CFF, lightAlpha: 0.12, dark: 0x3B82FF, darkAlpha: 0.22)
    static let accentSoft16 = dyn(light: 0x0A6CFF, lightAlpha: 0.16, dark: 0x3B82FF, darkAlpha: 0.26)

    // Ink / text
    static let ink = dyn(light: 0x15151A, dark: 0xF3F4F7)
    static let ink2 = dyn(light: 0x1F1F26, dark: 0xE4E6EA)
    static let textSecondary = dyn(light: 0x5C5C66, dark: 0x9EA2AA)
    static let textSecondary2 = dyn(light: 0x6B6B73, dark: 0x8A8E96)
    static let textTertiary = dyn(light: 0x9AA0A8, dark: 0x6B6F78)
    static let textTertiary2 = dyn(light: 0xB4B4BC, dark: 0x55585F)
    static let textMuted = dyn(light: 0x3C3C45, dark: 0xB6B9C0)

    // Surfaces
    static let backdrop = dyn(light: 0xE6E6E9, dark: 0x070709)
    static let surface = dyn(light: 0xFFFFFF, dark: 0x16161A)
    static let inset = dyn(light: 0xFAFAFA, dark: 0x101014)
    static let sidebar = dyn(light: 0xF7F7F9, dark: 0x0E0E12)
    static let grid = dyn(light: 0xFCFCFD, dark: 0x0A0A0D)
    static let titlebar = dyn(light: 0xFAFAFA, dark: 0x0D0D11)

    // Control grays
    static let controlSearch = dyn(light: 0xF5F5F7, dark: 0x1B1B20)
    static let controlTrack = dyn(light: 0xF1F1F3, dark: 0x202026)
    static let controlPill = dyn(light: 0xF4F4F6, dark: 0x1C1C22)
    static let controlHover = dyn(light: 0xECECEF, dark: 0x26262D)

    // Borders — black hairlines on light, white hairlines on dark.
    static let border06 = dyn(light: 0x14141E, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.06)
    static let border08 = dyn(light: 0x14141E, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.08)
    static let border09 = dyn(light: 0x14141E, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.09)
    static let border10 = dyn(light: 0x14141E, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.10)
    static let border12 = dyn(light: 0x14141E, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let border16 = dyn(light: 0x14141E, lightAlpha: 0.16, dark: 0xFFFFFF, darkAlpha: 0.14)
    static let border18 = dyn(light: 0x14141E, lightAlpha: 0.18, dark: 0xFFFFFF, darkAlpha: 0.16)

    // Status
    static let success = dyn(light: 0x22C55E, dark: 0x32D366)
    static let successText = dyn(light: 0x15803D, dark: 0x4ADE80)
    static let danger = dyn(light: 0xDC2626, dark: 0xF06A6A)
    static let dangerSoft = dyn(light: 0xDC2626, lightAlpha: 0.06, dark: 0xF06A6A, darkAlpha: 0.14)
    static let dangerBorder = dyn(light: 0xDC2626, lightAlpha: 0.20, dark: 0xF06A6A, darkAlpha: 0.32)

    // Dark tiles / logo — kept dark in both schemes, lifted slightly on dark
    // so the rounded tile stays visible against the near-black titlebar.
    static let darkTile = dyn(light: 0x15151A, dark: 0x26262E)
    static let darkBlock = dyn(light: 0x141418, dark: 0x222229)

    // Toggle off track
    static let toggleOff = dyn(light: 0xD1D1D6, dark: 0x3A3A42)

    static func favicon(for domain: String) -> Color {
        switch domain.lowercased() {
        case "linear.app": return Color(hex: 0x5E6AD2)
        case "figma.com": return Color(hex: 0xA259FF)
        case "github.com": return dyn(light: 0x1F2328, dark: 0x2C313A)
        default: return dyn(light: 0x5C5C66, dark: 0x6B6F78)
        }
    }

    /// Builds a color that resolves to its light or dark value based on the
    /// surrounding view's effective appearance.
    static func dyn(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor(acHex: dark, alpha: CGFloat(darkAlpha))
                : NSColor(acHex: light, alpha: CGFloat(lightAlpha))
        })
    }
}

enum ACFont {
    // The handoff specifies Geist / Geist Mono; macOS substitutes SF Pro / SF Mono.
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension NSColor {
    convenience init(acHex hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

// Shared rounded-rect hairline border helper.
extension View {
    func acBorder(_ color: Color = ACColor.border09, radius: CGFloat, width: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }
}
