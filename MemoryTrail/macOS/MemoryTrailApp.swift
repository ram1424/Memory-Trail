#if os(macOS)
import AppKit
import Darwin
import Foundation
import SwiftUI
import SwiftData

@main
struct MemoryTrailApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true
    @State private var splashProgress = 0.02
    @State private var updatePresentation: MemoryTrailUpdatePresentation?
    @State private var isCheckingForUpdates = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("memoryTrail.lastPresentedWhatsNewRelease") private var lastPresentedWhatsNewRelease = ""
    @AppStorage("memoryTrail.lastUpdateCheckEpoch") private var lastUpdateCheckEpoch = 0.0
    @AppStorage("memoryTrail.didRequestInitialMaximizedWindow") private var didRequestInitialMaximizedWindow = false

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
                    currentVersion: Self.appVersion,
                    onDownload: { url in
                        NSWorkspace.shared.open(url)
                        updatePresentation = nil
                    },
                    onOpenReleases: {
                        if let url = URL(string: "https://github.com/ram1424/Memory-Trail/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                        updatePresentation = nil
                    },
                    onDismiss: {
                        updatePresentation = nil
                    }
                )
            }
            .onChange(of: hasCompletedOnboarding) { _, completed in
                guard completed, Self.screenshotDemoSelection == nil else { return }
                Task {
                    await presentWhatsNewIfNeeded()
                    await performAutomaticUpdateCheckIfNeeded()
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private static var releaseIdentity: String {
        "\(appVersion) (\(buildNumber))"
    }

    private static var currentChangelog: MemoryTrailChangelog {
        MemoryTrailChangelog(
            version: appVersion,
            headline: "First Official Release",
            summary: "Welcome to the first official release of Memory Trail — a privacy-first, local activity history for rediscovering what you worked on, viewed, discussed, opened, and copied throughout your day.",
            sections: [
                MemoryTrailChangeSection(
                    title: "Your Day, Remembered",
                    symbol: "clock.arrow.circlepath",
                    items: [
                        "Builds a chronological local timeline of the activity Memory Trail can observe on your Mac.",
                        "Keeps the newest activity at the top with Live Activity so your most recent context is easy to find.",
                        "Records meaningful app and window context instead of rewriting your history into AI-generated summaries."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Ask Memory Trail",
                    symbol: "magnifyingglass",
                    items: [
                        "Search your locally stored history using natural-language questions.",
                        "Find activity by time, app, subject, page, conversation, filename, document, or nearby activity.",
                        "Use questions such as what you were doing around a certain time, what happened before or after another activity, or which conversations you had today."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Conversations & Chat",
                    symbol: "bubble.left.and.bubble.right.fill",
                    items: [
                        "Captures supported Microsoft Teams conversation and chat titles, including selected chats when macOS exposes them.",
                        "Supports generic conversation-title capture for Slack, Discord, Zoom, Webex, Signal, WhatsApp, Telegram, Mattermost, Google Chat, Messages, and other compatible chat apps.",
                        "Conversation capture stores useful local context such as the chat or conversation title — not audio recordings or screen recordings."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Email",
                    symbol: "envelope.fill",
                    items: [
                        "Captures supported Microsoft Outlook message subject context and sender information when available.",
                        "Retains useful Mail and email-window context exposed through macOS Accessibility.",
                        "Helps you retrace which message or subject you were working with without creating a cloud copy of your mailbox."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Web & Browsers",
                    symbol: "globe",
                    items: [
                        "Captures supported browser page and tab titles as you work.",
                        "Stores URLs when the browser exposes them to Memory Trail.",
                        "Keeps web activity searchable alongside email, chat, files, and other local activity."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Files & Documents",
                    symbol: "folder.fill",
                    items: [
                        "Tracks supported Finder, Preview, Word, Excel, PowerPoint, and OneNote context.",
                        "Captures useful file, folder, document, notebook, page, or path information when macOS and the source app expose it.",
                        "Makes documents easier to rediscover later without uploading their contents to Memory Trail."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Clipboard History",
                    symbol: "doc.on.clipboard.fill",
                    items: [
                        "Keeps a local history of supported copied text, links, and code when clipboard capture is enabled.",
                        "Clipboard capture is enabled by default and can be turned off at any time.",
                        "Clipboard history remains stored locally with the rest of your Memory Trail data."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Favorites & Manual Memories",
                    symbol: "star.fill",
                    items: [
                        "Mark important timeline entries as Favorites for quick access later.",
                        "Create manual memories for notes, references, or context you want to preserve yourself.",
                        "Use Memory Trail as both an automatic activity trail and a lightweight personal reference history."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Insights & Filters",
                    symbol: "chart.bar.fill",
                    items: [
                        "Use Insights to understand the locally captured activity represented in your history.",
                        "Filter the Today timeline by the activity categories that are actually present in your data.",
                        "Quickly narrow your history to web, email, chat, files, clipboard, favorites, and other supported activity types."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Details & Navigation",
                    symbol: "rectangle.righthalf.inset.filled",
                    items: [
                        "Select activity to inspect its captured details in the right-side panel.",
                        "Use the newest-first Today view to retrace work without scrolling through unrelated history.",
                        "Memory Trail avoids duplicate/noisy entries where possible so the timeline stays useful."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Privacy First",
                    symbol: "lock.shield.fill",
                    items: [
                        "Captured activity is sourced, processed, and stored locally on your Mac using SwiftData.",
                        "There is no Memory Trail account, no cloud timeline sync, no advertising SDK, and no analytics SDK.",
                        "Captured timeline data is not sent to an external service, and Memory Trail does not generate AI summaries of your timeline.",
                        "The source code is available for review so the app's capture and storage behavior can be verified."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Your Controls",
                    symbol: "slider.horizontal.3",
                    items: [
                        "Pause and resume capture whenever you want.",
                        "Exclude apps and processes from capture; Wallet and Passwords are excluded by default.",
                        "Enable or disable clipboard capture and review privacy information directly in Settings.",
                        "Memory Trail requests Accessibility permission only to read supported active-app and window context needed for your local timeline."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Menu Bar",
                    symbol: "menubar.rectangle",
                    items: [
                        "Keep Memory Trail available from the macOS menu bar while the main window is closed or minimized.",
                        "Pause or resume capture quickly from the menu bar.",
                        "See the reminder that your activity stays on this Mac and quit Memory Trail directly from the menu."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Updates",
                    symbol: "arrow.triangle.2.circlepath",
                    items: [
                        "Choose Memory Trail → Check for Updates… at any time.",
                        "Memory Trail periodically checks a small version manifest for newer releases when you do not check manually.",
                        "When a newer version is available, Download Update takes you to the current DMG.",
                        "Update checks use version metadata only and never include your timeline, clipboard history, files, conversations, or searches."
                    ]
                ),
                MemoryTrailChangeSection(
                    title: "Designed for macOS",
                    symbol: "laptopcomputer",
                    items: [
                        "Built as a native macOS app with an Apple-style interface, local SwiftData storage, and macOS Accessibility integration.",
                        "Includes a fast 2-second animated startup experience.",
                        "Requires macOS 14 or later."
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
            .version: "Build \(Self.buildNumber)",
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
        let minimumSplashDuration: TimeInterval = 2.0

        splashProgress = 0.02
        withAnimation(.linear(duration: 1.85)) {
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

        // Keep the simple animated splash visible for its full 2-second run.
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
        await maximizeWindowOnFirstLaunchIfNeeded()

        if hasCompletedOnboarding {
            await presentWhatsNewIfNeeded()
            await performAutomaticUpdateCheckIfNeeded()
        }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await performAutomaticUpdateCheckIfNeeded()
        }
    }

    @MainActor
    private func maximizeWindowOnFirstLaunchIfNeeded() async {
        guard Self.screenshotDemoSelection == nil,
              !didRequestInitialMaximizedWindow
        else {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Wait until SwiftUI/AppKit has presented the first real app window,
        // then expand it to the screen's visible work area exactly once.
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

                didRequestInitialMaximizedWindow = true
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
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        lastUpdateCheckEpoch = Date().timeIntervalSince1970

        do {
            let manifest = try await MemoryTrailUpdateService.fetchLatest()
            if MemoryTrailUpdateService.isNewer(
                manifest,
                thanVersion: Self.appVersion,
                build: Int(Self.buildNumber) ?? 0
            ) {
                updatePresentation = .updateAvailable(manifest)
            } else if manual {
                updatePresentation = .upToDate(Self.appVersion)
            }
        } catch {
            guard manual else { return }
            updatePresentation = .unavailable(
                "Memory Trail could not reach the update manifest. The source repository is private, so automatic checks use the public update manifest rather than embedding GitHub credentials in the app."
            )
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
    let build: Int
    let publishedAt: String?
    let downloadURL: String
    let releaseURL: String
    let highlights: [String]
    let changelog: [MemoryTrailChangeSection]
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
            return "update-\(manifest.version)-\(manifest.build)"
        case .upToDate(let version):
            return "up-to-date-\(version)"
        case .unavailable:
            return "update-unavailable"
        }
    }
}

private enum MemoryTrailUpdateService {
    private static let manifestURL = URL(
        string: "https://ram1424.github.io/Memory-Trail/update.json"
    )!

    static func fetchLatest() async throws -> MemoryTrailUpdateManifest {
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
    }

    static func isNewer(
        _ manifest: MemoryTrailUpdateManifest,
        thanVersion currentVersion: String,
        build currentBuild: Int
    ) -> Bool {
        let result = compare(manifest.version, currentVersion)
        if result != 0 {
            return result > 0
        }
        return manifest.build > currentBuild
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

private struct MemoryTrailUpdateSheet: View {
    let presentation: MemoryTrailUpdatePresentation
    let icon: NSImage
    let currentVersion: String
    let onDownload: (URL) -> Void
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
                .padding(32)
        }
        .frame(width: 760, height: 720)
    }

    @ViewBuilder
    private var content: some View {
        switch presentation {
        case .whatsNew(let changelog):
            whatsNewView(changelog)

        case .updateAvailable(let manifest):
            updateAvailableView(manifest)

        case .upToDate(let version):
            statusView(
                symbol: "checkmark.seal.fill",
                symbolColor: .green,
                title: "Memory Trail is up to date",
                message: "You’re running version \(version). No newer release is available.",
                primaryButton: "Done",
                primaryAction: onDismiss
            )

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
                eyebrow: "FIRST OFFICIAL RELEASE • VERSION \(changelog.version)",
                title: "Welcome to Memory Trail",
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
                eyebrow: "UPDATE AVAILABLE",
                title: "Memory Trail \(manifest.version)",
                subtitle: "A newer version is ready to download."
            )

            HStack(spacing: 12) {
                versionPill("Current", value: currentVersion, tint: .gray, valueColor: primaryText)
                Image(systemName: "arrow.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.secondary)
                versionPill("New", value: manifest.version, tint: .blue, valueColor: .blue)
            }
            .padding(.top, 18)
            .padding(.bottom, 18)

            ScrollView {
                VStack(spacing: 14) {
                    if !manifest.highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Highlights")
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

            Text("Only update metadata is checked. Your Memory Trail activity remains local to this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            footer(
                primaryTitle: "Download Update",
                primaryAction: {
                    if let url = URL(string: manifest.downloadURL) {
                        onDownload(url)
                    }
                },
                secondaryTitle: "Later",
                secondaryAction: onDismiss
            )
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
