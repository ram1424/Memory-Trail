#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

@main
struct MemoryLaneApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared

    init() {
        do {
            container = try ModelContainer(for: MemoryItem.self)
        } catch {
            fatalError("Unable to initialize Memory Lane database: \(error)")
        }

        NSApplication.shared.applicationIconImage = Self.makeDockIcon()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .modelContainer(container)
                .task {
                    MacCaptureCoordinator.shared.start(context: container.mainContext)
                }
        }
        .defaultSize(width: 1000, height: 700)

        MenuBarExtra("Memory Lane", systemImage: preferences.capturePaused ? "pause.circle" : "brain.head.profile") {
            Button(preferences.capturePaused ? "Resume Capture" : "Pause Capture") {
                preferences.capturePaused.toggle()
            }
            Divider()
            Text("Memory Lane is local-first")
                .foregroundStyle(.secondary)
            Button("Quit Memory Lane") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static func makeDockIcon() -> NSImage {
        let canvas = CGFloat(1024)
        let image = NSImage(size: NSSize(width: canvas, height: canvas))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let iconRect = NSRect(x: 28, y: 28, width: 968, height: 968)
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 190, yRadius: 190)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 38
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.set()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.025, green: 0.06, blue: 0.20, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.30, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.015, blue: 0.14, alpha: 1)
        ])!.draw(in: iconPath, angle: -55)

        NSGraphicsContext.current?.saveGraphicsState()
        iconPath.addClip()

        // Enlarge the foreground artwork by 20% while preserving the outer icon shape.
        let transform = NSAffineTransform()
        transform.translateX(by: canvas / 2, yBy: canvas / 2)
        transform.scale(by: 1.20)
        transform.translateX(by: -canvas / 2, yBy: -canvas / 2)
        transform.concat()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.0, green: 0.50, blue: 1.0, alpha: 0.30),
            NSColor.clear
        ])!.draw(
            fromCenter: NSPoint(x: 565, y: 735),
            radius: 10,
            toCenter: NSPoint(x: 565, y: 735),
            radius: 460,
            options: []
        )

        func drawCard(_ rect: NSRect, alpha: CGFloat) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 55, yRadius: 55)
            NSColor(calibratedRed: 0.02, green: 0.18, blue: 0.55, alpha: alpha).setFill()
            path.fill()
            NSColor(calibratedRed: 0.12, green: 0.62, blue: 1.0, alpha: 0.58).setStroke()
            path.lineWidth = 5
            path.stroke()
        }

        drawCard(NSRect(x: 125, y: 265, width: 355, height: 300), alpha: 0.72)
        drawCard(NSRect(x: 190, y: 205, width: 365, height: 315), alpha: 0.78)
        drawCard(NSRect(x: 265, y: 145, width: 390, height: 330), alpha: 0.88)

        let clockRect = NSRect(x: 370, y: 310, width: 345, height: 345)
        let clockPath = NSBezierPath(ovalIn: clockRect)
        NSGradient(colors: [
            NSColor(calibratedRed: 0.0, green: 0.47, blue: 0.98, alpha: 0.96),
            NSColor(calibratedRed: 0.02, green: 0.10, blue: 0.45, alpha: 0.98)
        ])!.draw(in: clockPath, angle: -60)

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: NSPoint(x: 535, y: 520),
            radius: 330,
            startAngle: 42,
            endAngle: 318,
            clockwise: false
        )
        arc.lineWidth = 118
        arc.lineCapStyle = .round
        NSColor(calibratedRed: 0.18, green: 0.76, blue: 1.0, alpha: 0.98).setStroke()
        arc.stroke()

        let accent = NSBezierPath()
        accent.appendArc(
            withCenter: NSPoint(x: 535, y: 520),
            radius: 330,
            startAngle: 318,
            endAngle: 355,
            clockwise: false
        )
        accent.lineWidth = 118
        accent.lineCapStyle = .round
        NSColor(calibratedRed: 0.64, green: 0.42, blue: 1.0, alpha: 0.92).setStroke()
        accent.stroke()

        let arrowHead = NSBezierPath()
        arrowHead.move(to: NSPoint(x: 166, y: 736))
        arrowHead.line(to: NSPoint(x: 330, y: 842))
        arrowHead.curve(
            to: NSPoint(x: 348, y: 792),
            controlPoint1: NSPoint(x: 343, y: 834),
            controlPoint2: NSPoint(x: 350, y: 813)
        )
        arrowHead.line(to: NSPoint(x: 352, y: 665))
        arrowHead.curve(
            to: NSPoint(x: 314, y: 638),
            controlPoint1: NSPoint(x: 349, y: 640),
            controlPoint2: NSPoint(x: 330, y: 632)
        )
        arrowHead.line(to: NSPoint(x: 166, y: 700))
        arrowHead.curve(
            to: NSPoint(x: 166, y: 736),
            controlPoint1: NSPoint(x: 146, y: 708),
            controlPoint2: NSPoint(x: 148, y: 727)
        )
        arrowHead.close()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.75, green: 0.65, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.20, green: 0.68, blue: 1.0, alpha: 1)
        ])!.draw(in: arrowHead, angle: -35)

        NSColor.white.withAlphaComponent(0.34).setStroke()
        arrowHead.lineWidth = 5
        arrowHead.stroke()

        func strokeLine(from: NSPoint, to: NSPoint, width: CGFloat) {
            let path = NSBezierPath()
            path.move(to: from)
            path.line(to: to)
            path.lineWidth = width
            path.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.95).setStroke()
            path.stroke()
        }

        let center = NSPoint(x: 543, y: 482)
        strokeLine(from: center, to: NSPoint(x: 543, y: 616), width: 26)
        strokeLine(from: center, to: NSPoint(x: 640, y: 417), width: 26)

        NSColor(calibratedRed: 0.74, green: 0.86, blue: 1.0, alpha: 1).setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - 28,
                y: center.y - 28,
                width: 56,
                height: 56
            )
        ).fill()

        NSColor.white.withAlphaComponent(0.82).setStroke()
        let hub = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - 28,
                y: center.y - 28,
                width: 56,
                height: 56
            )
        )
        hub.lineWidth = 8
        hub.stroke()

        NSGraphicsContext.current?.restoreGraphicsState()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
#endif
