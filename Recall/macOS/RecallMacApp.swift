#if os(macOS)
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
}
#endif
