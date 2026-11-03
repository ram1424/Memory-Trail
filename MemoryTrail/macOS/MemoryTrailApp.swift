#if os(macOS)
import AppKit
import Darwin
import SwiftUI
import SwiftData

@main
struct MemoryTrailApp: App {
    private let container: ModelContainer
    @State private var preferences = RecallPreferences.shared
    @State private var isLaunching = true
    @State private var launchProgress = 0.06
    @State private var launchStatus = "Opening your private timeline…"

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
                    await runStartupSequence()
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
        MemoryTrailNativeLoadingView(
            icon: Self.brandIcon,
            progress: launchProgress,
            status: launchStatus
        )
    }

    @MainActor
    private func runStartupSequence() async {
        let startupBeganAt = Date()
        let minimumSplashDuration: TimeInterval = 2.5

        updateLaunchProgress(0.12, status: "Opening your private timeline…")

        // A real SwiftData read verifies the local store is ready before capture starts.
        _ = try? container.mainContext.fetchCount(FetchDescriptor<MemoryItem>())
        updateLaunchProgress(0.34, status: "Starting private activity capture…")

        MacCaptureCoordinator.shared.start(context: container.mainContext)
        updateLaunchProgress(0.62, status: "Loading recent activity…")

        // Warm the exact local data path the Today view uses without loading the full history.
        var warmupDescriptor = FetchDescriptor<MemoryItem>()
        warmupDescriptor.fetchLimit = 32
        _ = try? container.mainContext.fetch(warmupDescriptor)
        updateLaunchProgress(0.86, status: "Preparing your workspace…")

        // Give SwiftUI one render pass to settle the main interface before the handoff.
        await Task.yield()
        updateLaunchProgress(1.0, status: "Ready")

        // Keep the loading screen visible for at least 2.5 seconds total.
        let elapsed = Date().timeIntervalSince(startupBeganAt)
        let remaining = max(0, minimumSplashDuration - elapsed)
        if remaining > 0 {
            try? await Task.sleep(
                nanoseconds: UInt64(remaining * 1_000_000_000)
            )
        }

        isLaunching = false
    }

    @MainActor
    private func updateLaunchProgress(_ value: Double, status: String) {
        launchStatus = status
        withAnimation(.easeInOut(duration: 0.32)) {
            launchProgress = min(max(value, 0), 1)
        }
    }
}

private struct MemoryTrailNativeLoadingView: View {
    let icon: NSImage
    let progress: Double
    let status: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let activityIcons: [(symbol: String, tint: Color)] = [
        ("globe", .cyan),
        ("envelope.fill", .blue),
        ("bubble.left.and.bubble.right.fill", .purple),
        ("doc.text.fill", .orange),
        ("calendar", .pink)
    ]

