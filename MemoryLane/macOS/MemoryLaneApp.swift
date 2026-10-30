#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

@main
struct MemoryLaneApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true

    private static let screenshotOutputDirectory: URL? = {
        let prefix = "--export-screenshots="
        guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }

        let path = String(argument.dropFirst(prefix.count))
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()


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
            if Self.screenshotOutputDirectory != nil {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(
                    for: MemoryItem.self,
                    configurations: configuration
                )
            } else {
                container = try ModelContainer(for: MemoryItem.self)
            }
        } catch {
            fatalError("Unable to initialize Memory Lane database: \(error)")
        }

        NSApplication.shared.applicationIconImage = Self.dockIcon
    }

    var body: some Scene {
        WindowGroup {
            if let outputDirectory = Self.screenshotOutputDirectory {
                Color(nsColor: .windowBackgroundColor)
                    .frame(width: 1, height: 1)
                    .task {
                        do {
                            try await MemoryLaneScreenshotExporter.export(
                                to: outputDirectory,
                                container: container,
                                preferences: preferences
                            )
                        } catch {
                            fputs("Screenshot export failed: \(error)\n", stderr)
                        }

                        NSApplication.shared.terminate(nil)
                    }
            } else {
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

@MainActor
private enum MemoryLaneScreenshotExporter {
    private static let size = NSSize(width: 1440, height: 900)

    static func export(
        to directory: URL,
        container: ModelContainer,
        preferences: RecallPreferences
    ) async throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        seedDemoTimeline(in: container.mainContext)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)

        let screenshots: [(String, AnyView)] = [
            (
                "timeline.png",
                AnyView(
                    RootView(initialSelection: .timeline, forceMainInterface: true)
                        .environment(preferences)
                        .modelContainer(container)
                        .preferredColorScheme(.light)
                )
            ),
            (
                "ask-memory-lane.png",
                AnyView(
                    RootView(initialSelection: .search, forceMainInterface: true)
                        .environment(preferences)
                        .modelContainer(container)
                        .preferredColorScheme(.light)
                )
            ),
            (
                "privacy-general.png",
                AnyView(
                    RootView(initialSelection: .settings, forceMainInterface: true)
                        .environment(preferences)
                        .modelContainer(container)
                        .preferredColorScheme(.light)
                )
            )
        ]

        for (filename, view) in screenshots {
            try await render(
                view,
                to: directory.appendingPathComponent(filename)
            )
        }
    }

    private static func seedDemoTimeline(in context: ModelContext) {
        let now = Date()
        let demoItems = [
            MemoryItem(
                createdAt: now.addingTimeInterval(-2 * 60),
                title: "Chat with Alex Morgan, Priya Shah, and Jordan Lee",
                sourceApp: "Microsoft Teams",
                sourceBundleID: "com.microsoft.teams2",
                sourceKind: .appActivity
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-16 * 60),
                title: "Quarterly planning update",
                body: "From: Jordan Lee",
                sourceApp: "Microsoft Outlook",
                sourceBundleID: "com.microsoft.outlook",
                sourceKind: .appActivity,
                isFavorite: true
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-31 * 60),
                title: "Product documentation",
                sourceApp: "Safari",
                sourceBundleID: "com.apple.Safari",
                sourceKind: .appActivity,
                sourceURL: "https://example.com/docs"
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-47 * 60),
                title: "Budget Forecast.xlsx",
                sourceApp: "Microsoft Excel",
                sourceBundleID: "com.microsoft.Excel",
                sourceKind: .appActivity
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-64 * 60),
                title: "Project Assets",
                sourceApp: "Finder",
                sourceBundleID: "com.apple.finder",
                sourceKind: .file,
                sourceURL: "/Users/demo/Documents/Project Assets"
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-78 * 60),
                title: "Copied text",
                body: "Follow up on the project review notes",
                sourceApp: "Clipboard",
                sourceKind: .clipboard
            ),
            MemoryItem(
                createdAt: now.addingTimeInterval(-102 * 60),
                title: "Release Notes",
                sourceApp: "Preview",
                sourceBundleID: "com.apple.Preview",
                sourceKind: .appActivity
            )
        ]

        for item in demoItems {
            context.insert(item)
        }

        try? context.save()
    }

    private static func render(
        _ view: AnyView,
        to url: URL
    ) async throws {
        let framedView = AnyView(
            view
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )

        let hostingController = NSHostingController(rootView: framedView)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.orderFrontRegardless()

        try await Task.sleep(nanoseconds: 650_000_000)

        guard let contentView = window.contentView else {
            window.close()
            throw ScreenshotExportError.missingContentView
        }

        contentView.layoutSubtreeIfNeeded()

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            window.close()
            throw ScreenshotExportError.unableToCreateBitmap
        }

        contentView.cacheDisplay(in: bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            window.close()
            throw ScreenshotExportError.unableToEncodePNG
        }

        try png.write(to: url, options: .atomic)
        window.orderOut(nil)
        window.close()
    }

    private enum ScreenshotExportError: Error {
        case missingContentView
        case unableToCreateBitmap
        case unableToEncodePNG
    }
}

#endif
