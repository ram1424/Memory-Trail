#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

enum MemoryTrailStorage {
    static let retentionDays = 30

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    }

    static var directoryURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Memory Trails", isDirectory: true)
    }

    static var storeURL: URL {
        directoryURL.appendingPathComponent("MemoryTrail.store")
    }

    private static var previousNamedStoreURL: URL {
        applicationSupportDirectory
            .appendingPathComponent("Memory Trail", isDirectory: true)
            .appendingPathComponent("MemoryTrail.store")
    }

    static func preparePersistentStore() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(atPath: storeURL.path),
              fileManager.fileExists(atPath: previousNamedStoreURL.path)
        else {
            return
        }

        for suffix in ["", "-shm", "-wal"] {
            let source = URL(
                fileURLWithPath: previousNamedStoreURL.path + suffix
            )
            let destination = URL(
                fileURLWithPath: storeURL.path + suffix
            )

            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path)
            else {
                continue
            }

            try fileManager.moveItem(at: source, to: destination)
        }
    }
}

@main
struct MemoryTrailAppStore: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var showWhatsNew = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("memoryTrail.appStore.lastWhatsNewVersion") private var lastWhatsNewVersion = ""

    private static var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.4"
    }

    private static var appBuild: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "1"
    }

    private static var displayVersion: String {
        "\(appVersion) • Build \(appBuild)"
    }

    init() {
        do {
            try MemoryTrailStorage.preparePersistentStore()
            let configuration = ModelConfiguration(
                "MemoryTrail",
                url: MemoryTrailStorage.storeURL
            )
            container = try ModelContainer(
                for: MemoryItem.self,
                configurations: configuration
            )
        } catch {
            fatalError("Unable to initialize Memory Trails database: \(error)")
        }

        NSApplication.shared.applicationIconImage =
            NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .modelContainer(container)
                .task {
                    MacCaptureCoordinator.shared.start(
                        context: container.mainContext
                    )
                    pruneExpiredHistory()

                    if hasCompletedOnboarding {
                        presentWhatsNewIfNeeded()
                    }
                }
                .onChange(of: hasCompletedOnboarding) { _, completed in
                    if completed {
                        presentWhatsNewIfNeeded()
                    }
                }
                .sheet(isPresented: $showWhatsNew) {
                    AppStoreWhatsNewView(version: Self.displayVersion)
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Memory Trails") {
                    showAboutPanel()
                }

                Divider()

                Button("What’s New in Memory Trails…") {
                    showWhatsNew = true
                }
            }
        }

        MenuBarExtra {
            Button(
                preferences.capturePaused
                    ? "Resume Capture"
                    : "Pause Capture"
            ) {
                preferences.capturePaused.toggle()
            }

            Divider()

            Text("App Store Edition • Local Only")
                .foregroundStyle(.secondary)

            Button("Quit Memory Trails") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(
                systemName: preferences.capturePaused
                    ? "pause.circle.fill"
                    : "clock.arrow.circlepath"
            )
        }
    }

    @MainActor
    private func presentWhatsNewIfNeeded() {
        let identity = Self.displayVersion
        guard lastWhatsNewVersion != identity else { return }
        lastWhatsNewVersion = identity
        showWhatsNew = true
    }

    @MainActor
    private func pruneExpiredHistory() {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -MemoryTrailStorage.retentionDays,
            to: Date()
        ) else { return }

        do {
            let items = try container.mainContext.fetch(
                FetchDescriptor<MemoryItem>()
            )
            for item in items where item.createdAt < cutoff {
                container.mainContext.delete(item)
            }
            try container.mainContext.save()
        } catch {
            NSLog(
                "Memory Trails retention cleanup failed: %@",
                error.localizedDescription
            )
        }
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Created By: Roman Zakharov\nMac App Store Edition",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Memory Trails",
            .applicationIcon: NSWorkspace.shared.icon(
                forFile: Bundle.main.bundlePath
            ),
            .applicationVersion:
                "Version \(Self.appVersion) • Build \(Self.appBuild)",
            .version: "",
            .credits: credits
        ])
    }
}

private struct AppStoreWhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 34))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Memory Trails \(version)")
                        .font(.title2.bold())
                    Text("Mac App Store Edition")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            section(
                icon: "app.badge",
                title: "Sandbox-safe activity capture",
                text:
                    "Records application switches using standard macOS workspace notifications without inspecting other apps through Accessibility APIs."
            )

            section(
                icon: "doc.on.clipboard",
                title: "Optional clipboard history",
                text:
                    "Copied text can be remembered locally when you explicitly enable Clipboard Capture in Settings."
            )

            section(
                icon: "sparkles.rectangle.stack",
                title: "Core Memory Trails tools",
                text:
                    "Today, Insights, Ask Memory Trails, Favorites, manual memories, local retention, and JSON export remain available."
            )

            section(
                icon: "lock.shield.fill",
                title: "Private by design",
                text:
                    "Runs inside App Sandbox. Captured history stays in the local app container and updates come from the Mac App Store."
            )

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620)
    }

    private func section(
        icon: String,
        title: String,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}
#endif
