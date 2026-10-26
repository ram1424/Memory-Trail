#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

final class MemoryLaneAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

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
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
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
