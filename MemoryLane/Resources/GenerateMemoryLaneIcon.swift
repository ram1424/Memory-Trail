import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "memory-lane-icon-master.png"
let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))

func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, shadowColor: NSColor? = nil, shadowBlur: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    if let shadowColor {
        let shadow = NSShadow()
        shadow.shadowColor = shadowColor
        shadow.shadowBlurRadius = shadowBlur
        shadow.shadowOffset = .zero
        shadow.set()
    }
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

image.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .high

let bgRect = NSRect(x: 18, y: 18, width: 988, height: 988)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 220, yRadius: 220)
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.01, green: 0.04, blue: 0.13, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.13, blue: 0.34, alpha: 1),
    NSColor(calibratedRed: 0.11, green: 0.04, blue: 0.23, alpha: 1)
])!
bgGradient.draw(in: bgPath, angle: -45)

let innerBorder = NSBezierPath(roundedRect: NSInsetRect(bgRect, 8, 8), xRadius: 210, yRadius: 210)
stroke(innerBorder, color: NSColor(calibratedRed: 0.15, green: 0.55, blue: 1.0, alpha: 0.40), width: 5)

let glow1 = NSBezierPath(ovalIn: NSRect(x: 120, y: 330, width: 560, height: 560))
NSColor(calibratedRed: 0.0, green: 0.55, blue: 1.0, alpha: 0.07).setFill()
glow1.fill()
let glow2 = NSBezierPath(ovalIn: NSRect(x: 390, y: 240, width: 500, height: 500))
NSColor(calibratedRed: 0.65, green: 0.10, blue: 1.0, alpha: 0.07).setFill()
glow2.fill()

let brain = NSBezierPath()
brain.move(to: p(510, 690))
brain.curve(to: p(445, 785), controlPoint1: p(500, 760), controlPoint2: p(480, 805))
brain.curve(to: p(325, 790), controlPoint1: p(405, 812), controlPoint2: p(350, 812))
brain.curve(to: p(250, 735), controlPoint1: p(286, 781), controlPoint2: p(252, 760))
brain.curve(to: p(205, 650), controlPoint1: p(218, 716), controlPoint2: p(195, 684))
brain.curve(to: p(220, 560), controlPoint1: p(187, 618), controlPoint2: p(194, 585))
brain.curve(to: p(275, 510), controlPoint1: p(232, 536), controlPoint2: p(250, 516))
brain.curve(to: p(260, 425), controlPoint1: p(245, 480), controlPoint2: p(238, 449))
brain.curve(to: p(315, 345), controlPoint1: p(267, 389), controlPoint2: p(289, 357))
brain.curve(to: p(405, 330), controlPoint1: p(345, 330), controlPoint2: p(376, 325))
brain.curve(to: p(510, 360), controlPoint1: p(450, 329), controlPoint2: p(488, 340))
brain.curve(to: p(615, 330), controlPoint1: p(535, 340), controlPoint2: p(575, 326))
brain.curve(to: p(710, 350), controlPoint1: p(650, 324), controlPoint2: p(686, 332))
brain.curve(to: p(770, 420), controlPoint1: p(738, 360), controlPoint2: p(759, 389))
brain.curve(to: p(760, 510), controlPoint1: p(783, 452), controlPoint2: p(781, 486))
brain.curve(to: p(815, 570), controlPoint1: p(785, 520), controlPoint2: p(809, 540))
brain.curve(to: p(820, 655), controlPoint1: p(830, 596), controlPoint2: p(830, 628))
brain.curve(to: p(775, 730), controlPoint1: p(810, 690), controlPoint2: p(795, 713))
brain.curve(to: p(690, 785), controlPoint1: p(750, 756), controlPoint2: p(718, 779))
brain.curve(to: p(575, 782), controlPoint1: p(650, 798), controlPoint2: p(610, 794))
brain.curve(to: p(510, 690), controlPoint1: p(540, 770), controlPoint2: p(515, 740))

