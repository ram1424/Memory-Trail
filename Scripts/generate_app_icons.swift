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
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: colors)?.draw(in: path.bounds, angle: angle)
    NSGraphicsContext.restoreGraphicsState()
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

    guard let cg = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    cg.setShouldAntialias(true)
    cg.setAllowsAntialiasing(true)

    let s = CGFloat(size) / 1024.0
    cg.scaleBy(x: s, y: s)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()

    let outerRect = NSRect(x: 42, y: 42, width: 940, height: 940)
    let outer = roundedRect(outerRect, radius: 214)

    let outerShadow = NSShadow()
    outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    outerShadow.shadowBlurRadius = 34
    outerShadow.shadowOffset = NSSize(width: 0, height: -16)
    outerShadow.set()

    fillGradient(
        outer,
        colors: [
            NSColor(calibratedRed: 0.015, green: 0.07, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.01, green: 0.16, blue: 0.43, alpha: 1),
            NSColor(calibratedRed: 0.025, green: 0.07, blue: 0.20, alpha: 1)
        ],
        angle: 38
    )

    NSGraphicsContext.saveGraphicsState()
    outer.addClip()

    // Atmospheric blue glow behind the brain.
    let backGlow = NSBezierPath(ovalIn: NSRect(x: 120, y: 390, width: 800, height: 610))
    fillGradient(
        backGlow,
        colors: [
            NSColor(calibratedRed: 0.05, green: 0.68, blue: 1.0, alpha: 0.23),
            NSColor(calibratedRed: 0.35, green: 0.20, blue: 0.92, alpha: 0.08)
        ],
        angle: 20
    )

    // Brain base silhouette.
    let brain = NSBezierPath()
    brain.move(to: NSPoint(x: 224, y: 560))
    brain.curve(to: NSPoint(x: 205, y: 735),
                controlPoint1: NSPoint(x: 150, y: 620),
                controlPoint2: NSPoint(x: 155, y: 700))
    brain.curve(to: NSPoint(x: 330, y: 885),
                controlPoint1: NSPoint(x: 220, y: 820),
                controlPoint2: NSPoint(x: 270, y: 865))
    brain.curve(to: NSPoint(x: 500, y: 902),
                controlPoint1: NSPoint(x: 390, y: 915),
                controlPoint2: NSPoint(x: 455, y: 920))
    brain.curve(to: NSPoint(x: 665, y: 875),
                controlPoint1: NSPoint(x: 550, y: 930),
                controlPoint2: NSPoint(x: 620, y: 915))
    brain.curve(to: NSPoint(x: 820, y: 765),
                controlPoint1: NSPoint(x: 755, y: 855),
                controlPoint2: NSPoint(x: 810, y: 815))
    brain.curve(to: NSPoint(x: 810, y: 605),
                controlPoint1: NSPoint(x: 855, y: 705),
                controlPoint2: NSPoint(x: 850, y: 650))
    brain.curve(to: NSPoint(x: 720, y: 520),
                controlPoint1: NSPoint(x: 792, y: 565),
                controlPoint2: NSPoint(x: 760, y: 535))
    brain.curve(to: NSPoint(x: 580, y: 510),
                controlPoint1: NSPoint(x: 675, y: 500),
                controlPoint2: NSPoint(x: 620, y: 505))
    brain.curve(to: NSPoint(x: 455, y: 485),
                controlPoint1: NSPoint(x: 535, y: 495),
                controlPoint2: NSPoint(x: 500, y: 480))
    brain.curve(to: NSPoint(x: 320, y: 505),
                controlPoint1: NSPoint(x: 405, y: 475),
                controlPoint2: NSPoint(x: 355, y: 485))
    brain.curve(to: NSPoint(x: 224, y: 560),
                controlPoint1: NSPoint(x: 280, y: 510),
                controlPoint2: NSPoint(x: 245, y: 535))
    brain.close()

    let brainShadow = NSShadow()
    brainShadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
    brainShadow.shadowBlurRadius = 26
    brainShadow.shadowOffset = NSSize(width: 0, height: -10)
    brainShadow.set()

    fillGradient(
        brain,
        colors: [
            NSColor(calibratedRed: 0.04, green: 0.50, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.78, alpha: 1),
            NSColor(calibratedRed: 0.40, green: 0.23, blue: 0.82, alpha: 1)
        ],
        angle: 25
    )

    // Brain lobes: large, clean forms that survive at small icon sizes.
    let lobes: [(NSRect, [NSColor])] = [
        (NSRect(x: 185, y: 650, width: 210, height: 210),
         [NSColor(calibratedRed: 0.08, green: 0.74, blue: 1.0, alpha: 0.95),
          NSColor(calibratedRed: 0.05, green: 0.30, blue: 0.86, alpha: 0.95)]),
        (NSRect(x: 285, y: 760, width: 210, height: 190),
         [NSColor(calibratedRed: 0.20, green: 0.72, blue: 1.0, alpha: 0.96),
          NSColor(calibratedRed: 0.09, green: 0.32, blue: 0.90, alpha: 0.96)]),
        (NSRect(x: 410, y: 775, width: 220, height: 185),
         [NSColor(calibratedRed: 0.25, green: 0.66, blue: 1.0, alpha: 0.96),
          NSColor(calibratedRed: 0.18, green: 0.33, blue: 0.94, alpha: 0.96)]),
        (NSRect(x: 545, y: 735, width: 225, height: 205),
         [NSColor(calibratedRed: 0.52, green: 0.38, blue: 0.98, alpha: 0.96),
          NSColor(calibratedRed: 0.23, green: 0.28, blue: 0.88, alpha: 0.96)]),
        (NSRect(x: 650, y: 625, width: 205, height: 225),
         [NSColor(calibratedRed: 0.72, green: 0.32, blue: 0.86, alpha: 0.92),
          NSColor(calibratedRed: 0.18, green: 0.24, blue: 0.78, alpha: 0.95)]),
        (NSRect(x: 250, y: 565, width: 220, height: 210),
         [NSColor(calibratedRed: 0.05, green: 0.60, blue: 0.98, alpha: 0.96),
          NSColor(calibratedRed: 0.04, green: 0.25, blue: 0.78, alpha: 0.96)]),
        (NSRect(x: 430, y: 560, width: 230, height: 205),
         [NSColor(calibratedRed: 0.15, green: 0.48, blue: 0.98, alpha: 0.95),
          NSColor(calibratedRed: 0.15, green: 0.23, blue: 0.80, alpha: 0.96)])
    ]

    for (rect, colors) in lobes {
        let lobe = NSBezierPath(ovalIn: rect)
        fillGradient(lobe, colors: colors, angle: 45)
        NSColor.white.withAlphaComponent(0.08).setStroke()
        lobe.lineWidth = 3
        lobe.stroke()
    }

    // Warm memory glow at the destination point.
    let memoryGlow = NSBezierPath(ovalIn: NSRect(x: 585, y: 645, width: 220, height: 220))
    fillGradient(
        memoryGlow,
        colors: [
            NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.30, alpha: 0.88),
            NSColor(calibratedRed: 1.0, green: 0.35, blue: 0.62, alpha: 0.52),
            NSColor.clear
        ],
        angle: 35
    )

    // Subtle brain folds.
    let foldSpecs: [(NSPoint, NSPoint, NSPoint, NSPoint)] = [
        (NSPoint(x: 285, y: 785), NSPoint(x: 345, y: 835), NSPoint(x: 385, y: 710), NSPoint(x: 430, y: 760)),
        (NSPoint(x: 455, y: 850), NSPoint(x: 520, y: 900), NSPoint(x: 550, y: 760), NSPoint(x: 590, y: 815)),
        (NSPoint(x: 600, y: 760), NSPoint(x: 665, y: 830), NSPoint(x: 720, y: 720), NSPoint(x: 760, y: 750)),
        (NSPoint(x: 270, y: 630), NSPoint(x: 340, y: 690), NSPoint(x: 400, y: 590), NSPoint(x: 460, y: 625))
    ]

    for spec in foldSpecs {
        let fold = NSBezierPath()
        fold.move(to: spec.0)
        fold.curve(to: spec.3, controlPoint1: spec.1, controlPoint2: spec.2)
        fold.lineCapStyle = .round
        fold.lineWidth = 10
        NSColor.white.withAlphaComponent(0.17).setStroke()
        fold.stroke()
    }

    // The memory road curves from the foreground into the brain.
    let road = NSBezierPath()
    road.move(to: NSPoint(x: 430, y: 90))
    road.curve(
        to: NSPoint(x: 590, y: 315),
        controlPoint1: NSPoint(x: 430, y: 180),
        controlPoint2: NSPoint(x: 655, y: 190)
    )
    road.curve(
        to: NSPoint(x: 535, y: 470),
        controlPoint1: NSPoint(x: 545, y: 375),
        controlPoint2: NSPoint(x: 485, y: 410)
    )
    road.curve(
        to: NSPoint(x: 665, y: 650),
        controlPoint1: NSPoint(x: 585, y: 530),
        controlPoint2: NSPoint(x: 660, y: 560)
    )
    road.lineCapStyle = .round
    road.lineJoinStyle = .round

    // Outer blue glow.
    NSColor(calibratedRed: 0.02, green: 0.60, blue: 1.0, alpha: 0.22).setStroke()
    road.lineWidth = 238
    road.stroke()

    // Warm rim visible around the road.
    NSColor(calibratedRed: 1.0, green: 0.61, blue: 0.28, alpha: 0.88).setStroke()
    road.lineWidth = 210
    road.stroke()

    // Main road surface.
    let roadSurface = road.copy() as! NSBezierPath
    roadSurface.lineCapStyle = .round
    roadSurface.lineJoinStyle = .round
    NSColor(calibratedRed: 0.08, green: 0.20, blue: 0.72, alpha: 1).setStroke()
    roadSurface.lineWidth = 184
    roadSurface.stroke()

    // Cool inner highlight makes the road read as dimensional.
    let roadHighlight = road.copy() as! NSBezierPath
    NSColor(calibratedRed: 0.26, green: 0.44, blue: 1.0, alpha: 0.46).setStroke()
    roadHighlight.lineWidth = 150
    roadHighlight.stroke()

    // White dashed center line.
    let dash = road.copy() as! NSBezierPath
    dash.lineCapStyle = .round
    dash.lineWidth = 15
    var dashPattern: [CGFloat] = [48, 42]
    dash.setLineDash(&dashPattern, count: dashPattern.count, phase: 0)
    NSColor.white.withAlphaComponent(0.96).setStroke()
    dash.stroke()

    // Destination light.
    let destination = NSBezierPath(ovalIn: NSRect(x: 625, y: 610, width: 86, height: 86))
    fillGradient(
        destination,
        colors: [
            NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.72, alpha: 1),
            NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.28, alpha: 0.96)
        ],
        angle: 45
    )

    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedRed: 0.04, green: 0.56, blue: 1.0, alpha: 0.88).setStroke()
    outer.lineWidth = 7
    outer.stroke()

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

print("Memory Lane icons generated from the approved brain-and-road design.")
