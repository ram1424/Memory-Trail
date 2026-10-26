import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: GenerateMemoryLaneIcon.swift <AppIcon.appiconset path>\n", stderr)
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let canvas: CGFloat = 1024
let master = NSImage(size: NSSize(width: canvas, height: canvas))
master.lockFocus()
guard let context = NSGraphicsContext.current else { exit(2) }
context.imageInterpolation = .high

let outer = NSRect(x: 18, y: 18, width: 988, height: 988)
let outerPath = NSBezierPath(roundedRect: outer, xRadius: 205, yRadius: 205)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.01, green: 0.035, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.15, blue: 0.38, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.025, blue: 0.20, alpha: 1)
])!
bg.draw(in: outerPath, angle: -55)

NSGraphicsContext.saveGraphicsState()
outerPath.addClip()

let halo = NSGradient(colors: [
    NSColor(calibratedRed: 0.0, green: 0.62, blue: 1.0, alpha: 0.32),
    NSColor.clear
])!
halo.draw(fromCenter: NSPoint(x: 390, y: 745), radius: 10,
          toCenter: NSPoint(x: 390, y: 745), radius: 500, options: [])

func neonStroke(_ path: NSBezierPath, width: CGFloat, color: NSColor) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width + 28
    color.withAlphaComponent(0.18).setStroke()
    path.stroke()
    path.lineWidth = width + 10
    color.withAlphaComponent(0.42).setStroke()
    path.stroke()
    path.lineWidth = width
    color.setStroke()
    path.stroke()
    path.lineWidth = max(3, width * 0.22)
    NSColor.white.withAlphaComponent(0.70).setStroke()
    path.stroke()
}

let cyan = NSColor(calibratedRed: 0.02, green: 0.72, blue: 1.0, alpha: 1)
let blue = NSColor(calibratedRed: 0.06, green: 0.32, blue: 1.0, alpha: 1)
let purple = NSColor(calibratedRed: 0.68, green: 0.20, blue: 1.0, alpha: 1)
let pink = NSColor(calibratedRed: 0.96, green: 0.38, blue: 0.95, alpha: 1)

let leftBrain = NSBezierPath()
leftBrain.move(to: NSPoint(x: 505, y: 770))
leftBrain.curve(to: NSPoint(x: 422, y: 854), controlPoint1: NSPoint(x: 498, y: 835), controlPoint2: NSPoint(x: 468, y: 864))
leftBrain.curve(to: NSPoint(x: 337, y: 825), controlPoint1: NSPoint(x: 382, y: 873), controlPoint2: NSPoint(x: 345, y: 852))
leftBrain.curve(to: NSPoint(x: 236, y: 770), controlPoint1: NSPoint(x: 298, y: 833), controlPoint2: NSPoint(x: 247, y: 810))
leftBrain.curve(to: NSPoint(x: 180, y: 680), controlPoint1: NSPoint(x: 191, y: 752), controlPoint2: NSPoint(x: 166, y: 716))
leftBrain.curve(to: NSPoint(x: 148, y: 574), controlPoint1: NSPoint(x: 145, y: 648), controlPoint2: NSPoint(x: 132, y: 608))
leftBrain.curve(to: NSPoint(x: 181, y: 477), controlPoint1: NSPoint(x: 128, y: 536), controlPoint2: NSPoint(x: 146, y: 495))
leftBrain.curve(to: NSPoint(x: 247, y: 420), controlPoint1: NSPoint(x: 193, y: 442), controlPoint2: NSPoint(x: 218, y: 422))
leftBrain.curve(to: NSPoint(x: 342, y: 399), controlPoint1: NSPoint(x: 271, y: 392), controlPoint2: NSPoint(x: 312, y: 387))
leftBrain.curve(to: NSPoint(x: 404, y: 424), controlPoint1: NSPoint(x: 365, y: 394), controlPoint2: NSPoint(x: 389, y: 404))
neonStroke(leftBrain, width: 27, color: cyan)

let rightBrain = NSBezierPath()
rightBrain.move(to: NSPoint(x: 519, y: 770))
rightBrain.curve(to: NSPoint(x: 602, y: 854), controlPoint1: NSPoint(x: 526, y: 835), controlPoint2: NSPoint(x: 556, y: 864))
rightBrain.curve(to: NSPoint(x: 687, y: 825), controlPoint1: NSPoint(x: 642, y: 873), controlPoint2: NSPoint(x: 679, y: 852))
rightBrain.curve(to: NSPoint(x: 788, y: 770), controlPoint1: NSPoint(x: 726, y: 833), controlPoint2: NSPoint(x: 777, y: 810))
rightBrain.curve(to: NSPoint(x: 844, y: 680), controlPoint1: NSPoint(x: 833, y: 752), controlPoint2: NSPoint(x: 858, y: 716))
rightBrain.curve(to: NSPoint(x: 876, y: 574), controlPoint1: NSPoint(x: 879, y: 648), controlPoint2: NSPoint(x: 892, y: 608))
rightBrain.curve(to: NSPoint(x: 843, y: 477), controlPoint1: NSPoint(x: 896, y: 536), controlPoint2: NSPoint(x: 878, y: 495))
rightBrain.curve(to: NSPoint(x: 777, y: 420), controlPoint1: NSPoint(x: 831, y: 442), controlPoint2: NSPoint(x: 806, y: 422))
rightBrain.curve(to: NSPoint(x: 682, y: 399), controlPoint1: NSPoint(x: 753, y: 392), controlPoint2: NSPoint(x: 712, y: 387))
rightBrain.curve(to: NSPoint(x: 620, y: 424), controlPoint1: NSPoint(x: 659, y: 394), controlPoint2: NSPoint(x: 635, y: 404))
neonStroke(rightBrain, width: 27, color: pink)

