// Generates Aura's app icon and DMG background.
//   swift scripts/make_art.swift icon <out.png>          (1024×1024)
//   swift scripts/make_art.swift dmg  <out.png> <scale>  (660×420 points)
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: make_art.swift icon|dmg <out.png> [scale]")
    exit(1)
}

let violet = NSColor(calibratedRed: 0.49, green: 0.36, blue: 1.0, alpha: 1)
let cyan = NSColor(calibratedRed: 0.24, green: 0.77, blue: 1.0, alpha: 1)
let mint = NSColor(calibratedRed: 0.30, green: 1.0, blue: 0.71, alpha: 1)
let pink = NSColor(calibratedRed: 1.0, green: 0.38, blue: 0.66, alpha: 1)

func softBlob(_ ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
    ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// Notch silhouette (flared top corners, rounded bottom) with its top edge at `top` (y-up coordinates).
func notchPath(midX: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, flare: CGFloat, bottom: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let minX = midX - width / 2, maxX = midX + width / 2, minY = top - height
    p.move(to: CGPoint(x: minX, y: top))
    p.addQuadCurve(to: CGPoint(x: minX + flare, y: top - flare), control: CGPoint(x: minX + flare, y: top))
    p.addLine(to: CGPoint(x: minX + flare, y: minY + bottom))
    p.addQuadCurve(to: CGPoint(x: minX + flare + bottom, y: minY), control: CGPoint(x: minX + flare, y: minY))
    p.addLine(to: CGPoint(x: maxX - flare - bottom, y: minY))
    p.addQuadCurve(to: CGPoint(x: maxX - flare, y: minY + bottom), control: CGPoint(x: maxX - flare, y: minY))
    p.addLine(to: CGPoint(x: maxX - flare, y: top - flare))
    p.addQuadCurve(to: CGPoint(x: maxX, y: top), control: CGPoint(x: maxX - flare, y: top))
    p.closeSubpath()
    return p
}

func render(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> Data? {
    let px = CGSize(width: size.width * scale, height: size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px.width), pixelsHigh: Int(px.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let ctx = context.cgContext
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

func drawIcon(_ ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Night-sky background
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.12, green: 0.09, blue: 0.27, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.03, green: 0.07, blue: 0.14, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Aurora glow spilling from the notch
    softBlob(ctx, center: CGPoint(x: 370, y: 610), radius: 360, color: violet, alpha: 0.85)
    softBlob(ctx, center: CGPoint(x: 660, y: 560), radius: 340, color: cyan, alpha: 0.75)
    softBlob(ctx, center: CGPoint(x: 520, y: 380), radius: 300, color: mint, alpha: 0.55)
    softBlob(ctx, center: CGPoint(x: 280, y: 330), radius: 220, color: pink, alpha: 0.35)

    // Aurora ribbons
    for (i, color) in [violet, cyan, mint].enumerated() {
        let path = CGMutablePath()
        let y = 470 - CGFloat(i) * 70
        path.move(to: CGPoint(x: 60, y: y))
        path.addCurve(to: CGPoint(x: 964, y: y + 40), control1: CGPoint(x: 360, y: y + 190), control2: CGPoint(x: 660, y: y - 150))
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(46 - CGFloat(i) * 8)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(color.withAlphaComponent(0.22).cgColor)
        ctx.setShadow(offset: .zero, blur: 40, color: color.withAlphaComponent(0.9).cgColor)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // The notch, as an expanded "live activity"
    let notch = notchPath(midX: 512, top: 924, width: 560, height: 196, flare: 34, bottom: 74)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: NSColor.black.withAlphaComponent(0.7).cgColor)
    ctx.addPath(notch)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Album-art square on the left wing
    let art = CGRect(x: 340, y: 762, width: 92, height: 92)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: art, cornerWidth: 24, cornerHeight: 24, transform: nil))
    ctx.clip()
    let artGradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [pink.cgColor, violet.cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(artGradient, start: CGPoint(x: art.minX, y: art.maxY), end: CGPoint(x: art.maxX, y: art.minY), options: [])
    ctx.restoreGState()

    // Visualizer bars on the right wing
    let heights: [CGFloat] = [52, 84, 64, 96]
    for (i, h) in heights.enumerated() {
        let x = 592 + CGFloat(i) * 26
        let rect = CGRect(x: x, y: 808 - h / 2, width: 15, height: h)
        let color = [cyan, mint, cyan, violet][i]
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 16, color: color.cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 7.5, cornerHeight: 7.5, transform: nil))
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Glass highlight
    let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [NSColor.white.withAlphaComponent(0.10).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Hairline edge
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
    ctx.setLineWidth(3)
    ctx.strokePath()
}

func drawDMG(_ ctx: CGContext, size: CGSize) {
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [NSColor(calibratedRed: 0.10, green: 0.08, blue: 0.22, alpha: 1).cgColor,
                                 NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.12, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
    softBlob(ctx, center: CGPoint(x: 150, y: 330), radius: 260, color: violet, alpha: 0.45)
    softBlob(ctx, center: CGPoint(x: 520, y: 300), radius: 260, color: cyan, alpha: 0.35)
    softBlob(ctx, center: CGPoint(x: 330, y: 60), radius: 220, color: mint, alpha: 0.18)

    // Mini notch at the top edge
    ctx.addPath(notchPath(midX: size.width / 2, top: size.height, width: 190, height: 30, flare: 9, bottom: 14))
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()

    func text(_ string: String, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? font
        let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: NSColor.white.withAlphaComponent(alpha)]
        let str = NSAttributedString(string: string, attributes: attributes)
        let width = str.size().width
        str.draw(at: CGPoint(x: (size.width - width) / 2, y: y))
    }

    text("Drag Aura into Applications", size: 21, weight: .semibold, alpha: 0.95, y: 338)
    text("Your notch, turned into a live command center.", size: 12.5, weight: .medium, alpha: 0.6, y: 316)

    // Arrow between the two icons (icons sit at y≈190 from the top → 230 from the bottom)
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 268, y: 200))
    arrow.addCurve(to: CGPoint(x: 392, y: 200), control1: CGPoint(x: 300, y: 228), control2: CGPoint(x: 360, y: 228))
    ctx.addPath(arrow)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 9])
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 380, y: 214))
    head.addLine(to: CGPoint(x: 394, y: 199))
    head.addLine(to: CGPoint(x: 376, y: 192))
    ctx.addPath(head)
    ctx.setLineWidth(3)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Light plaques under the icon labels: Finder draws them in black on custom backgrounds.
    for x in [CGFloat(170), 490] {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - 64, y: 134, width: 128, height: 24),
                           cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.fillPath()
    }

    text("First launch: if macOS blocks Aura, open System Settings → Privacy & Security → Open Anyway.", size: 10.5,
         weight: .medium, alpha: 0.55, y: 34)
    text("Or Control-click Aura in Applications and choose Open.", size: 10.5, weight: .medium, alpha: 0.55, y: 18)
}

let out = URL(fileURLWithPath: args[2])
let data: Data?
switch args[1] {
case "icon":
    data = render(size: CGSize(width: 1024, height: 1024), scale: 1, draw: drawIcon)
case "dmg":
    let scale = args.count > 3 ? CGFloat(Double(args[3]) ?? 1) : 1
    let size = CGSize(width: 660, height: 420)
    data = render(size: size, scale: scale) { drawDMG($0, size: size) }
default:
    data = nil
}
guard let data else { print("render failed"); exit(1) }
try data.write(to: out)
print("wrote \(out.path)")
