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
            RootView()
                .environment(preferences)
        }
        .modelContainer(container)
    }
}
#endif
