import AppKit

// Renders the DMG window background (with the drag arrow) as a Retina TIFF.
// Coordinates below are AppKit bottom-left origin. The DMG window is 640×420pt;
// dmgbuild places the app icon centered at (160,190 top-left) and the
// Applications symlink at (480,190 top-left) — mirror those here.

// dmgbuild maps background PIXELS to Finder POINTS, so render the background at
// exactly the window's point size (640×420, 1x).
let W: CGFloat = 640, H: CGFloat = 420
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background
color(0xF6F7F9).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Title + subtitle (bottom-left origin: higher y = higher on screen)
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor, centerY: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: c, .paragraphStyle: p
    ]
    let h = size * 1.4
    (s as NSString).draw(in: NSRect(x: 0, y: centerY - h / 2, width: W, height: h), withAttributes: attrs)
}
text("Install AirCopy", size: 22, weight: .bold, color: color(0x15151A), centerY: H - 56)
text("Drag AirCopy onto the Applications folder", size: 13, weight: .regular,
     color: color(0x6B6B73), centerY: H - 88)

// Arrow between the two icon slots (icons centered at y = H-190 = 230).
let arrowY = H - 190
let path = NSBezierPath()
path.lineWidth = 7
path.lineCapStyle = .round
path.lineJoinStyle = .round
path.move(to: NSPoint(x: 250, y: arrowY))
path.line(to: NSPoint(x: 388, y: arrowY))
color(0x0A6CFF).setStroke()
path.stroke()
// Arrowhead
let head = NSBezierPath()
head.lineWidth = 7
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: 372, y: arrowY + 16))
head.line(to: NSPoint(x: 392, y: arrowY))
head.line(to: NSPoint(x: 372, y: arrowY - 16))
color(0x0A6CFF).setStroke()
head.stroke()

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
