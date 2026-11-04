#if os(macOS)
import AppKit
import Darwin
import Foundation
import SwiftUI
import SwiftData

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
            .appendingPathComponent("Memory Trail", isDirectory: true)
    }

    static var storeURL: URL {
        directoryURL.appendingPathComponent("MemoryTrail.store")
    }

    private static var legacyStoreURL: URL {
        applicationSupportDirectory.appendingPathComponent("default.store")
    }

    static func preparePersistentStore() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(atPath: storeURL.path),
              fileManager.fileExists(atPath: legacyStoreURL.path)
        else {
            return
        }

        for suffix in ["", "-shm", "-wal"] {
            let source = URL(fileURLWithPath: legacyStoreURL.path + suffix)
            let destination = URL(fileURLWithPath: storeURL.path + suffix)

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
struct MemoryTrailApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true
    @State private var splashProgress = 0.02
    @State private var updatePresentation: MemoryTrailUpdatePresentation?
    @State private var isCheckingForUpdates = false
    @State private var isInstallingUpdate = false
    @State private var showAccessibilityPrompt = false
    @State private var didPromptAccessibilityThisLaunch = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("memoryTrail.lastPresentedWhatsNewRelease") private var lastPresentedWhatsNewRelease = ""
    @AppStorage("memoryTrail.lastUpdateCheckEpoch") private var lastUpdateCheckEpoch = 0.0
    @AppStorage("memoryTrail.remindUpdateAfterEpoch") private var remindUpdateAfterEpoch = 0.0
    @AppStorage("memoryTrail.skippedUpdateVersion") private var skippedUpdateVersion = ""

    private static let screenshotDemoSelection: SidebarItem? = {
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--screenshot-demo=")
        }) else {
            return nil
        }

        switch String(argument.dropFirst("--screenshot-demo=".count)) {
        case "timeline":
            return .today
        case "insights":
            return .insights
        case "ask":
            return .search
        case "clipboard":
            return .clipboard
        case "favorites":
            return .favorites
        case "settings", "privacy":
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
                try MemoryTrailStorage.preparePersistentStore()
                let configuration = ModelConfiguration(
                    "MemoryTrail",
                    url: MemoryTrailStorage.storeURL
                )
                container = try ModelContainer(
                    for: MemoryItem.self,
                    configurations: configuration
                )
            }
        } catch {
            fatalError("Unable to initialize Memory Trail database: \(error)")
        }

        NSApplication.shared.applicationIconImage = Self.brandIcon
    }

    var body: some Scene {
        WindowGroup {
            Group {
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
                    await launchAndMonitorUpdates()
                }
            }
            }
            .sheet(item: $updatePresentation) { presentation in
                MemoryTrailUpdateSheet(
                    presentation: presentation,
                    icon: Self.brandIcon,
                    currentVersion: Self.displayVersion,
                    isInstallingUpdate: isInstallingUpdate,
                    onUpdate: { manifest in
                        updatePresentation = nil
                        beginBackgroundUpdate(manifest)
                    },
                    onRemindTomorrow: { manifest in
                        remindUpdateAfterEpoch = Date().addingTimeInterval(24 * 60 * 60).timeIntervalSince1970
                        if skippedUpdateVersion == manifest.identity {
                            skippedUpdateVersion = ""
                        }
                        updatePresentation = nil
                        refreshAccessibilityAndPromptIfNeeded()
                    },
                    onSkipVersion: { manifest in
                        skippedUpdateVersion = manifest.identity
                        remindUpdateAfterEpoch = 0
                        updatePresentation = nil
                        refreshAccessibilityAndPromptIfNeeded()
                    },
                    onOpenReleases: {
                        if let url = URL(string: "https://github.com/ram1424/Memory-Trail/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                        updatePresentation = nil
                        refreshAccessibilityAndPromptIfNeeded()
                    },
                    onDismiss: {
                        updatePresentation = nil
                        refreshAccessibilityAndPromptIfNeeded()
                    }
                )
            }
            .sheet(isPresented: $showAccessibilityPrompt) {
                MemoryTrailAccessibilityPrompt(
                    onOpenSettings: {
                        MacCaptureCoordinator.shared.requestAccessibilityPermission()
                        MacCaptureCoordinator.shared.openAccessibilitySettings()
                        showAccessibilityPrompt = false
                    },
                    onNotNow: {
                        showAccessibilityPrompt = false
                    }
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .memoryTrailCheckForUpdates)) { _ in
                Task {
                    await checkForUpdates(manual: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                MacCaptureCoordinator.shared.refreshAccessibilityStatus()
                if MacCaptureCoordinator.shared.hasAccessibilityPermission {
                    showAccessibilityPrompt = false
                } else {
                    refreshAccessibilityAndPromptIfNeeded()
                }
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                guard completed, Self.screenshotDemoSelection == nil else { return }
                Task {
                    await checkForUpdates(manual: false)
                    refreshAccessibilityAndPromptIfNeeded()
                    if updatePresentation == nil, !showAccessibilityPrompt {
                        await presentWhatsNewIfNeeded()
                    }
                }
            }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Memory Trail") {
                    showAboutPanel()
                }

                Divider()

                Button(isCheckingForUpdates ? "Checking for Updates…" : "Check for Updates…") {
                    Task {
                        await checkForUpdates(manual: true)
                    }
                }
                .disabled(isCheckingForUpdates)

                Button("What’s New in Memory Trail…") {
                    updatePresentation = .whatsNew(Self.currentChangelog)
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.4"
    }

    private static var appBuild: Int {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return Int(value) ?? 0
    }

    private static var displayVersion: String {
        "\(appVersion) • Build \(appBuild)"
    }

    private static var releaseIdentity: String {
        "\(appVersion)-build-\(appBuild)"
    }

    private static var currentChangelog: MemoryTrailChangelog {
        MemoryTrailChangelog(
            version: displayVersion,
            headline: "More Control Over Your Trail",
            summary: "Memory Trail \(appVersion) makes local history easier to manage, export, retain, and navigate while keeping everything on your Mac.",
            sections: [
                MemoryTrailChangeSection(
                    title: "Freshest Trail, Reimagined",
                    symbol: "checkmark.seal.fill",
                    items: [
                        "The up-to-date screen now uses a full illustrated Memory Trail landscape with mountains, trees, sunrise, and a winding path.",
                        "A laptop and success badge make the current-release state feel more celebratory while keeping the real version and build visible.",
                        "Keep Exploring remains the one-click way back into the app."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Settings, Repacked",
                    symbol: "rectangle.grid.1x2.fill",
                    items: [
                        "Settings now flows in a continuous card stack with no dead column space.",
                        "Excluded Apps, Storage & History, and Privacy are positioned higher for quicker access.",
                        "Updates and Help now live at the bottom of the page."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Exported with Style",
                    symbol: "square.and.arrow.up.fill",
                    items: [
                        "JSON exports now finish with a polished Memory Trail success screen.",
                        "The export receipt shows the real filename, item count, file size, and a Show in Finder shortcut.",
                        "Your trail. Your data. Your file."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Cleanup with a Smile",
                    symbol: "sparkles",
                    items: [
                        "History cleanup now uses playful, visual confirmation sheets for the last week, last month, and full-history reset.",
                        "The Today activity-feed clear action uses the same friendly full-reset experience."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Storage & History",
                    symbol: "internaldrive.fill",
                    items: [
                        "Activity now uses a clearly named local MemoryTrail.store inside Memory Trail’s Application Support folder.",
                        "Export your locally stored activity history as a readable JSON file from Settings.",
                        "History is retained locally for 30 days by default, with controls to clear the last week, last month, or all history."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Jump Back to Today",
                    symbol: "calendar.badge.clock",
                    items: [
                        "When browsing earlier dates, a Go to Today control returns you to the present day in one click.",
                        "Date navigation remains available for retracing earlier activity."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Today, Reorganized",
                    symbol: "calendar",
                    items: [
                        "Today now opens with a full-width at-a-glance summary for activities, apps used, active time, files and documents, and clipboard items.",
                        "The timeline is now the most prominent part of the page, with clearer hierarchy and category-colored activity markers.",
                        "Date navigation and activity filtering are consolidated into the redesigned Today experience."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Useful Context Beside the Timeline",
                    symbol: "rectangle.split.2x1.fill",
                    items: [
                        "Top Apps Today highlights the apps that received the most observed activity.",
                        "Key Takeaways surfaces peak focus, top work type, and app-switching context.",
                        "Recent Files & Documents keeps recently observed work easy to reopen."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "A Consistent Experience",
                    symbol: "rectangle.3.group.fill",
                    items: [
                        "Insights now uses a balanced dashboard grid with consistent card sizes and spacing.",
                        "Ask Memory Trail, Clipboard History, Settings, and Favorites now share the same structured headers, cards, spacing, and filter-inspired color system.",
                        "Favorites now makes starring activity feel intentional, with clearer saved-item context and a more welcoming empty state."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Privacy Remains Local",
                    symbol: "lock.shield.fill",
                    items: [
                        "The redesigned views continue to use only locally captured Memory Trail history.",
                        "No external data connectors, cloud timeline processing, or AI scraping were added.",
                        "Passwords and Wallet remain excluded by default, with existing capture and exclusion controls preserved."
                    ]
                )
            ]
        )
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
            .credits: credits
        ])
    }

    private var startupView: some View {
        MemoryTrailSimpleSplashView(
            icon: Self.brandIcon,
            progress: splashProgress
        )
    }

    @MainActor
    private func runStartupSequence() async {
        let startupBeganAt = Date()
        let minimumSplashDuration: TimeInterval = 1.5

        splashProgress = 0.02
        withAnimation(.linear(duration: 1.35)) {
            splashProgress = 1.0
        }

        // Verify the local SwiftData store is ready before capture starts.
        _ = try? container.mainContext.fetchCount(FetchDescriptor<MemoryItem>())

        MacCaptureCoordinator.shared.start(context: container.mainContext)

        // Warm the same local data path used by the Today view.
        var warmupDescriptor = FetchDescriptor<MemoryItem>()
        warmupDescriptor.fetchLimit = 32
        _ = try? container.mainContext.fetch(warmupDescriptor)

        await Task.yield()

        // Keep the simple animated splash visible for its full 1.5-second run.
        let elapsed = Date().timeIntervalSince(startupBeganAt)
        let remaining = max(0, minimumSplashDuration - elapsed)
        if remaining > 0 {
            try? await Task.sleep(
                nanoseconds: UInt64(remaining * 1_000_000_000)
            )
        }

        splashProgress = 1.0
        isLaunching = false
    }

    @MainActor
    private func launchAndMonitorUpdates() async {
        await runStartupSequence()
        await maximizeWindowOnLaunch()

        Self.pruneExpiredHistory(in: container.mainContext)

        // Check for a newer release on every normal app launch.
        await checkForUpdates(manual: false)

        // Refresh the current macOS Accessibility trust state every launch.
        refreshAccessibilityAndPromptIfNeeded()

        if hasCompletedOnboarding,
           updatePresentation == nil,
           !showAccessibilityPrompt {
            await presentWhatsNewIfNeeded()
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            Self.pruneExpiredHistory(in: container.mainContext)
            await performAutomaticUpdateCheckIfNeeded()
        }
    }

    @MainActor
    private static func pruneExpiredHistory(in context: ModelContext) {
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -MemoryTrailStorage.retentionDays,
            to: Date()
        ) else {
            return
        }

        do {
            let items = try context.fetch(FetchDescriptor<MemoryItem>())
            let expired = items.filter { $0.createdAt < cutoff }

            guard !expired.isEmpty else { return }

            for item in expired {
                context.delete(item)
            }

            try context.save()
        } catch {
            NSLog("Memory Trail retention cleanup failed: %@", error.localizedDescription)
        }
    }

    @MainActor
    private func refreshAccessibilityAndPromptIfNeeded() {
        let capture = MacCaptureCoordinator.shared
        capture.refreshAccessibilityStatus()

        guard Self.screenshotDemoSelection == nil,
              hasCompletedOnboarding,
              !capture.hasAccessibilityPermission,
              !didPromptAccessibilityThisLaunch,
              updatePresentation == nil
        else {
            return
        }

        didPromptAccessibilityThisLaunch = true
        showAccessibilityPrompt = true
    }

    @MainActor
    private func maximizeWindowOnLaunch() async {
        guard Self.screenshotDemoSelection == nil else { return }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Wait until SwiftUI/AppKit has presented the main app window, then
        // expand it to the screen's visible work area every time the app launches.
        // This keeps Memory Trail as a normal macOS window and does not enter
        // native full-screen mode or create a separate full-screen Space.
        for _ in 0..<20 {
            if let window = NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.level == .normal && $0.canBecomeKey
                }) {
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }

                window.makeKeyAndOrderFront(nil)

                if let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true, animate: true)
                }

                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    @MainActor
    private func presentWhatsNewIfNeeded() async {
        guard hasCompletedOnboarding,
              lastPresentedWhatsNewRelease != Self.releaseIdentity,
              updatePresentation == nil
        else {
            return
        }

        try? await Task.sleep(nanoseconds: 350_000_000)
        guard updatePresentation == nil else { return }

        lastPresentedWhatsNewRelease = Self.releaseIdentity
        updatePresentation = .whatsNew(Self.currentChangelog)
    }

    @MainActor
    private func performAutomaticUpdateCheckIfNeeded() async {
        let now = Date().timeIntervalSince1970
        let sixHours: TimeInterval = 6 * 60 * 60

        guard now - lastUpdateCheckEpoch >= sixHours,
              updatePresentation == nil
        else {
            return
        }

        await checkForUpdates(manual: false)
    }

    @MainActor
    private func checkForUpdates(manual: Bool) async {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        let now = Date().timeIntervalSince1970
        lastUpdateCheckEpoch = now

        do {
            let manifest = try await MemoryTrailUpdateService.fetchLatest()
            if MemoryTrailUpdateService.isNewer(
                manifest,
                thanVersion: Self.appVersion,
                currentBuild: Self.appBuild
            ) {
                if !manual {
                    if skippedUpdateVersion == manifest.identity {
                        return
                    }

                    if remindUpdateAfterEpoch > now {
                        return
                    }
                }

                if skippedUpdateVersion != manifest.identity {
                    skippedUpdateVersion = ""
                }
                if remindUpdateAfterEpoch <= now {
                    remindUpdateAfterEpoch = 0
                }

                updatePresentation = .updateAvailable(manifest)
            } else if manual {
                updatePresentation = .upToDate(Self.displayVersion)
            }
        } catch {
            guard manual else { return }
            updatePresentation = .unavailable(
                "Memory Trail couldn’t reach the update service. Check your connection and try again, or open Releases to download the latest version manually."
            )
        }
    }

    @MainActor
    private func beginBackgroundUpdate(_ manifest: MemoryTrailUpdateManifest) {
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true

        Task {
            do {
                try await MemoryTrailBackgroundUpdater.downloadInstallAndRelaunch(manifest)
            } catch {
                isInstallingUpdate = false
                updatePresentation = .unavailable(
                    "The update could not be installed automatically. Your current copy of Memory Trail is unchanged. You can open Releases and install the update manually."
                )
            }
        }
    }
}

private struct MemoryTrailSimpleSplashView: View {
    let icon: NSImage
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            SwiftUI.TimelineView(.animation) { timeline in
                let size = geometry.size
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let waveShift = reduceMotion ? 0 : CGFloat(sin(time * 0.90) * 8)
                let secondWaveShift = reduceMotion ? 0 : CGFloat(cos(time * 0.72) * 10)
                let iconScale: CGFloat = reduceMotion
                    ? 1.0
                    : CGFloat(1.0 + (sin(time * 1.75) * 0.012))
                let glowOpacity = reduceMotion ? 0.16 : 0.14 + (sin(time * 1.45) + 1) * 0.035
                let contentWidth = min(760.0, max(520.0, size.width * 0.58))
                let iconSize = min(166.0, max(122.0, size.width * 0.115))
                let titleSize = min(66.0, max(46.0, size.width * 0.046))

                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.91, green: 0.97, blue: 1.00),
                            Color.white,
                            Color(red: 0.94, green: 0.98, blue: 1.00)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.36),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: min(size.width, size.height) * 0.64
                    )

                    MemoryTrailSplashWaveShape(edge: .topLeading)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.55, blue: 0.98).opacity(0.68),
                                    Color(red: 0.40, green: 0.78, blue: 1.00).opacity(0.38),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: waveShift, y: -4)

                    MemoryTrailSplashWaveShape(edge: .topLeading, secondary: true)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.36, green: 0.72, blue: 1.00).opacity(0.34),
                                    Color(red: 0.75, green: 0.91, blue: 1.00).opacity(0.10),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: -secondWaveShift, y: 5)

                    MemoryTrailSplashWaveShape(edge: .bottomTrailing)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(red: 0.30, green: 0.72, blue: 1.00).opacity(0.30),
                                    Color(red: 0.08, green: 0.48, blue: 0.96).opacity(0.68)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: secondWaveShift, y: 2)

                    MemoryTrailSplashWaveShape(edge: .bottomTrailing, secondary: true)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(red: 0.48, green: 0.82, blue: 1.00).opacity(0.26),
                                    Color(red: 0.22, green: 0.63, blue: 0.99).opacity(0.46)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .offset(x: -waveShift, y: -5)

                    VStack(spacing: 0) {
                        Spacer(minLength: 42)

                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(glowOpacity))
                                .frame(width: iconSize * 1.42, height: iconSize * 1.42)
                                .blur(radius: 28)

                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(width: iconSize, height: iconSize)
                                .scaleEffect(iconScale)
                                .shadow(color: Color.blue.opacity(0.18), radius: 18, y: 8)
                        }

                        HStack(spacing: 12) {
                            Text("Memory")
                                .foregroundStyle(Color(red: 0.035, green: 0.17, blue: 0.42))

                            Text("Trail")
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.04, green: 0.42, blue: 0.96),
                                            Color(red: 0.08, green: 0.62, blue: 1.00)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .font(.system(size: titleSize, weight: .bold, design: .rounded))
                        .tracking(-1.2)
                        .padding(.top, 18)

                        Text("YOUR DIGITAL ACTIVITY, ORGANIZED")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .tracking(6.0)
                            .foregroundStyle(Color(red: 0.32, green: 0.38, blue: 0.49))
                            .padding(.top, 12)

                        Spacer()
                            .frame(height: min(64, max(38, size.height * 0.065)))

                        Text("Loading Memory Trail…")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.29, green: 0.36, blue: 0.47))
                            .padding(.bottom, 18)

                        MemoryTrailSplashProgressBar(progress: progress)
                            .frame(width: contentWidth, height: 24)

                        Spacer(minLength: 70)
                    }
                    .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .background(Color(red: 0.94, green: 0.98, blue: 1.00))
        .ignoresSafeArea()
    }
}

