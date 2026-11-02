#if os(macOS)
import AppKit
import AVFoundation
import Darwin
import SwiftUI
import SwiftData

@main
struct MemoryTrailApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true

    private static let screenshotDemoSelection: SidebarItem? = {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--screenshot-demo=")
        }) else {
            return nil
        }

        switch String(argument.dropFirst("--screenshot-demo=".count)) {
        case "timeline":
            return .today
        case "ask":
            return .search
        case "favorites":
            return .favorites
        case "privacy":
            return .settings
        default:
            return nil
        }
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
            if Self.screenshotDemoSelection != nil {
                let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
                container = try ModelContainer(
                    for: MemoryItem.self,
                    configurations: configuration
                )
            } else {
                container = try ModelContainer(for: MemoryItem.self)
            }
        } catch {
            fatalError("Unable to initialize Memory Trail database: \(error)")
        }

        NSApplication.shared.applicationIconImage = Self.brandIcon
    }

    var body: some Scene {
        WindowGroup {
            if let selection = Self.screenshotDemoSelection {
                RootView(
                    initialSelection: selection,
                    forceMainInterface: true
                )
                .environment(preferences)
                .modelContainer(container)
                .preferredColorScheme(.light)
                .task {
                    MemoryTrailScreenshotDemo.seedDemoTimeline(
                        in: container.mainContext
                    )
                    await MemoryTrailScreenshotDemo.configureLiveWindow(for: selection)
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

                    let minimumSplashDuration: UInt64 = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                        ? 900_000_000
                        : 2_200_000_000
                    try? await Task.sleep(nanoseconds: minimumSplashDuration)
                    isLaunching = false
                }
            }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Memory Trail") {
                    showAboutPanel()
                }
            }
        }

        MenuBarExtra {
            Button(preferences.capturePaused ? "Resume Capture" : "Pause Capture") {
                preferences.capturePaused.toggle()
            }
            Divider()
            Text("Your activity stays on this Mac")
                .foregroundStyle(.secondary)
            Button("Quit Memory Trail") {
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
            .applicationName: "Memory Trail",
            .applicationIcon: Self.brandIcon,
            .applicationVersion: "Version \(Self.appVersion)",
            .version: "Build \(Self.buildNumber)",
            .credits: credits
        ])
    }

    private var startupView: some View {
        ZStack {
            Color(red: 0.025, green: 0.075, blue: 0.22)
                .ignoresSafeArea()

            if let animationURL = Bundle.main.url(
                forResource: "MemoryTrailLoading",
                withExtension: "mp4"
            ) {
                MemoryTrailLoadingAnimationView(url: animationURL)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(nsImage: Self.brandIcon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 112, height: 112)

                    Text("Memory Trail")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
        }
    }
}

private struct MemoryTrailLoadingAnimationView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> MemoryTrailLoadingPlayerView {
        let view = MemoryTrailLoadingPlayerView()
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        let looper = AVPlayerLooper(player: player, templateItem: item)
        context.coordinator.player = player
        context.coordinator.looper = looper
        view.playerLayer.player = player

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            player.seek(to: .zero)
        } else {
            player.play()
        }

        return view
    }

    func updateNSView(_ nsView: MemoryTrailLoadingPlayerView, context: Context) { }

    static func dismantleNSView(
        _ nsView: MemoryTrailLoadingPlayerView,
        coordinator: Coordinator
    ) {
        coordinator.player?.pause()
        nsView.playerLayer.player = nil
        coordinator.looper = nil
        coordinator.player = nil
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }
}

private final class MemoryTrailLoadingPlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(
            calibratedRed: 0.025,
            green: 0.075,
            blue: 0.22,
            alpha: 1
        ).cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}



@MainActor
private enum MemoryTrailScreenshotDemo {
    private static let standardDemoSize = NSSize(width: 1440, height: 980)
    private static let settingsDemoSize = NSSize(width: 1440, height: 1020)

    static func seedDemoTimeline(in context: ModelContext) {
        let descriptor = FetchDescriptor<MemoryItem>()
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return
        }

        let now = Date()
        let demoItems = [
            MemoryItem(
                createdAt: now.addingTimeInterval(-2 * 60),
                title: "Chat with Alex Morgan, Priya Shah, and Jordan Lee",
                sourceApp: "Microsoft Teams",
                sourceBundleID: "com.microsoft.teams2",
                sourceKind: .appActivity,
                isFavorite: true
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
                sourceURL: "https://example.com/docs",
                isFavorite: true
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
            )
        ]

        for item in demoItems {
            context.insert(item)
        }

        try? context.save()
    }

    static func configureLiveWindow(for selection: SidebarItem) async {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)

        let size = selection == .settings
            ? settingsDemoSize
            : standardDemoSize

        for _ in 0..<20 {
            if let window = NSApplication.shared.windows.first(where: {
                $0.contentView != nil
            }) {
                window.setContentSize(size)
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApplication.shared.activate(ignoringOtherApps: true)
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

#endif
