import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: GenerateMemoryLaneIcon.swift <AppIcon.appiconset directory>\n", stderr)
    exit(1)
}

let redirectedPath = arguments[1].replacingOccurrences(of: "/Recall/Resources/", with: "/MemoryLane/Resources/")
let appIconSetURL = URL(fileURLWithPath: redirectedPath, isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)

let canvas = CGFloat(1024)
let master = NSImage(size: NSSize(width: canvas, height: canvas))
master.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let iconRect = NSRect(x: 28, y: 28, width: 968, height: 968)
let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)
let shadow = NSShadow()
shadow.shadowBlurRadius = 38
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
shadow.set()

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.025, green: 0.06, blue: 0.20, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.03, green: 0.015, blue: 0.14, alpha: 1)
])!
background.draw(in: iconPath, angle: -55)

NSGraphicsContext.current?.saveGraphicsState()
iconPath.addClip()

let foregroundTransform = NSAffineTransform()
foregroundTransform.translateX(by: canvas / 2, yBy: canvas / 2)
foregroundTransform.scale(by: 1.20)
foregroundTransform.translateX(by: -canvas / 2, yBy: -canvas / 2)
foregroundTransform.concat()

let glow = NSGradient(colors: [
    NSColor(calibratedRed: 0.0, green: 0.50, blue: 1.0, alpha: 0.30),
    NSColor.clear
])!
glow.draw(fromCenter: NSPoint(x: 565, y: 735), radius: 10,
          toCenter: NSPoint(x: 565, y: 735), radius: 460,
          options: [])

func drawCard(_ rect: NSRect, alpha: CGFloat) {
    let p = NSBezierPath(roundedRect: rect, xRadius: 55, yRadius: 55)
    NSColor(calibratedRed: 0.02, green: 0.18, blue: 0.55, alpha: alpha).setFill()
    p.fill()
    NSColor(calibratedRed: 0.12, green: 0.62, blue: 1.0, alpha: 0.58).setStroke()
    p.lineWidth = 5
    p.stroke()
}

drawCard(NSRect(x: 125, y: 265, width: 355, height: 300), alpha: 0.72)
drawCard(NSRect(x: 190, y: 205, width: 365, height: 315), alpha: 0.78)
drawCard(NSRect(x: 265, y: 145, width: 390, height: 330), alpha: 0.88)

let clockRect = NSRect(x: 370, y: 310, width: 345, height: 345)
let clockPath = NSBezierPath(ovalIn: clockRect)
let clockGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.0, green: 0.47, blue: 0.98, alpha: 0.96),
    NSColor(calibratedRed: 0.02, green: 0.10, blue: 0.45, alpha: 0.98)
])!
clockGradient.draw(in: clockPath, angle: -60)

let arc = NSBezierPath()
arc.appendArc(withCenter: NSPoint(x: 535, y: 520), radius: 330,
              startAngle: 42, endAngle: 318, clockwise: false)
arc.lineWidth = 118
arc.lineCapStyle = .round
NSColor(calibratedRed: 0.18, green: 0.76, blue: 1.0, alpha: 0.98).setStroke()
arc.stroke()

let accent = NSBezierPath()
accent.appendArc(withCenter: NSPoint(x: 535, y: 520), radius: 330,
                 startAngle: 318, endAngle: 355, clockwise: false)
accent.lineWidth = 118
accent.lineCapStyle = .round
NSColor(calibratedRed: 0.64, green: 0.42, blue: 1.0, alpha: 0.92).setStroke()
accent.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: 166, y: 736))
arrowHead.line(to: NSPoint(x: 330, y: 842))
arrowHead.curve(to: NSPoint(x: 348, y: 792), controlPoint1: NSPoint(x: 343, y: 834), controlPoint2: NSPoint(x: 350, y: 813))
arrowHead.line(to: NSPoint(x: 352, y: 665))
arrowHead.curve(to: NSPoint(x: 314, y: 638), controlPoint1: NSPoint(x: 349, y: 640), controlPoint2: NSPoint(x: 330, y: 632))
arrowHead.line(to: NSPoint(x: 166, y: 700))
arrowHead.curve(to: NSPoint(x: 166, y: 736), controlPoint1: NSPoint(x: 146, y: 708), controlPoint2: NSPoint(x: 148, y: 727))
arrowHead.close()
let arrowGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.75, green: 0.65, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.68, blue: 1.0, alpha: 1)
])!
arrowGradient.draw(in: arrowHead, angle: -35)
NSColor.white.withAlphaComponent(0.34).setStroke()
arrowHead.lineWidth = 5
arrowHead.stroke()

func strokeLine(from: NSPoint, to: NSPoint, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: from)
    p.line(to: to)
    p.lineWidth = width
    p.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.95).setStroke()
    p.stroke()
}
let center = NSPoint(x: 543, y: 482)
strokeLine(from: center, to: NSPoint(x: 543, y: 616), width: 26)
strokeLine(from: center, to: NSPoint(x: 640, y: 417), width: 26)
NSColor(calibratedRed: 0.74, green: 0.86, blue: 1.0, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56)).fill()
NSColor.white.withAlphaComponent(0.82).setStroke()
let hub = NSBezierPath(ovalIn: NSRect(x: center.x - 28, y: center.y - 28, width: 56, height: 56))
hub.lineWidth = 8
hub.stroke()

NSGraphicsContext.current?.restoreGraphicsState()
master.unlockFocus()

func pngData(from image: NSImage, size: Int) -> Data? {
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    output.unlockFocus()
    guard let tiff = output.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}

let outputs: [(String, Int)] = [
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

for (name, size) in outputs {
    guard let data = pngData(from: master, size: size) else {
        fputs("Unable to render \(name)\n", stderr)
        exit(2)
    }
    try data.write(to: appIconSetURL.appendingPathComponent(name), options: .atomic)
}
