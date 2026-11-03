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
    @State private var splashProgress = 0.02

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
        MemoryTrailSimpleSplashView(
            icon: Self.brandIcon,
            progress: splashProgress
        )
    }

    @MainActor
    private func runStartupSequence() async {
        let startupBeganAt = Date()
        let minimumSplashDuration: TimeInterval = 2.5

        splashProgress = 0.02
        withAnimation(.linear(duration: 2.35)) {
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

        // Keep the simple animated splash visible for its full 2.5-second run.
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
                let iconScale = reduceMotion ? 1.0 : 1.0 + (sin(time * 1.75) * 0.012)
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
                                .antialiased(true)
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
