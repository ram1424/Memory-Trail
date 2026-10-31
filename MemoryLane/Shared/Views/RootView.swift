import AppKit
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var selection: SidebarItem?
    @State private var category: MemoryLaneCategory = .allApps
    @State private var showingAddMemory = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let forceMainInterface: Bool
    private let forcedSelection: SidebarItem?

    init(
        initialSelection: SidebarItem? = .today,
        forceMainInterface: Bool = false
    ) {
        _selection = State(initialValue: initialSelection)
        self.forceMainInterface = forceMainInterface
        self.forcedSelection = forceMainInterface ? initialSelection : nil
    }

    var body: some View {
        Group {
            if forceMainInterface || hasCompletedOnboarding {
                mainInterface
            } else {
                OnboardingView()
            }
        }
    }

    private var mainInterface: some View {
        let activeSelection = forcedSelection ?? selection ?? .today

        return HStack(spacing: 0) {
            MemoryLaneSidebar(
                selection: Binding(
                    get: { forcedSelection ?? selection },
                    set: { value in
                        guard forcedSelection == nil else { return }
                        selection = value
                    }
                ),
                category: $category
            )
            .environment(preferences)
            .frame(width: 238)

            Divider()
                .opacity(0.55)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(red: 0.96, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch activeSelection {
                    case .today, .timeline:
                        TimelineView(category: $category)
                    case .search:
                        SearchView()
                    case .favorites:
                        FavoritesView()
                    case .clipboard:
                        ClipboardHistoryView()
                    case .insights:
                        InsightsView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Memory")
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
        }
    }
}

struct MemoryLaneSidebar: View {
    @Environment(RecallPreferences.self) private var preferences
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    @Binding var selection: SidebarItem?
    @Binding var category: MemoryLaneCategory

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 16)

                    VStack(spacing: 5) {
                        sidebarButton(.today, title: "Today", symbol: "house.fill")
                        sidebarButton(.timeline, title: "Timeline", symbol: "line.3.horizontal.decrease")
                        sidebarButton(.search, title: "Ask Memory Lane", symbol: "magnifyingglass")
                        sidebarButton(.favorites, title: "Favorites", symbol: "star.fill")
                        sidebarButton(.clipboard, title: "Clipboard History", symbol: "doc.on.clipboard.fill")
                        sidebarButton(.insights, title: "Insights", symbol: "chart.bar.fill")
                        sidebarButton(.settings, title: "Settings", symbol: "gearshape.fill")
                    }
                    .padding(.horizontal, 10)

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)

                    HStack {
                        Text("Filters")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "chevron.up")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 7)

                    VStack(spacing: 3) {
                        ForEach(MemoryLaneCategory.allCases) { option in
                            categoryButton(option)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 14)
                }
            }

            captureStatus
                .padding(10)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.985, blue: 1.0),
                    Color(red: 0.94, green: 0.965, blue: 0.995)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var brandHeader: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .shadow(color: Color.accentColor.opacity(0.18), radius: 14, y: 6)

            Text("Memory Lane")
                .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private func sidebarButton(_ item: SidebarItem, title: String, symbol: String) -> some View {
        Button {
            selection = item
            if item == .today {
                category = .allApps
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 22)

                Text(title)
                    .font(.system(size: 14.5, weight: selection == item ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(selection == item ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 39)
            .background(
                selection == item
                    ? LinearGradient(
                        colors: [Color(red: 0.08, green: 0.50, blue: 1.0), Color(red: 0.20, green: 0.43, blue: 0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    : LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func categoryButton(_ option: MemoryLaneCategory) -> some View {
        let count = memories.lazy.filter { !$0.isCaptureNoise && option.matches($0) }.count
        let selected = category == option && (selection == .today || selection == .timeline)

        return Button {
            category = option
            selection = .today
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(option.tint)
                    .frame(width: 22)

                Text(option.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 26, minHeight: 22)
                    .background(Color.white.opacity(0.72), in: Capsule())
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var captureStatus: some View {
        Button {
            preferences.capturePaused.toggle()
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(preferences.capturePaused ? Color.orange : Color.green)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preferences.capturePaused ? "Capture paused" : "Capturing")
                        .font(.caption.weight(.semibold))

                    Text(preferences.capturePaused ? "Click to resume" : "Your activity is stored locally")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(11)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct MemoryLaneScreenshotShell: View {
    @Environment(RecallPreferences.self) private var preferences
    let selection: SidebarItem

    @State private var category: MemoryLaneCategory = .allApps

    var body: some View {
        HStack(spacing: 0) {
            MemoryLaneSidebar(
                selection: .constant(selection),
                category: $category
            )
            .environment(preferences)
            .frame(width: 238)

            Divider()
                .opacity(0.55)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(red: 0.96, green: 0.98, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selection {
                    case .today, .timeline:
                        TimelineView(category: $category)
                    case .search:
                        SearchView()
                    case .favorites:
                        FavoritesView()
                    case .clipboard:
                        ClipboardHistoryView()
                    case .insights:
                        InsightsView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ClipboardHistoryView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var searchText = ""

    private var items: [MemoryItem] {
        memories.filter {
            $0.sourceKind == .clipboard &&
            (searchText.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                pageHeader(
                    "Clipboard History",
                    subtitle: "Quickly find text and links you copied.",
                    symbol: "doc.on.clipboard.fill",
                    tint: .orange
                )

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search clipboard…", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                }

                if items.isEmpty {
                    ContentUnavailableView(
                        "No Clipboard Items",
                        systemImage: "doc.on.clipboard",
                        description: Text("Copied text will appear here when clipboard capture is enabled.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(items) { item in
                            MemoryRow(item: item)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct InsightsView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    private var todayItems: [MemoryItem] {
        memories.filter { Calendar.current.isDateInToday($0.createdAt) && !$0.isCaptureNoise }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageHeader(
                    "Insights",
                    subtitle: "A quick view of how your day is distributed.",
                    symbol: "chart.bar.fill",
                    tint: .cyan
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    InsightMetricCard(
                        title: "Total Activities",
                        value: "\(todayItems.count)",
                        symbol: "chart.bar.fill",
                        tint: .cyan
                    )

                    InsightMetricCard(
                        title: "Apps Used",
                        value: "\(Set(todayItems.map(\.sourceApp)).count)",
                        symbol: "square.grid.2x2.fill",
                        tint: .blue
                    )

                    InsightMetricCard(
                        title: "Favorites",
                        value: "\(todayItems.filter { $0.isFavorite }.count)",
                        symbol: "star.fill",
                        tint: .yellow
                    )

                    InsightMetricCard(
                        title: "Clipboard Items",
                        value: "\(todayItems.filter { $0.sourceKind == .clipboard }.count)",
                        symbol: "doc.on.clipboard.fill",
                        tint: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Activity by Category")
                        .font(.headline)

                    ForEach(MemoryLaneCategory.allCases.filter { $0 != .allApps }) { option in
                        let count = todayItems.filter(option.matches).count
                        HStack {
                            Label(option.title, systemImage: option.symbol)
                                .foregroundStyle(option.tint)
                            Spacer()
                            Text("\(count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                }
            }
            .padding(24)
        }
    }
}

private struct InsightMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(18)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
    }
}

@ViewBuilder
private func pageHeader(_ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
    HStack(spacing: 14) {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        Spacer()
    }
}

enum SidebarItem: Hashable {
    case today
    case timeline
    case search
    case favorites
    case clipboard
    case insights
    case settings
}

enum MemoryLaneCategory: String, CaseIterable, Identifiable {
    case allApps
    case web
    case email
    case chat
    case files
    case productivity
    case development
    case media
    case design
    case remoteAccess
    case system
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allApps: "All Apps"
        case .web: "Web Browsers"
        case .email: "Email"
        case .chat: "Chat & Meetings"
        case .files: "Files & Documents"
        case .productivity: "Productivity"
        case .development: "Development"
        case .media: "Media"
        case .design: "Design"
        case .remoteAccess: "Remote Access"
        case .system: "System"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .allApps: "square.grid.2x2.fill"
        case .web: "globe"
        case .email: "envelope.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .files: "folder.fill"
        case .productivity: "chart.bar.fill"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .media: "play.circle.fill"
        case .design: "paintbrush.fill"
        case .remoteAccess: "display"
        case .system: "gearshape.fill"
        case .other: "ellipsis"
        }
    }

    var tint: Color {
        switch self {
        case .allApps: .blue
        case .web: .cyan
        case .email: .orange
        case .chat: .purple
        case .files: .yellow
        case .productivity: .teal
        case .development: .orange
        case .media: .red
        case .design: .indigo
        case .remoteAccess: .cyan
        case .system: .gray
        case .other: .gray
        }
    }

    func matches(_ item: MemoryItem) -> Bool {
        if self == .allApps {
            return true
        }
        return Self.category(for: item) == self
    }

    static func category(for item: MemoryItem) -> MemoryLaneCategory {
        let app = "\(item.sourceApp) \(item.sourceBundleID)".lowercased()

        if app.contains("safari") || app.contains("chrome") || app.contains("firefox") || app.contains("edge") || app.contains("arc") || app.contains("browser") {
            return .web
        }

        if app.contains("outlook") || app.contains("mail") {
            return .email
        }

        if app.contains("teams") || app.contains("slack") || app.contains("messages") || app.contains("discord") || app.contains("zoom") || app.contains("webex") {
            return .chat
        }

        if item.sourceKind == .file || item.sourceKind == .screenshot || app.contains("finder") || app.contains("preview") {
            return .files
        }

        if app.contains("word") || app.contains("excel") || app.contains("powerpoint") || app.contains("onenote") || app.contains("notes") || app.contains("calendar") {
            return .productivity
        }

        if app.contains("xcode") || app.contains("terminal") || app.contains("iterm") || app.contains("visual studio") || app.contains("vscode") || app.contains("codex") || app.contains("github") {
            return .development
        }

        if app.contains("music") || app.contains("quicktime") || app.contains("vlc") || app.contains("photos") || app.contains("tv") {
            return .media
        }

        if app.contains("figma") || app.contains("sketch") || app.contains("photoshop") || app.contains("illustrator") || app.contains("canva") {
            return .design
        }

        if app.contains("remote desktop") || app.contains("screen sharing") || app.contains("citrix") || app.contains("vmware") || app.contains("anydesk") || app.contains("teamviewer") {
            return .remoteAccess
        }

        if app.contains("settings") || app.contains("system preferences") || app.contains("activity monitor") || app.contains("console") || app.contains("disk utility") {
            return .system
        }

        return .other
    }
}