private struct MemoryTrailSplashProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clamped = CGFloat(min(max(progress, 0), 1))
            let fillWidth = max(height, width * clamped)
            let beadSize = max(12.0, height * 0.72)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.78, green: 0.85, blue: 0.91).opacity(0.48))
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.92), lineWidth: 2)
                    }
                    .shadow(color: Color.blue.opacity(0.08), radius: 8, y: 3)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.38, blue: 0.98),
                                Color(red: 0.00, green: 0.72, blue: 0.98),
                                Color(red: 0.20, green: 0.88, blue: 1.00)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)
                    .shadow(color: Color.cyan.opacity(0.34), radius: 10)

                Circle()
                    .fill(Color.white.opacity(0.98))
                    .frame(width: beadSize, height: beadSize)
                    .shadow(color: Color.cyan.opacity(0.70), radius: 11)
                    .offset(
                        x: max(
                            (height - beadSize) / 2,
                            min(
                                width - beadSize - (height - beadSize) / 2,
                                fillWidth - beadSize - (height - beadSize) / 2
                            )
                        )
                    )
            }
        }
        .animation(.linear(duration: 0.08), value: progress)
    }
}

private struct MemoryTrailSplashWaveShape: Shape {
    enum Edge {
        case topLeading
        case bottomTrailing
    }