let center = NSBezierPath()
center.move(to: NSPoint(x: 512, y: 853))
center.line(to: NSPoint(x: 512, y: 747))
neonStroke(center, width: 25, color: cyan)

func fold(_ points: [NSPoint], color: NSColor, width: CGFloat = 18) {
    guard points.count >= 2 else { return }
    let p = NSBezierPath()
    p.move(to: points[0])
    for i in 1..<points.count {
        let prev = points[i - 1], next = points[i]
        let mid = NSPoint(x: (prev.x + next.x)/2, y: (prev.y + next.y)/2)
        p.curve(to: next, controlPoint1: mid, controlPoint2: mid)
    }
    neonStroke(p, width: width, color: color)
}

fold([NSPoint(x:260,y:700),NSPoint(x:320,y:737),NSPoint(x:370,y:705)], color: cyan)
fold([NSPoint(x:220,y:610),NSPoint(x:305,y:640),NSPoint(x:375,y:602)], color: cyan)
fold([NSPoint(x:220,y:510),NSPoint(x:300,y:535),NSPoint(x:360,y:510)], color: blue)
fold([NSPoint(x:330,y:785),NSPoint(x:350,y:745),NSPoint(x:390,y:735)], color: cyan)
fold([NSPoint(x:764,y:700),NSPoint(x:704,y:737),NSPoint(x:654,y:705)], color: pink)
fold([NSPoint(x:804,y:610),NSPoint(x:719,y:640),NSPoint(x:649,y:602)], color: purple)
fold([NSPoint(x:804,y:510),NSPoint(x:724,y:535),NSPoint(x:664,y:510)], color: purple)
fold([NSPoint(x:694,y:785),NSPoint(x:674,y:745),NSPoint(x:634,y:735)], color: pink)

let road = NSBezierPath()
road.move(to: NSPoint(x: 472, y: 720))
road.curve(to: NSPoint(x: 607, y: 660), controlPoint1: NSPoint(x: 530, y: 706), controlPoint2: NSPoint(x: 602, y: 698))
road.curve(to: NSPoint(x: 462, y: 566), controlPoint1: NSPoint(x: 614, y: 616), controlPoint2: NSPoint(x: 482, y: 622))
road.curve(to: NSPoint(x: 637, y: 466), controlPoint1: NSPoint(x: 421, y: 524), controlPoint2: NSPoint(x: 600, y: 532))
road.curve(to: NSPoint(x: 526, y: 335), controlPoint1: NSPoint(x: 688, y: 396), controlPoint2: NSPoint(x: 569, y: 398))
road.curve(to: NSPoint(x: 267, y: 133), controlPoint1: NSPoint(x: 462, y: 242), controlPoint2: NSPoint(x: 354, y: 177))
road.lineCapStyle = .round
road.lineJoinStyle = .round
road.lineWidth = 100
blue.withAlphaComponent(0.98).setStroke()
road.stroke()
road.lineWidth = 62
cyan.withAlphaComponent(0.95).setStroke()
road.stroke()
road.lineWidth = 12
NSColor.white.withAlphaComponent(0.96).setStroke()
road.stroke()

let lane = NSBezierPath()
lane.move(to: NSPoint(x: 502, y: 699))
lane.curve(to: NSPoint(x: 575, y: 658), controlPoint1: NSPoint(x: 542, y: 690), controlPoint2: NSPoint(x: 578, y: 676))
lane.curve(to: NSPoint(x: 492, y: 582), controlPoint1: NSPoint(x: 578, y: 626), controlPoint2: NSPoint(x: 505, y: 618))
lane.curve(to: NSPoint(x: 600, y: 486), controlPoint1: NSPoint(x: 461, y: 552), controlPoint2: NSPoint(x: 582, y: 531))
lane.curve(to: NSPoint(x: 498, y: 353), controlPoint1: NSPoint(x: 630, y: 419), controlPoint2: NSPoint(x: 540, y: 409))
lane.lineWidth = 13
lane.lineCapStyle = .round
lane.setLineDash([30, 27], count: 2, phase: 0)
NSColor.white.withAlphaComponent(0.90).setStroke()
lane.stroke()

NSGraphicsContext.restoreGraphicsState()
master.unlockFocus()

func pngData(_ image: NSImage, size: Int) -> Data? {
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: NSRect(x: 0, y: 0, width: 1024, height: 1024),
               operation: .copy, fraction: 1)
    output.unlockFocus()
    guard let tiff = output.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MemoryLaneIcon-\(UUID().uuidString)")
let iconset = tempRoot.appendingPathExtension("iconset")
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fileManager.removeItem(at: iconset) }

let files: [(String, Int)] = [
    ("icon_16x16.png",16), ("icon_16x16@2x.png",32),
    ("icon_32x32.png",32), ("icon_32x32@2x.png",64),
    ("icon_128x128.png",128), ("icon_128x128@2x.png",256),
    ("icon_256x256.png",256), ("icon_256x256@2x.png",512),
    ("icon_512x512.png",512), ("icon_512x512@2x.png",1024)
]

for (name, size) in files {
    guard let data = pngData(master, size: size) else { exit(3) }
    try data.write(to: iconset.appendingPathComponent(name), options: .atomic)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\\n", stderr)
    exit(iconutil.terminationStatus)
}
