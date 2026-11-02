import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let fm = FileManager.default
guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate_memory_trail_icons.swift <repo-root>\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let masterURL = root.appendingPathComponent("Branding/MemoryTrailIconMaster.png")
let appIconDir = root.appendingPathComponent("MemoryTrail/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let onboardingDir = root.appendingPathComponent("MemoryTrail/Resources/Assets.xcassets/OnboardingIcon.imageset", isDirectory: true)
try fm.createDirectory(at: masterURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try fm.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fm.createDirectory(at: onboardingDir, withIntermediateDirectories: true)

func c(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func symbol(_ name: String, in rect: CGRect, context: CGContext) {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let configuration = NSImage.SymbolConfiguration(pointSize: rect.height * 0.78, weight: .semibold)
    let configured = image.withSymbolConfiguration(configuration) ?? image
    configured.isTemplate = true
    NSColor.white.set()
    configured.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

func makeContext(_ pixels: Int) -> CGContext {
    CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

func drawCard(_ context: CGContext, rect: CGRect, angle: CGFloat, colors: [CGColor], icon: String) {
    context.saveGState()
    context.translateBy(x: rect.midX, y: rect.midY)
    context.rotate(by: angle)
    let box = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 24, color: c(0x001b45, 0.34))
    context.addPath(rounded(box, 38))
    context.clip()
    context.drawLinearGradient(gradient(colors), start: box.origin, end: CGPoint(x: box.maxX, y: box.maxY), options: [])
    context.resetClip()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setStrokeColor(c(0xffffff, 0.42))
    context.setLineWidth(4)
    context.addPath(rounded(box.insetBy(dx: 2, dy: 2), 36))
    context.strokePath()

    let tile = CGRect(x: box.minX + 28, y: box.minY + 22, width: 96, height: 96)
    context.addPath(rounded(tile, 24))
    context.clip()
    context.drawLinearGradient(
        gradient([c(0x14a8ff), c(0x1756d8), c(0x754bd7)]),
        start: tile.origin,
        end: CGPoint(x: tile.maxX, y: tile.maxY),
        options: []
    )
    context.resetClip()
    symbol(icon, in: tile.insetBy(dx: 19, dy: 19), context: context)

    context.setFillColor(c(0xd5eaff, 0.78))
    context.addPath(rounded(CGRect(x: box.minX + 150, y: box.minY + 41, width: 220, height: 18), 9))
    context.fillPath()
    context.setFillColor(c(0xb5d7ff, 0.56))
    context.addPath(rounded(CGRect(x: box.minX + 150, y: box.minY + 78, width: 165, height: 16), 8))
    context.fillPath()
    context.restoreGState()
}

func masterIcon() -> CGImage {
    let pixels = 1024
    let size = CGFloat(pixels)
    let context = makeContext(pixels)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    let iconRect = CGRect(x: 28, y: 28, width: 968, height: 968)
    let iconPath = rounded(iconRect, 205)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 18), blur: 34, color: c(0x001737, 0.45))
    context.setFillColor(c(0x062f6e))
    context.addPath(iconPath)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(iconPath)
    context.clip()
    context.drawLinearGradient(
        gradient([c(0x04265c), c(0x075bc1), c(0x6954d5), c(0x13285f)], [0, 0.38, 0.72, 1]),
        start: CGPoint(x: 80, y: 70),
        end: CGPoint(x: 950, y: 960),
        options: []
    )
    context.drawRadialGradient(
        gradient([c(0xfff7b1, 1), c(0xffad40, 0.92), c(0xf26e69, 0.40), c(0x5c3da9, 0)]),
        startCenter: CGPoint(x: 780, y: 190), startRadius: 8,
        endCenter: CGPoint(x: 780, y: 190), endRadius: 250,
        options: []
    )
    context.setFillColor(c(0xfff8bf))
    context.fillEllipse(in: CGRect(x: 718, y: 136, width: 124, height: 124))

    let hills = CGMutablePath()
    hills.move(to: CGPoint(x: 500, y: 300))
    hills.addCurve(to: CGPoint(x: 1000, y: 286), control1: CGPoint(x: 650, y: 180), control2: CGPoint(x: 820, y: 220))
    hills.addLine(to: CGPoint(x: 1000, y: 515))
    hills.addCurve(to: CGPoint(x: 510, y: 470), control1: CGPoint(x: 830, y: 430), control2: CGPoint(x: 660, y: 505))
    hills.closeSubpath()
    context.setFillColor(c(0x171f67, 0.96))
    context.addPath(hills)
    context.fillPath()

    let road = CGMutablePath()
    road.move(to: CGPoint(x: 110, y: 930))
    road.addCurve(to: CGPoint(x: 535, y: 710), control1: CGPoint(x: 245, y: 920), control2: CGPoint(x: 390, y: 815))
    road.addCurve(to: CGPoint(x: 675, y: 520), control1: CGPoint(x: 620, y: 650), control2: CGPoint(x: 640, y: 585))
    road.addCurve(to: CGPoint(x: 610, y: 410), control1: CGPoint(x: 700, y: 465), control2: CGPoint(x: 670, y: 430))
    road.addCurve(to: CGPoint(x: 812, y: 230), control1: CGPoint(x: 500, y: 360), control2: CGPoint(x: 635, y: 300))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for (width, color) in [(164.0, c(0x32e5ff, 0.38)), (124.0, c(0x202976, 0.98)), (18.0, c(0xffbd5e, 0.98))] as [(CGFloat, CGColor)] {
        context.addPath(road)
        context.setLineWidth(width)
        context.setStrokeColor(color)
        context.strokePath()
    }
    context.addPath(road)
    context.setStrokeColor(c(0xffffff, 0.96))
    context.setLineWidth(11)
    context.setLineDash(phase: 0, lengths: [46, 35])
    context.strokePath()
    context.setLineDash(phase: 0, lengths: [])

    drawCard(context, rect: CGRect(x: 100, y: 142, width: 470, height: 145), angle: -0.055, colors: [c(0x2098ff, 0.94), c(0x344bd0, 0.88), c(0x865ae8, 0.72)], icon: "globe")
    drawCard(context, rect: CGRect(x: 70, y: 265, width: 470, height: 145), angle: -0.04, colors: [c(0x2a8fff, 0.94), c(0x3245ca, 0.88), c(0x7863e4, 0.72)], icon: "envelope.fill")
    drawCard(context, rect: CGRect(x: 58, y: 390, width: 470, height: 145), angle: 0.012, colors: [c(0x1acdc3, 0.92), c(0x1478c8, 0.88), c(0x5b5bd7, 0.72)], icon: "message.fill")
    drawCard(context, rect: CGRect(x: 70, y: 515, width: 470, height: 145), angle: 0.035, colors: [c(0xffb63f, 0.94), c(0xe5707c, 0.78), c(0x685bd6, 0.74)], icon: "folder.fill")
    drawCard(context, rect: CGRect(x: 96, y: 640, width: 470, height: 145), angle: 0.052, colors: [c(0xa64eff, 0.90), c(0x6655dc, 0.86), c(0x2a83d9, 0.72)], icon: "calendar")

    let clock = CGRect(x: 570, y: 560, width: 310, height: 310)
    context.setShadow(offset: CGSize(width: 0, height: 16), blur: 30, color: c(0x00183d, 0.48))
    context.setFillColor(c(0x052d6d, 0.97))
    context.fillEllipse(in: clock)
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setStrokeColor(c(0x63e8ff, 0.98))
    context.setLineWidth(34)
    context.strokeEllipse(in: clock)
    context.setStrokeColor(c(0xffffff, 0.98))
    context.setLineWidth(22)
    context.setLineCap(.round)
    let center = CGPoint(x: clock.midX, y: clock.midY)
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x, y: center.y - 78))
    context.move(to: center)
    context.addLine(to: CGPoint(x: center.x + 70, y: center.y + 52))
    context.strokePath()
    context.setStrokeColor(c(0xffffff, 0.96))
    context.setLineWidth(24)
    context.move(to: CGPoint(x: center.x - 150, y: center.y + 10))
    context.addCurve(to: CGPoint(x: center.x - 82, y: center.y - 125), control1: CGPoint(x: center.x - 155, y: center.y - 48), control2: CGPoint(x: center.x - 130, y: center.y - 98))
    context.strokePath()
    let arrowHead = CGMutablePath()
    arrowHead.move(to: CGPoint(x: center.x - 94, y: center.y - 94))
    arrowHead.addLine(to: CGPoint(x: center.x - 82, y: center.y - 145))
    arrowHead.addLine(to: CGPoint(x: center.x - 42, y: center.y - 112))
    arrowHead.closeSubpath()
    context.setFillColor(c(0xffffff, 0.96))
    context.addPath(arrowHead)
    context.fillPath()

    context.setStrokeColor(c(0xffffff, 0.34))
    context.setLineWidth(5)
    context.addPath(rounded(iconRect.insetBy(dx: 3, dy: 3), 202))
    context.strokePath()
    context.restoreGState()
    return context.makeImage()!
}

func resize(_ image: CGImage, to pixels: Int) -> CGImage {
    let context = makeContext(pixels)
    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "MemoryTrailIcon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "MemoryTrailIcon", code: 2)
    }
}

func validate(_ url: URL, pixels: Int) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == pixels, image.height == pixels else {
        throw NSError(domain: "MemoryTrailIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid icon: \(url.path)"])
    }
}

let master = masterIcon()
try writePNG(master, to: masterURL)
try validate(masterURL, pixels: 1024)

let appTargets = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, pixels) in appTargets {
    let url = appIconDir.appendingPathComponent(name)
    try writePNG(resize(master, to: pixels), to: url)
    try validate(url, pixels: pixels)
}
for (name, pixels) in [("OnboardingIcon.png", 512), ("OnboardingIcon@2x.png", 1024)] {
    let url = onboardingDir.appendingPathComponent(name)
    try writePNG(resize(master, to: pixels), to: url)
    try validate(url, pixels: pixels)
}
print("Generated and verified clean Memory Trail macOS icon assets.")