    let edge: Edge
    var secondary = false

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch edge {
        case .topLeading:
            let depth = secondary ? rect.height * 0.33 : rect.height * 0.26
            let reach = secondary ? rect.width * 0.48 : rect.width * 0.40

            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: reach, y: 0))
            path.addCurve(
                to: CGPoint(x: 0, y: depth),
                control1: CGPoint(x: reach * 0.72, y: rect.height * 0.04),
                control2: CGPoint(x: rect.width * 0.13, y: depth * 0.86)
            )
            path.closeSubpath()

        case .bottomTrailing:
            let depth = secondary ? rect.height * 0.32 : rect.height * 0.26
            let reach = secondary ? rect.width * 0.54 : rect.width * 0.46

            path.move(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width - reach, y: rect.height))
            path.addCurve(
                to: CGPoint(x: rect.width, y: rect.height - depth),
                control1: CGPoint(x: rect.width - reach * 0.70, y: rect.height - rect.height * 0.03),
                control2: CGPoint(x: rect.width - rect.width * 0.13, y: rect.height - depth * 0.88)
            )
            path.closeSubpath()
        }

        return path
    }
}


private struct MemoryTrailChangeSection: Codable, Hashable, Identifiable {
    let title: String
    let symbol: String
    let items: [String]

    var id: String { "\(symbol)-\(title)" }
}

