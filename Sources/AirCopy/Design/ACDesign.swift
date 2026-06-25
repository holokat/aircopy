import SwiftUI

// MARK: - Design tokens for the AirCopy redesign.
//
// The new design is a fixed light-mode surface. Colors are hard-coded hex
// values straight from the design handoff so the window renders identically
// regardless of the system appearance ("pixel-perfect, do not deviate").

enum ACColor {
    // Accent
    static let accent = Color(hex: 0x0A6CFF)
    static let accentSoft = Color(hex: 0x0A6CFF, alpha: 0.08)
    static let accentSoft12 = Color(hex: 0x0A6CFF, alpha: 0.12)
    static let accentSoft16 = Color(hex: 0x0A6CFF, alpha: 0.16)

    // Ink / text
    static let ink = Color(hex: 0x15151A)
    static let ink2 = Color(hex: 0x1F1F26)
    static let textSecondary = Color(hex: 0x5C5C66)
    static let textSecondary2 = Color(hex: 0x6B6B73)
    static let textTertiary = Color(hex: 0x9AA0A8)
    static let textTertiary2 = Color(hex: 0xB4B4BC)
    static let textMuted = Color(hex: 0x3C3C45)

    // Surfaces
    static let backdrop = Color(hex: 0xE6E6E9)
    static let surface = Color.white
    static let inset = Color(hex: 0xFAFAFA)
    static let sidebar = Color(hex: 0xF7F7F9)
    static let grid = Color(hex: 0xFCFCFD)
    static let titlebar = Color(hex: 0xFAFAFA)

    // Control grays
    static let controlSearch = Color(hex: 0xF5F5F7)
    static let controlTrack = Color(hex: 0xF1F1F3)
    static let controlPill = Color(hex: 0xF4F4F6)
    static let controlHover = Color(hex: 0xECECEF)

    // Borders
    static let border06 = Color(hex: 0x14141E, alpha: 0.06)
    static let border08 = Color(hex: 0x14141E, alpha: 0.08)
    static let border09 = Color(hex: 0x14141E, alpha: 0.09)
    static let border10 = Color(hex: 0x14141E, alpha: 0.10)
    static let border12 = Color(hex: 0x14141E, alpha: 0.12)
    static let border16 = Color(hex: 0x14141E, alpha: 0.16)
    static let border18 = Color(hex: 0x14141E, alpha: 0.18)

    // Status
    static let success = Color(hex: 0x22C55E)
    static let successText = Color(hex: 0x15803D)
    static let danger = Color(hex: 0xDC2626)
    static let dangerSoft = Color(hex: 0xDC2626, alpha: 0.06)
    static let dangerBorder = Color(hex: 0xDC2626, alpha: 0.20)

    // Dark tiles / logo
    static let darkTile = Color(hex: 0x15151A)
    static let darkBlock = Color(hex: 0x141418)

    // Toggle off track
    static let toggleOff = Color(hex: 0xD1D1D6)

    static func favicon(for domain: String) -> Color {
        switch domain.lowercased() {
        case "linear.app": return Color(hex: 0x5E6AD2)
        case "figma.com": return Color(hex: 0xA259FF)
        case "github.com": return Color(hex: 0x1F2328)
        default: return Color(hex: 0x5C5C66)
        }
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

// Shared rounded-rect hairline border helper.
extension View {
    func acBorder(_ color: Color = ACColor.border09, radius: CGFloat, width: CGFloat = 1) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }
}
