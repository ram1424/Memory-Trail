import AppKit
import Foundation

let fm = FileManager.default
guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_app_icons.swift <repo-root>\n", stderr)
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let appIconDir = root.appendingPathComponent("MemoryLane/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let onboardingDir = root.appendingPathComponent("MemoryLane/Resources/Assets.xcassets/OnboardingIcon.imageset", isDirectory: true)
try fm.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fm.createDirectory(at: onboardingDir, withIntermediateDirectories: true)

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fillGradient(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    path.saveGraphicsState()
    path.addClip()
    NSGradient(colors: colors)?.draw(in: path.bounds, angle: angle)
    path.restoreGraphicsState()
}

func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor = .white) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: p
    ]
    (text as NSString).draw(in: rect, withAttributes: attrs)
}

func drawCard(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, accent: NSColor, mark: String) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()

    let r = NSRect(x: x, y: y, width: w, height: h)
    let p = roundedRect(r, radius: 28)
    NSColor(calibratedRed: 0.21, green: 0.37, blue: 0.66, alpha: 0.78).setFill()
    p.fill()
    NSColor.white.withAlphaComponent(0.58).setStroke()
    p.lineWidth = 3
    p.stroke()

    let icon = NSRect(x: x + 22, y: y + 22, width: h - 44, height: h - 44)
    let ip = roundedRect(icon, radius: 18)
    accent.setFill()
    ip.fill()
    drawText(mark, in: NSRect(x: icon.minX, y: icon.minY + 7, width: icon.width, height: icon.height - 10), size: icon.height * 0.52)

    NSColor.white.withAlphaComponent(0.55).setFill()
    roundedRect(NSRect(x: icon.maxX + 22, y: y + h * 0.61, width: w - icon.width - 72, height: 12), radius: 6).fill()
    roundedRect(NSRect(x: icon.maxX + 22, y: y + h * 0.39, width: (w - icon.width - 72) * 0.78, height: 12), radius: 6).fill()
}

func drawIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let cg = NSGraphicsContext.current?.cgContext else { return image }
    cg.setShouldAntialias(true)
    cg.setAllowsAntialiasing(true)
    let s = CGFloat(size) / 1024.0
    cg.scaleBy(x: s, y: s)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let outer = roundedRect(NSRect(x: 38, y: 38, width: 948, height: 948), radius: 210)
    fillGradient(outer, colors: [
        NSColor(calibratedRed: 0.015, green: 0.09, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.28, blue: 0.72, alpha: 1),
        NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.34, alpha: 1)
    ], angle: 35)
    NSColor(calibratedRed: 0.10, green: 0.67, blue: 1.0, alpha: 0.85).setStroke()
    outer.lineWidth = 7
    outer.stroke()

    // Subtle floor
    let floor = NSBezierPath()
    floor.move(to: NSPoint(x: 42, y: 94))
    floor.line(to: NSPoint(x: 982, y: 94))
    floor.line(to: NSPoint(x: 982, y: 450))
    floor.curve(to: NSPoint(x: 42, y: 360), controlPoint1: NSPoint(x: 730, y: 520), controlPoint2: NSPoint(x: 300, y: 450))
    floor.close()
    fillGradient(floor, colors: [
        NSColor(calibratedRed: 0.02, green: 0.12, blue: 0.33, alpha: 0.9),
        NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.70, alpha: 0.45)
    ], angle: 90)

    // Glowing activity lane
    let lane = NSBezierPath()
    lane.move(to: NSPoint(x: 95, y: 130))
    lane.curve(to: NSPoint(x: 650, y: 430), controlPoint1: NSPoint(x: 280, y: 230), controlPoint2: NSPoint(x: 760, y: 185))
    lane.curve(to: NSPoint(x: 560, y: 525), controlPoint1: NSPoint(x: 575, y: 465), controlPoint2: NSPoint(x: 500, y: 485))
    lane.curve(to: NSPoint(x: 675, y: 610), controlPoint1: NSPoint(x: 630, y: 565), controlPoint2: NSPoint(x: 675, y: 575))
    lane.lineCapStyle = .round
    NSColor(calibratedRed: 0.03, green: 0.46, blue: 1.0, alpha: 0.22).setStroke()
    lane.lineWidth = 72
    lane.stroke()
    NSColor(calibratedRed: 0.14, green: 0.70, blue: 1.0, alpha: 0.9).setStroke()
    lane.lineWidth = 9
    lane.stroke()

    // Warm memory highlight along the lane
    let warm = lane.copy() as! NSBezierPath
    NSColor(calibratedRed: 1.0, green: 0.66, blue: 0.20, alpha: 0.72).setStroke()
    warm.lineWidth = 5
    warm.stroke()

    // Timeline nodes
    for point in [NSPoint(x: 205, y: 190), NSPoint(x: 405, y: 275), NSPoint(x: 610, y: 360), NSPoint(x: 620, y: 495), NSPoint(x: 660, y: 590)] {
        let glow = NSBezierPath(ovalIn: NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32))
        NSColor(calibratedRed: 0.15, green: 0.72, blue: 1.0, alpha: 0.28).setFill()
        glow.fill()
        let dot = NSBezierPath(ovalIn: NSRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16))
        NSColor.white.setFill()
        dot.fill()
        NSColor(calibratedRed: 0.13, green: 0.68, blue: 1.0, alpha: 1).setStroke()
        dot.lineWidth = 4
        dot.stroke()
    }

    // Activity cards
    drawCard(x: 170, y: 225, w: 315, h: 128, accent: NSColor.systemBlue, mark: "S")
    drawCard(x: 115, y: 390, w: 300, h: 118, accent: NSColor(calibratedRed: 0.28, green: 0.24, blue: 0.86, alpha: 1), mark: "T")
    drawCard(x: 165, y: 545, w: 300, h: 118, accent: NSColor(calibratedRed: 0.0, green: 0.52, blue: 0.95, alpha: 1), mark: "O")
    drawCard(x: 650, y: 235, w: 265, h: 112, accent: NSColor(calibratedRed: 0.08, green: 0.60, blue: 0.95, alpha: 1), mark: "F")
    drawCard(x: 690, y: 390, w: 235, h: 104, accent: NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.16, alpha: 1), mark: "N")
    drawCard(x: 715, y: 525, w: 195, h: 90, accent: NSColor(calibratedRed: 0.10, green: 0.78, blue: 0.31, alpha: 1), mark: "M")

    // Clock face
    let center = NSPoint(x: 525, y: 765)
    let face = NSBezierPath(ovalIn: NSRect(x: center.x - 165, y: center.y - 165, width: 330, height: 330))
    NSColor(calibratedRed: 0.01, green: 0.10, blue: 0.30, alpha: 0.94).setFill()
    face.fill()
    NSColor(calibratedRed: 0.56, green: 0.84, blue: 1.0, alpha: 0.82).setStroke()
    face.lineWidth = 12
    face.stroke()

    for i in 0..<12 {
        let a = CGFloat(i) * .pi / 6
        let r1: CGFloat = i % 3 == 0 ? 127 : 136
        let r2: CGFloat = 145
        let p = NSBezierPath()
        p.move(to: NSPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
        p.line(to: NSPoint(x: center.x + cos(a) * r2, y: center.y + sin(a) * r2))
        NSColor.white.withAlphaComponent(i % 3 == 0 ? 0.82 : 0.24).setStroke()
        p.lineWidth = i % 3 == 0 ? 8 : 4
        p.lineCapStyle = .round
        p.stroke()
    }

    func hand(to p: NSPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: center)
        path.line(to: p)
        path.lineCapStyle = .round
        path.lineWidth = width
        NSColor.white.setStroke()
        path.stroke()
    }
    hand(to: NSPoint(x: 610, y: 845), width: 15)
    hand(to: NSPoint(x: 455, y: 815), width: 13)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 15, y: center.y - 15, width: 30, height: 30)).fill()

    // Rewind/history arrow around the clock
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: 205, startAngle: -40, endAngle: 210, clockwise: false)
    arc.lineCapStyle = .round
    arc.lineWidth = 62
    NSColor(calibratedRed: 0.65, green: 0.88, blue: 1.0, alpha: 0.96).setStroke()
    arc.stroke()

    let tip = NSPoint(x: center.x + cos(210 * .pi / 180) * 205, y: center.y + sin(210 * .pi / 180) * 205)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: tip.x - 48, y: tip.y + 58))
    arrow.line(to: NSPoint(x: tip.x + 40, y: tip.y + 4))
    arrow.line(to: NSPoint(x: tip.x - 45, y: tip.y - 52))
    arrow.close()
    NSColor(calibratedRed: 0.75, green: 0.92, blue: 1.0, alpha: 1).setFill()
    arrow.fill()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MemoryLaneIcon", code: 1)
    }
    try data.write(to: url, options: .atomic)
}

let appTargets: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]
for (name, size) in appTargets {
    try writePNG(drawIcon(size: size), to: appIconDir.appendingPathComponent(name))
}
try writePNG(drawIcon(size: 512), to: onboardingDir.appendingPathComponent("OnboardingIcon.png"))
try writePNG(drawIcon(size: 1024), to: onboardingDir.appendingPathComponent("OnboardingIcon@2x.png"))

print("Memory Lane icons generated from the approved clock/timeline design.")