private struct MemoryTrailChangelog: Hashable {
    let version: String
    let headline: String
    let summary: String
    let sections: [MemoryTrailChangeSection]
}

private struct MemoryTrailUpdateManifest: Decodable, Hashable {
    let version: String
    let build: Int?
    let publishedAt: String?
    let downloadURL: String
    let releaseURL: String
    let highlights: [String]
    let changelog: [MemoryTrailChangeSection]

    var identity: String {
        "\(version)-build-\(build ?? 0)"
    }

    var displayVersion: String {
        if let build {
            return "\(version) • Build \(build)"
        }
        return version
    }
}

private enum MemoryTrailUpdatePresentation: Identifiable {
    case whatsNew(MemoryTrailChangelog)
    case updateAvailable(MemoryTrailUpdateManifest)
    case upToDate(String)
    case unavailable(String)

    var id: String {
        switch self {
        case .whatsNew(let changelog):
            return "whats-new-\(changelog.version)"
        case .updateAvailable(let manifest):
            return "update-\(manifest.identity)"
        case .upToDate(let version):
            return "up-to-date-\(version)"
        case .unavailable:
            return "update-unavailable"
        }
    }
}

private enum MemoryTrailUpdateService {
    private static let githubLatestReleaseURL = URL(
        string: "https://api.github.com/repos/ram1424/Memory-Trail/releases/latest"
    )!