    var body: some View {
        GeometryReader { geometry in
            SwiftUI.TimelineView(.animation) { timeline in
                let size = geometry.size
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let barWidth = min(470.0, max(320.0, size.width * 0.34))
                let logoSize = min(132.0, max(108.0, size.width * 0.095))
                let logoPulse = reduceMotion ? 1.0 : 1.0 + (sin(time * 1.8) * 0.012)
                let glowPulse = reduceMotion ? 0.80 : 0.78 + (sin(time * 1.35) * 0.06)
                let dashPhase = reduceMotion ? 0 : -CGFloat((time * 28).truncatingRemainder(dividingBy: 48))

                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.070, blue: 0.210),
                            Color(red: 0.075, green: 0.185, blue: 0.430),
                            Color(red: 0.390, green: 0.285, blue: 0.570),
                            Color(red: 0.930, green: 0.545, blue: 0.395)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.86, blue: 0.48).opacity(glowPulse),
                            Color(red: 1.0, green: 0.56, blue: 0.39).opacity(0.28),
                            .clear
                        ],
                        center: UnitPoint(x: 0.83, y: 0.49),
                        startRadius: 4,
                        endRadius: max(260, size.width * 0.30)
                    )

                    MemoryTrailMountainShape(layer: 0)
                        .fill(Color(red: 0.055, green: 0.135, blue: 0.315).opacity(0.64))
                        .offset(y: size.height * 0.06)

                    MemoryTrailMountainShape(layer: 1)
                        .fill(Color(red: 0.018, green: 0.060, blue: 0.180).opacity(0.94))
                        .offset(y: size.height * 0.14)

                    trailPath(in: size)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.cyan.opacity(0.92),
                                    Color(red: 0.40, green: 0.50, blue: 1.0),
                                    Color(red: 1.0, green: 0.68, blue: 0.34)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 4.5,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: [18, 12],
                                dashPhase: dashPhase
                            )
                        )
                        .shadow(color: .cyan.opacity(0.40), radius: 8)

                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .scaleEffect(logoPulse)
                        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
                        .position(x: size.width * 0.5, y: size.height * 0.18)

                    HStack(spacing: 10) {
                        Text("Memory")
                            .foregroundStyle(.white)

                        Text("Trail")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.45, green: 0.90, blue: 1.0),
                                        Color(red: 0.58, green: 0.58, blue: 1.0),
                                        Color(red: 0.88, green: 0.60, blue: 1.0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .position(x: size.width * 0.5, y: size.height * 0.36)

                    Text("Rediscover your day, instantly")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .position(x: size.width * 0.5, y: size.height * 0.415)

                    HStack(spacing: 22) {
                        ForEach(Array(activityIcons.enumerated()), id: \.offset) { index, item in
                            let floatAmount = reduceMotion
                                ? 0
                                : CGFloat(sin((time * 1.65) + Double(index) * 0.92) * 6)

                            ZStack {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .fill(.white.opacity(0.15))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                                            .stroke(.white.opacity(0.25), lineWidth: 1)
                                    }
                                    .shadow(color: .black.opacity(0.16), radius: 12, y: 7)

                                Image(systemName: item.symbol)
                                    .font(.system(size: 25, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(item.tint)
                            }
                            .frame(width: 62, height: 62)
                            .offset(y: floatAmount)
                        }
                    }
                    .position(x: size.width * 0.5, y: size.height * 0.635)

                    VStack(spacing: 12) {
                        Text(status)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.90))
                            .contentTransition(.opacity)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.white.opacity(0.20))
                                .overlay {
                                    Capsule()
                                        .stroke(.white.opacity(0.22), lineWidth: 1)
                                }

                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.20, green: 0.86, blue: 1.0),
                                            Color(red: 0.24, green: 0.50, blue: 1.0),
                                            Color(red: 0.64, green: 0.45, blue: 1.0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(10, barWidth * progress))
                                .shadow(color: .cyan.opacity(0.45), radius: 8)
                                .animation(.easeInOut(duration: 0.32), value: progress)

                            Circle()
                                .fill(.white)
                                .frame(width: 11, height: 11)
                                .shadow(color: .cyan.opacity(0.85), radius: 8)
                                .offset(x: max(0, min(barWidth - 11, barWidth * progress - 6)))
                                .opacity(progress > 0.02 ? 1 : 0)
                                .animation(.easeInOut(duration: 0.32), value: progress)
                        }
                        .frame(width: barWidth, height: 11)
                    }
                    .position(x: size.width * 0.5, y: size.height * 0.82)
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .background(Color(red: 0.025, green: 0.070, blue: 0.210))
        .ignoresSafeArea()
    }

    private func trailPath(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.70))
            path.addCurve(
                to: CGPoint(x: size.width * 0.39, y: size.height * 0.665),
                control1: CGPoint(x: size.width * 0.20, y: size.height * 0.60),
                control2: CGPoint(x: size.width * 0.29, y: size.height * 0.74)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.66, y: size.height * 0.68),
                control1: CGPoint(x: size.width * 0.50, y: size.height * 0.59),
                control2: CGPoint(x: size.width * 0.56, y: size.height * 0.75)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.92, y: size.height * 0.57),
                control1: CGPoint(x: size.width * 0.77, y: size.height * 0.61),
                control2: CGPoint(x: size.width * 0.84, y: size.height * 0.66)
            )
        }
    }
}

private struct MemoryTrailMountainShape: Shape {
    let layer: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))

        if layer == 0 {
            path.addLine(to: CGPoint(x: 0, y: rect.height * 0.54))
            path.addLine(to: CGPoint(x: rect.width * 0.10, y: rect.height * 0.40))
            path.addLine(to: CGPoint(x: rect.width * 0.20, y: rect.height * 0.51))
            path.addLine(to: CGPoint(x: rect.width * 0.31, y: rect.height * 0.31))
            path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.50))
            path.addLine(to: CGPoint(x: rect.width * 0.55, y: rect.height * 0.28))
            path.addLine(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.48))
            path.addLine(to: CGPoint(x: rect.width * 0.80, y: rect.height * 0.30))
            path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.46))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.37))
        } else {
            path.addLine(to: CGPoint(x: 0, y: rect.height * 0.68))
            path.addLine(to: CGPoint(x: rect.width * 0.13, y: rect.height * 0.54))
            path.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.63))
            path.addLine(to: CGPoint(x: rect.width * 0.38, y: rect.height * 0.47))
            path.addLine(to: CGPoint(x: rect.width * 0.51, y: rect.height * 0.62))
            path.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.45))
            path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.61))
            path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.49))
            path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.58))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
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
