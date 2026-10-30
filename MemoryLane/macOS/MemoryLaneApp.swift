#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

@main
struct MemoryLaneApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true


    private static let brandIcon: NSImage = {
        if let image = NSImage(named: "OnboardingIcon") {
            image.isTemplate = false
            return image
        }

        // Fallback only if the compiled asset can't be loaded.
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        image.isTemplate = false
        return image
    }()

    private static let dockIcon: NSImage = {
        let canvas = NSSize(width: 64, height: 64)
        let output = NSImage(size: canvas)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        // Standard macOS Dock icons leave visual breathing room inside the icon canvas.
        let visibleSize = CGFloat(54)
        let inset = (canvas.width - visibleSize) / 2
        brandIcon.draw(
            in: NSRect(x: inset, y: inset, width: visibleSize, height: visibleSize),
            from: NSRect(origin: .zero, size: brandIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        output.unlockFocus()
        output.isTemplate = false
        return output
    }()


    private static let menuBarIcon: NSImage = {
        let canvas = NSSize(width: 20, height: 20)
        let output = NSImage(size: canvas)
        output.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        let visibleSize = CGFloat(20)
        let inset = (canvas.width - visibleSize) / 2
        brandIcon.draw(
            in: NSRect(x: inset, y: inset, width: visibleSize, height: visibleSize),
            from: NSRect(origin: .zero, size: brandIcon.size),
            operation: .sourceOver,
            fraction: 1.0
        )

        output.unlockFocus()
        output.isTemplate = false
        return output
    }()

    init() {
        do {
            container = try ModelContainer(for: MemoryItem.self)
        } catch {
            fatalError("Unable to initialize Memory Lane database: \(error)")
        }

        NSApplication.shared.applicationIconImage = Self.dockIcon
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isLaunching {
                    startupView
                        .transition(.opacity.combined(with: .scale(scale: 0.985)))
                } else {
                    RootView()
                        .environment(preferences)
                        .modelContainer(container)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.28), value: isLaunching)
            .task {
                MacCaptureCoordinator.shared.start(context: container.mainContext)

                try? await Task.sleep(nanoseconds: 900_000_000)
                isLaunching = false
            }
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Memory Lane") {
                    showAboutPanel()
                }
            }
        }

        MenuBarExtra {
            Button(preferences.capturePaused ? "Resume Capture" : "Pause Capture") {
                preferences.capturePaused.toggle()
            }
            Divider()
            Text("Memory Lane is local-first")
                .foregroundStyle(.secondary)
            Button("Quit Memory Lane") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .renderingMode(.original)
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private func showAboutPanel() {
        let credits = NSAttributedString(
            string: "Created By: Roman Zakharov",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Memory Lane",
            .applicationIcon: Self.brandIcon,
            .applicationVersion: "Version \(Self.appVersion)",
            .version: "Build \(Self.buildNumber)",
            .credits: credits
        ])
    }

    private var startupView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(nsImage: Self.brandIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 112, height: 112)
                    .shadow(radius: 18, y: 8)

                VStack(spacing: 6) {
                    Text("Memory Lane")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))

                    Text("Preparing your timeline…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            .padding(40)
        }
    }
}
#endif