    private static let manifestURLs = [
        URL(string: "https://raw.githubusercontent.com/ram1424/Memory-Trail/main/docs/update.json")!,
        URL(string: "https://ram1424.github.io/Memory-Trail/update.json")!
    ]

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let html_url: String
        let published_at: String?
        let assets: [GitHubReleaseAsset]
    }

    private struct GitHubReleaseAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    static func fetchLatest() async throws -> MemoryTrailUpdateManifest {
        do {
            return try await fetchLatestGitHubRelease()
        } catch {
            return try await fetchManifestFallback()
        }
    }

    private static func fetchLatestGitHubRelease() async throws -> MemoryTrailUpdateManifest {
        var request = URLRequest(
            url: githubLatestReleaseURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(
            "MemoryTrail/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v")
            ? String(release.tag_name.dropFirst())
            : release.tag_name

        guard let dmg = release.assets.first(where: {
            $0.name.lowercased().hasSuffix(".dmg")
        }) else {
            throw URLError(.fileDoesNotExist)
        }

        let highlights = release.body?
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("- ") }
            .prefix(8)
            .map { String($0.dropFirst(2)) }
            ?? []

        return MemoryTrailUpdateManifest(
            version: version,
            build: buildNumber(from: release.name) ?? buildNumber(from: release.body),
            publishedAt: release.published_at,
            downloadURL: dmg.browser_download_url,
            releaseURL: release.html_url,
            highlights: highlights,
            changelog: []
        )
    }

    private static func buildNumber(from text: String?) -> Int? {
        guard let text,
              let expression = try? NSRegularExpression(
                pattern: #"(?i)\bbuild\s*[:#-]?\s*(\d+)\b"#
              )
        else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return Int(text[numberRange])
    }

    private static func fetchManifestFallback() async throws -> MemoryTrailUpdateManifest {
        var lastError: Error = URLError(.badServerResponse)

        for manifestURL in manifestURLs {
            do {
                var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
                ]

                guard let url = components.url else {
                    throw URLError(.badURL)
                }

                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: 8
                )
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue(
                    "MemoryTrail/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")",
                    forHTTPHeaderField: "User-Agent"
                )

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode)
                else {
                    throw URLError(.badServerResponse)
                }

                return try JSONDecoder().decode(MemoryTrailUpdateManifest.self, from: data)
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    static func isNewer(
        _ manifest: MemoryTrailUpdateManifest,
        thanVersion currentVersion: String,
        currentBuild: Int
    ) -> Bool {
        let versionComparison = compare(manifest.version, currentVersion)
        if versionComparison != 0 {
            return versionComparison > 0
        }

        return (manifest.build ?? 0) > currentBuild
    }

    private static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r {
                return l > r ? 1 : -1
            }
        }
        return 0
    }
}

private enum MemoryTrailBackgroundUpdater {
    enum UpdateError: LocalizedError {
        case invalidDownloadURL
        case badDownloadResponse
        case mountFailed
        case appNotFound
        case installLocationNotWritable
        case signatureVerificationFailed
        case versionMismatch
        case helperLaunchFailed

