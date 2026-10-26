#if os(iOS)
import SwiftUI
import SwiftData

@main
struct RecallIOSApp: App {
    @State private var preferences = RecallPreferences.shared
    private let container: ModelContainer

    init() {
        do {
            container = try RecallSharedStore.makeContainer()
        } catch {
            fatalError("Unable to initialize Recall shared database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RecallIOSRoot()
                .environment(preferences)
        }
        .modelContainer(container)
    }
}

private struct RecallIOSRoot: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootView()
            .task {
                RecallSharedStore.importPendingItems(into: modelContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    RecallSharedStore.importPendingItems(into: modelContext)
                }
            }
    }
}
#endif
