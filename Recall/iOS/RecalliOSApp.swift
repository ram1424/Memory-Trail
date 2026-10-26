#if os(iOS)
import SwiftUI
import SwiftData

@main
struct RecallIOSApp: App {
    @State private var preferences = RecallPreferences.shared

    var body: some Scene {
        WindowGroup {
            IOSRootHost()
                .environment(preferences)
        }
        .modelContainer(for: MemoryItem.self)
    }
}

private struct IOSRootHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RootView()
            .task {
                IOSCaptureCoordinator.shared.captureSessionIfNeeded(context: modelContext)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    IOSCaptureCoordinator.shared.captureSessionIfNeeded(context: modelContext)
                }
            }
    }
}

@MainActor
final class IOSCaptureCoordinator {
    static let shared = IOSCaptureCoordinator()

    private let lastSessionKey = "recall.iOS.lastSessionCapture"
    private let minimumSessionInterval: TimeInterval = 60

    private init() {}

    func captureSessionIfNeeded(context: ModelContext) {
        let preferences = RecallPreferences.shared
        guard !preferences.capturePaused else { return }

        let defaults = UserDefaults.standard
        let lastCapture = defaults.object(forKey: lastSessionKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCapture) >= minimumSessionInterval else { return }

        #if targetEnvironment(simulator)
        let body = "Recall became active in the iPhone Simulator. This confirms that iOS capture and the local SwiftData timeline are working."
        #else
        let body = "Recall became active on this iPhone. iOS does not allow Recall to inspect activity inside other apps without an explicit share or user action."
        #endif

        let item = MemoryItem(
            title: "Recall session",
            body: body,
            sourceApp: "Recall",
            sourceBundleID: Bundle.main.bundleIdentifier ?? "",
            sourceKind: .appActivity
        )

        context.insert(item)
        do {
            try context.save()
            defaults.set(Date(), forKey: lastSessionKey)
        } catch {
            assertionFailure("Unable to save iOS Recall session: \(error)")
        }
    }
}
#endif