        var errorDescription: String? {
            switch self {
            case .invalidDownloadURL: return "The update download URL is invalid."
            case .badDownloadResponse: return "The update download failed."
            case .mountFailed: return "The downloaded update could not be opened."
            case .appNotFound: return "Memory Trail.app was not found in the downloaded update."
            case .installLocationNotWritable: return "Memory Trail cannot update itself from its current location."
            case .signatureVerificationFailed: return "The downloaded app failed code-signature verification."
            case .versionMismatch: return "The downloaded app does not match the expected Memory Trail release."
            case .helperLaunchFailed: return "The update helper could not be started."
            }
        }
    }

    static func downloadInstallAndRelaunch(_ manifest: MemoryTrailUpdateManifest) async throws {
        guard let downloadURL = URL(string: manifest.downloadURL) else {
            throw UpdateError.invalidDownloadURL
        }

        var request = URLRequest(
            url: downloadURL,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 60
        )
        request.setValue(
            "MemoryTrail/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")",
            forHTTPHeaderField: "User-Agent"
        )

        let (temporaryDownload, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw UpdateError.badDownloadResponse
        }

        let currentAppURL = Bundle.main.bundleURL
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let prepared = try await Task.detached(priority: .utility) {
            try prepareUpdate(
                temporaryDownload: temporaryDownload,
                currentAppURL: currentAppURL,
                expectedVersion: manifest.version,
                expectedBuild: manifest.build
            )
        }.value

        try launchReplacementHelper(
            stagedAppURL: prepared.stagedAppURL,
            stagingRootURL: prepared.stagingRootURL,
            currentAppURL: currentAppURL,
            currentPID: currentPID
        )

        await MainActor.run {
            NSApplication.shared.terminate(nil)
        }
    }

    private static func prepareUpdate(
        temporaryDownload: URL,
        currentAppURL: URL,
        expectedVersion: String,
        expectedBuild: Int?
    ) throws -> (stagedAppURL: URL, stagingRootURL: URL) {
        let fileManager = FileManager.default
        let parentDirectory = currentAppURL.deletingLastPathComponent()

        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            throw UpdateError.installLocationNotWritable
        }

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MemoryTrailUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: stagingRoot,
            withIntermediateDirectories: true
        )

        let dmgURL = stagingRoot.appendingPathComponent("MemoryTrailUpdate.dmg")
        try fileManager.moveItem(at: temporaryDownload, to: dmgURL)

        let mountPoint = try mountDMG(dmgURL)
        defer {
            _ = try? runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["detach", mountPoint.path]
            )
        }

        let mountedItems = try fileManager.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        guard let appURL = mountedItems.first(where: {
            $0.pathExtension.lowercased() == "app"
        }) else {
            throw UpdateError.appNotFound
        }

        let stagedAppURL = stagingRoot.appendingPathComponent("Memory Trail.app")
        try fileManager.copyItem(at: appURL, to: stagedAppURL)

        guard let stagedBundle = Bundle(url: stagedAppURL),
              stagedBundle.bundleIdentifier == Bundle.main.bundleIdentifier
        else {
            throw UpdateError.appNotFound
        }

        let stagedVersion =
            stagedBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard stagedVersion == expectedVersion else {
            throw UpdateError.versionMismatch
        }

        if let expectedBuild {
            let stagedBuildString =
                stagedBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            guard Int(stagedBuildString) == expectedBuild else {
                throw UpdateError.versionMismatch
            }
        }

        do {
            _ = try runProcess(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", stagedAppURL.path]
            )
        } catch {
            throw UpdateError.signatureVerificationFailed
        }

        return (stagedAppURL, stagingRoot)
    }

    private static func mountDMG(_ dmgURL: URL) throws -> URL {
        let data = try runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", "-plist", dmgURL.path]
        )

        guard let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        let entities = plist["system-entities"] as? [[String: Any]],
        let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw UpdateError.mountFailed
        }

        return URL(fileURLWithPath: mountPath, isDirectory: true)
    }

    private static func runProcess(
        executable: String,
        arguments: [String]
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw UpdateError.mountFailed
        }

        return data
    }

    private static func launchReplacementHelper(
        stagedAppURL: URL,
        stagingRootURL: URL,
        currentAppURL: URL,
        currentPID: Int32
    ) throws {
        let helperURL = stagingRootURL.appendingPathComponent("apply-update.sh")
        let script = """
        #!/bin/sh
        set -eu
        PID="$1"
        STAGED="$2"
        TARGET="$3"
        ROOT="$4"
        NEW="$TARGET.update"
        BACKUP="$TARGET.previous"

        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
        done

        rm -rf "$NEW" "$BACKUP"
        /usr/bin/ditto "$STAGED" "$NEW"

        if [ -e "$TARGET" ]; then
          /bin/mv "$TARGET" "$BACKUP"
        fi

        if /bin/mv "$NEW" "$TARGET"; then
          /usr/bin/open "$TARGET"
          rm -rf "$BACKUP" "$ROOT"
        else
          rm -rf "$NEW"
          if [ -e "$BACKUP" ]; then
            /bin/mv "$BACKUP" "$TARGET"
          fi
          exit 1
        fi
        """

        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            helperURL.path,
            String(currentPID),
            stagedAppURL.path,
            currentAppURL.path,
            stagingRootURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw UpdateError.helperLaunchFailed
        }
    }
}
private struct MemoryTrailUpdateSheet: View {
    let presentation: MemoryTrailUpdatePresentation
    let icon: NSImage
    let currentVersion: String
    let isInstallingUpdate: Bool
    let onUpdate: (MemoryTrailUpdateManifest) -> Void
    let onRemindTomorrow: (MemoryTrailUpdateManifest) -> Void
    let onSkipVersion: (MemoryTrailUpdateManifest) -> Void
    let onOpenReleases: () -> Void
    let onDismiss: () -> Void

