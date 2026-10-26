#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

final class MemoryLaneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private let memoryLaneMenuBarIcon: NSImage = {
    let size = NSSize(width: 36, height: 36)
    let image = NSImage(size: size, flipped: false) { rect in
        NSColor.black.setStroke()

        let brain = NSBezierPath()
        brain.move(to: NSPoint(x: 18, y: 31))
        brain.curve(to: NSPoint(x: 10, y: 29), controlPoint1: NSPoint(x: 15, y: 34), controlPoint2: NSPoint(x: 11, y: 33))
        brain.curve(to: NSPoint(x: 5, y: 23), controlPoint1: NSPoint(x: 6, y: 29), controlPoint2: NSPoint(x: 4, y: 26))
        brain.curve(to: NSPoint(x: 6, y: 15), controlPoint1: NSPoint(x: 3, y: 20), controlPoint2: NSPoint(x: 3, y: 17))
        brain.curve(to: NSPoint(x: 12, y: 10), controlPoint1: NSPoint(x: 6, y: 12), controlPoint2: NSPoint(x: 9, y: 10))
        brain.curve(to: NSPoint(x: 18, y: 12), controlPoint1: NSPoint(x: 14, y: 8), controlPoint2: NSPoint(x: 17, y: 9))
        brain.move(to: NSPoint(x: 18, y: 31))
        brain.curve(to: NSPoint(x: 26, y: 29), controlPoint1: NSPoint(x: 21, y: 34), controlPoint2: NSPoint(x: 25, y: 33))
        brain.curve(to: NSPoint(x: 31, y: 23), controlPoint1: NSPoint(x: 30, y: 29), controlPoint2: NSPoint(x: 32, y: 26))
        brain.curve(to: NSPoint(x: 30, y: 15), controlPoint1: NSPoint(x: 33, y: 20), controlPoint2: NSPoint(x: 33, y: 17))
        brain.curve(to: NSPoint(x: 24, y: 10), controlPoint1: NSPoint(x: 30, y: 12), controlPoint2: NSPoint(x: 27, y: 10))
        brain.curve(to: NSPoint(x: 18, y: 12), controlPoint1: NSPoint(x: 22, y: 8), controlPoint2: NSPoint(x: 19, y: 9))
        brain.lineWidth = 2.8
        brain.lineCapStyle = .round
        brain.lineJoinStyle = .round
        brain.stroke()

        let road = NSBezierPath()
        road.move(to: NSPoint(x: 15, y: 28))
        road.curve(to: NSPoint(x: 22, y: 24), controlPoint1: NSPoint(x: 18, y: 27), controlPoint2: NSPoint(x: 23, y: 27))
        road.curve(to: NSPoint(x: 15, y: 19), controlPoint1: NSPoint(x: 21, y: 21), controlPoint2: NSPoint(x: 16, y: 22))
        road.curve(to: NSPoint(x: 21, y: 14), controlPoint1: NSPoint(x: 14, y: 16), controlPoint2: NSPoint(x: 20, y: 17))
        road.curve(to: NSPoint(x: 13, y: 5), controlPoint1: NSPoint(x: 22, y: 10), controlPoint2: NSPoint(x: 17, y: 8))
        road.lineWidth = 3.4
        road.lineCapStyle = .round
        road.lineJoinStyle = .round
        road.stroke()

        return true
    }
    image.isTemplate = true
    return image
}()

@main
struct MemoryLaneApp: App {
    @NSApplicationDelegateAdaptor(MemoryLaneAppDelegate.self) private var appDelegate

    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared

    init() {
        do {
            container = try ModelContainer(for: MemoryItem.self)
        } catch {
            fatalError("Unable to initialize Memory Lane database: \(error)")
        }
    }

    var body: some Scene {
        Window("Memory Lane", id: "main") {
            RootView()
                .environment(preferences)
                .modelContainer(container)
                .task {
                    MacCaptureCoordinator.shared.start(context: container.mainContext)
                }
        }
        .defaultSize(width: 1000, height: 700)

        MenuBarExtra {
            MemoryLaneMenuBarView(preferences: preferences)
        } label: {
            Image(nsImage: memoryLaneMenuBarIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .accessibilityLabel("Memory Lane")
        }
    }
}

private struct MemoryLaneMenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let preferences: RecallPreferences

    var body: some View {
        Button("Open Memory Lane") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button(preferences.capturePaused ? "Resume Capture" : "Pause Capture") {
            preferences.capturePaused.toggle()
        }

        Divider()

        Text(preferences.capturePaused ? "Capture paused" : "Capture active")
            .foregroundStyle(.secondary)

        Button("Quit Memory Lane") {
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