stroke(brain, color: NSColor(calibratedRed: 0.0, green: 0.75, blue: 1.0, alpha: 0.25), width: 34, shadowColor: NSColor(calibratedRed: 0.0, green: 0.55, blue: 1.0, alpha: 0.75), shadowBlur: 26)
stroke(brain, color: NSColor(calibratedRed: 0.32, green: 0.90, blue: 1.0, alpha: 1), width: 20)
stroke(brain, color: NSColor.white.withAlphaComponent(0.88), width: 7)

let rightGlow = NSBezierPath()
rightGlow.move(to: p(510, 690))
rightGlow.curve(to: p(615, 330), controlPoint1: p(540, 525), controlPoint2: p(550, 360))
rightGlow.curve(to: p(815, 570), controlPoint1: p(690, 325), controlPoint2: p(810, 420))
stroke(rightGlow, color: NSColor(calibratedRed: 1.0, green: 0.25, blue: 0.95, alpha: 0.42), width: 18, shadowColor: NSColor.magenta.withAlphaComponent(0.55), shadowBlur: 18)

let folds: [(NSBezierPath, NSColor)] = {
    var arr: [(NSBezierPath, NSColor)] = []
    func curve(_ points: [NSPoint], _ color: NSColor) {
        let b = NSBezierPath()
        b.move(to: points[0])
        b.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
        arr.append((b,color))
    }
    curve([p(300,650),p(345,700),p(405,700),p(430,650)], .cyan)
    curve([p(280,570),p(330,610),p(390,610),p(425,575)], NSColor(calibratedRed:0.20,green:0.65,blue:1,alpha:1))
    curve([p(315,465),p(360,500),p(410,500),p(445,470)], NSColor(calibratedRed:0.18,green:0.55,blue:1,alpha:1))
    curve([p(580,650),p(620,700),p(675,695),p(710,645)], NSColor(calibratedRed:0.80,green:0.30,blue:1,alpha:1))
    curve([p(600,555),p(650,600),p(710,590),p(735,550)], NSColor(calibratedRed:0.88,green:0.28,blue:1,alpha:1))
    curve([p(585,455),p(635,500),p(690,490),p(725,455)], NSColor(calibratedRed:0.68,green:0.25,blue:1,alpha:1))
    return arr
}()
for (f,c) in folds {
    stroke(f, color: c.withAlphaComponent(0.30), width: 28, shadowColor: c.withAlphaComponent(0.55), shadowBlur: 18)
    stroke(f, color: c.withAlphaComponent(0.96), width: 15)
    stroke(f, color: .white.withAlphaComponent(0.55), width: 4)
}

let road = NSBezierPath()
road.move(to: p(315, 80))
road.curve(to: p(520, 340), controlPoint1: p(470, 125), controlPoint2: p(665, 225))
road.curve(to: p(495, 545), controlPoint1: p(400, 430), controlPoint2: p(420, 500))
road.curve(to: p(545, 710), controlPoint1: p(560, 610), controlPoint2: p(575, 670))

stroke(road, color: NSColor(calibratedRed: 0.1, green: 0.15, blue: 0.55, alpha: 0.75), width: 170, shadowColor: NSColor(calibratedRed:0.0,green:0.5,blue:1,alpha:0.75), shadowBlur: 34)
stroke(road, color: NSColor(calibratedRed: 0.12, green: 0.55, blue: 1.0, alpha: 0.95), width: 112)
stroke(road, color: NSColor(calibratedRed: 0.64, green: 0.22, blue: 0.95, alpha: 0.52), width: 66)
stroke(road, color: NSColor.white.withAlphaComponent(0.88), width: 14)

let lane = NSBezierPath()
lane.move(to: p(360, 92))
lane.curve(to: p(545, 340), controlPoint1: p(485, 145), controlPoint2: p(625, 245))
lane.curve(to: p(520, 545), controlPoint1: p(430, 430), controlPoint2: p(445, 500))
lane.curve(to: p(560, 700), controlPoint1: p(580, 610), controlPoint2: p(590, 660))
lane.setLineDash([34, 34], count: 2, phase: 0)
stroke(lane, color: .white.withAlphaComponent(0.95), width: 12)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Generated \(outputPath)")