    private let primaryText = Color(red: 0.07, green: 0.14, blue: 0.27)
    private let secondaryText = Color(red: 0.30, green: 0.37, blue: 0.48)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.96, blue: 1.00),
                    Color(red: 0.97, green: 0.985, blue: 1.00),
                    Color.white
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 270, y: -250)

            content
                .padding(usesFullBleedArtwork ? 0 : 32)
        }
        .frame(width: 760, height: 720)
    }

    private var usesFullBleedArtwork: Bool {
        if case .upToDate = presentation {
            return true
        }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .whatsNew(let changelog):
            whatsNewView(changelog)

        case .updateAvailable(let manifest):
            updateAvailableView(manifest)

        case .upToDate(let version):
            upToDateView(version: version)

        case .unavailable(let message):
            statusView(
                symbol: "wifi.exclamationmark",
                symbolColor: .orange,
                title: "Couldn’t check for updates",
                message: message,
                primaryButton: "Open Releases",
                primaryAction: onOpenReleases
            )
        }
    }

    private func whatsNewView(_ changelog: MemoryTrailChangelog) -> some View {
        VStack(spacing: 0) {
            sheetHeader(
                eyebrow: "WHAT’S NEW • VERSION \(changelog.version)",
                title: "What’s New in Memory Trail",
                subtitle: changelog.headline
            )

            Text(changelog.summary)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 570)
                .padding(.top, 12)
                .padding(.bottom, 22)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 14
                ) {
                    ForEach(changelog.sections) { section in
                        changeCard(section)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }

            footer(
                primaryTitle: "Continue",
                primaryAction: onDismiss,
                secondaryTitle: nil,
                secondaryAction: nil
            )
        }
    }

    private func updateAvailableView(_ manifest: MemoryTrailUpdateManifest) -> some View {
        VStack(spacing: 0) {
            sheetHeader(
                eyebrow: "A FRESHER TRAIL IS READY",
                title: "Memory Trail \(manifest.displayVersion)",
                subtitle: "A new version is ready. Update now, take a day, or skip this release."
            )

            HStack(spacing: 12) {
                versionPill("Current", value: currentVersion, tint: .gray, valueColor: primaryText)
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                versionPill("New", value: manifest.displayVersion, tint: .blue, valueColor: .blue)
            }
            .padding(.top, 18)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 14) {
                    if !manifest.highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What’s waiting on the next trail")
                                .font(.headline)
                                .foregroundStyle(primaryText)

                            ForEach(manifest.highlights, id: \.self) { item in
                                bulletRow(item)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(MemoryTrailPalette.border, lineWidth: 1)
                        }
                    }

                    ForEach(manifest.changelog) { section in
                        changeCard(section)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 8)
            }

            Text("Update checks use version metadata only. Your captured activity never leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            HStack(spacing: 10) {
                Button {
                    onUpdate(manifest)
                } label: {
                    Label(
                        isInstallingUpdate ? "Preparing Update…" : "Update Now",
                        systemImage: isInstallingUpdate ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isInstallingUpdate)
                .keyboardShortcut(.defaultAction)

                Button {
                    onRemindTomorrow(manifest)
                } label: {
                    Label("Remind Me Tomorrow", systemImage: "clock")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isInstallingUpdate)

                Button("Skip This Version") {
                    onSkipVersion(manifest)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(isInstallingUpdate)
            }
            .padding(.top, 18)
        }
    }

    private func upToDateView(version: String) -> some View {
        ZStack {
            FreshestTrailBackdrop()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

                    Text("Memory Trail")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Spacer()
                }
                .padding(.horizontal, 34)
                .padding(.top, 26)

                Spacer(minLength: 4)

                FreshestTrailLaptop(icon: icon)
                    .frame(width: 360, height: 205)

                VStack(spacing: 10) {
                    Text("You’re on the freshest trail.")
                        .font(.system(size: 37, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

                    Capsule()
                        .fill(Color.green)
                        .frame(width: 228, height: 5)

                    Text("No detours. No downloads. Memory Trail is already\nrunning the latest release.")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                HStack(spacing: 9) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.cyan)

                    Text("Version \(version)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                .frame(height: 46)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.cyan.opacity(0.70), lineWidth: 1.4)
                }
                .shadow(color: .cyan.opacity(0.16), radius: 12)
                .padding(.top, 18)

                Button {
                    onDismiss()
                } label: {
                    HStack(spacing: 12) {
                        Text("Keep Exploring")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 17, weight: .bold))
                    .frame(minWidth: 228)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 16)

                Text("We’ll keep an eye on the trail and let you know when something new arrives.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(10)
    }

    private struct FreshestTrailBackdrop: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.39, blue: 0.94),
                        Color(red: 0.32, green: 0.44, blue: 0.92),
                        Color(red: 0.04, green: 0.24, blue: 0.51)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.98),
                                Color.orange.opacity(0.42),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 92
                        )
                    )
                    .frame(width: 178, height: 178)
                    .offset(x: 235, y: -108)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 96))
                    .foregroundStyle(.white.opacity(0.22))
                    .offset(x: 250, y: -250)

                Image(systemName: "cloud.fill")
                    .font(.system(size: 78))
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: -250, y: -215)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 330))
                    .foregroundStyle(Color(red: 0.24, green: 0.37, blue: 0.72).opacity(0.74))
                    .offset(y: -20)

                Image(systemName: "mountain.2.fill")
                    .font(.system(size: 285))
                    .foregroundStyle(Color(red: 0.08, green: 0.27, blue: 0.55).opacity(0.82))
                    .offset(x: -165, y: 55)

                HStack(alignment: .bottom, spacing: 28) {
                    ForEach(0..<10, id: \.self) { index in
                        Image(systemName: "tree.fill")
                            .font(.system(size: CGFloat(38 + (index % 4) * 10)))
                            .foregroundStyle(
                                Color(red: 0.02, green: 0.20, blue: 0.34)
                                    .opacity(0.94)
                            )
                    }
                }
                .offset(y: 224)

                FreshestTrailRoad()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.88),
                                Color.yellow.opacity(0.98),
                                Color.orange.opacity(0.92)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        ),
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .frame(width: 370, height: 245)
                    .offset(x: 110, y: 75)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.24)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private struct FreshestTrailLaptop: View {
        let icon: NSImage

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.13, blue: 0.34))
                    .frame(width: 285, height: 166)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.04, green: 0.55, blue: 0.98),
                                        Color(red: 0.23, green: 0.38, blue: 0.88)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(8)
                    }
                    .overlay {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 88, height: 88)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.96),
                                Color(red: 0.65, green: 0.72, blue: 0.84)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 330, height: 20)
                    .offset(y: 88)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 4)

                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 86, height: 86)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.42, green: 0.96, blue: 0.24),
                                Color(red: 0.09, green: 0.72, blue: 0.22)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Circle()
                    )
                    .overlay {
                        Circle().stroke(.white.opacity(0.75), lineWidth: 3)
                    }
                    .shadow(color: .green.opacity(0.28), radius: 13, y: 6)
                    .offset(x: 128, y: 36)

                HStack(spacing: 12) {
                    Capsule().fill(Color.yellow)
                        .frame(width: 8, height: 34)
                        .rotationEffect(.degrees(22))
                    Capsule().fill(Color.yellow)
                        .frame(width: 8, height: 34)
                        .rotationEffect(.degrees(52))
                    Capsule().fill(Color.yellow)
                        .frame(width: 8, height: 34)
                        .rotationEffect(.degrees(80))
                }
                .offset(x: 154, y: -70)
            }
        }
    }

    private struct FreshestTrailRoad: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + 12, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.maxX - 20, y: rect.minY + 18),
                control1: CGPoint(x: rect.maxX * 0.65, y: rect.maxY * 0.72),
                control2: CGPoint(x: rect.midX * 0.65, y: rect.midY * 0.72)
            )
            return path
        }
    }

    private func statusView(
        symbol: String,
        symbolColor: Color,
        title: String,
        message: String,
        primaryButton: String,
        primaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(symbolColor.opacity(0.12))
                    .frame(width: 96, height: 96)

                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(symbolColor)
            }

            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(message)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            Spacer()

            Button(primaryButton, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Button("Close", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func sheetHeader(
        eyebrow: String,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 90, height: 90)
                .shadow(color: Color.blue.opacity(0.18), radius: 18, y: 8)

            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(Color.blue)

            Text(title)
                .font(.system(size: 33, weight: .bold, design: .rounded))
                .foregroundStyle(primaryText)

            Text(subtitle)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func changeCard(_ section: MemoryTrailChangeSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 34, height: 34)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(primaryText)
            }

            ForEach(section.items, id: \.self) { item in
                bulletRow(item)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(17)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.035), radius: 9, y: 4)
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(Color.blue.opacity(0.72))
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func versionPill(
        _ label: String,
        value: String,
        tint: Color,
        valueColor: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(valueColor)
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private func footer(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        HStack {
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()

            Button(primaryTitle, action: primaryAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 18)
    }
}

private struct MemoryTrailAccessibilityPrompt: View {
    let onOpenSettings: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.97, blue: 1.00),
                    Color.white,
                    Color(red: 0.96, green: 0.98, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.10))
                        .frame(width: 96, height: 96)

                    Image(systemName: "accessibility")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                Text("Give Memory Trail the full picture")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("Accessibility is needed to recognize focused window context such as browser page titles, Outlook subjects, Teams conversations, and supported document names. Without it, your trail will be incomplete.")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)

                HStack(spacing: 10) {
                    Button("Not Now", action: onNotNow)
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                    Button(action: onOpenSettings) {
                        Label("Enable Accessibility", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                Text("Memory Trail only reads supported local app/window context. Your captured history remains on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            .padding(30)
        }
        .frame(width: 520, height: 410)
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
