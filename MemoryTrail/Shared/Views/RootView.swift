import AppKit
import SwiftUI
import SwiftData

enum MemoryTrailPalette {
    static let canvasTop = Color(red: 0.91, green: 0.935, blue: 0.975)
    static let canvasBottom = Color(red: 0.86, green: 0.90, blue: 0.955)
    static let sidebarTop = Color(red: 0.89, green: 0.92, blue: 0.97)
    static let sidebarBottom = Color(red: 0.82, green: 0.87, blue: 0.94)
    static let surface = Color(red: 0.92, green: 0.945, blue: 0.975)
    static let elevated = Color(red: 0.965, green: 0.975, blue: 0.99)
    static let elevatedStrong = Color(red: 0.985, green: 0.99, blue: 1.0)
    static let border = Color(red: 0.39, green: 0.48, blue: 0.61).opacity(0.16)
    static let divider = Color(red: 0.42, green: 0.50, blue: 0.62).opacity(0.22)
}

struct RootView: View {
    @Environment(RecallPreferences.self) private var preferences
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var selection: SidebarItem?
    @State private var category: MemoryTrailCategory = .allApps
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
            MemoryTrailSidebar(
                memories: memories,
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
                        MemoryTrailPalette.canvasTop,
                        MemoryTrailPalette.canvasBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch activeSelection {
                    case .today:
                        TimelineView(memories: memories, category: $category)
                    case .search:
                        SearchView(memories: memories)
                    case .favorites:
                        FavoritesView(memories: memories)
                    case .clipboard:
                        ClipboardHistoryView(memories: memories)
                    case .insights:
                        InsightsView(memories: memories)
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
        .background(MemoryTrailPalette.canvasTop)
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
        }
    }
}

struct MemoryTrailSidebar: View {
    @Environment(RecallPreferences.self) private var preferences

    let memories: [MemoryItem]
    @Binding var selection: SidebarItem?
    @Binding var category: MemoryTrailCategory
    @State private var categoryCounts: [MemoryTrailCategory: Int] = [:]

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
                        sidebarButton(.search, title: "Ask Memory Trail", symbol: "magnifyingglass")
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
                        ForEach(availableCategories) { option in
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
                    MemoryTrailPalette.sidebarTop,
                    MemoryTrailPalette.sidebarBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear(perform: refreshCategoryCounts)
        .onChange(of: memories.count) { _, _ in
            refreshCategoryCounts()
        }
    }

    private var availableCategories: [MemoryTrailCategory] {
        [.allApps] + MemoryTrailCategory.allCases.filter {
            $0 != .allApps && categoryCounts[$0, default: 0] > 0
        }
    }

    private func refreshCategoryCounts() {
        var counts: [MemoryTrailCategory: Int] = [:]
        counts.reserveCapacity(MemoryTrailCategory.allCases.count)

        for item in memories where !item.isCaptureNoise {
            counts[.allApps, default: 0] += 1
            counts[MemoryTrailCategory.category(for: item), default: 0] += 1
        }

        categoryCounts = counts
    }

    private var brandHeader: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 64, height: 64)
                .shadow(color: Color.accentColor.opacity(0.18), radius: 14, y: 6)

            Text("Memory Trail")
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

    private func categoryButton(_ option: MemoryTrailCategory) -> some View {
        let count = categoryCounts[option, default: 0]
        let selected = category == option && selection == .today

        return Button {
            category = option
            selection = .today
        } label: {
            HStack(spacing: 10) {
                Image(systemName: option.symbol)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(option.filterTint)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [
                                option.filterBackground.opacity(0.96),
                                option.filterBackground.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(option.filterTint.opacity(0.12), lineWidth: 0.8)
                    }
                    .shadow(color: option.filterTint.opacity(0.08), radius: 2, y: 1)

                Text(option.title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(minWidth: 26, minHeight: 22)
                    .background(MemoryTrailPalette.elevated.opacity(0.92), in: Capsule())
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                selected ? Color(red: 0.10, green: 0.49, blue: 1.0).opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
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
            .background(MemoryTrailPalette.elevated.opacity(0.90), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct MemoryTrailScreenshotShell: View {
    @Environment(RecallPreferences.self) private var preferences
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    let selection: SidebarItem

    @State private var category: MemoryTrailCategory = .allApps

    var body: some View {
        HStack(spacing: 0) {
            MemoryTrailSidebar(
                memories: memories,
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
                        MemoryTrailPalette.canvasTop,
                        MemoryTrailPalette.canvasBottom
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selection {
                    case .today:
                        TimelineView(memories: memories, category: $category)
                    case .search:
                        SearchView(memories: memories)
                    case .favorites:
                        FavoritesView(memories: memories)
                    case .clipboard:
                        ClipboardHistoryView(memories: memories)
                    case .insights:
                        InsightsView(memories: memories)
                    case .settings:
                        SettingsView()
                    }
                }
            }
        }
        .background(MemoryTrailPalette.canvasTop)
    }
}

struct ClipboardHistoryView: View {
    let memories: [MemoryItem]
    @State private var searchText = ""

    private var items: [MemoryItem] {
        memories.filter {
            $0.sourceKind == .clipboard &&
            (searchText.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        let visibleItems = items

        return ScrollView {
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
                .background(MemoryTrailPalette.elevated.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
                .overlay {
                    RoundedRectangle(cornerRadius: 13)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                }

                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        "No Clipboard Items",
                        systemImage: "doc.on.clipboard",
                        description: Text("Copied text will appear here when clipboard capture is enabled.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(visibleItems) { item in
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
    let memories: [MemoryItem]
    @State private var range: InsightsRange = .today

    private var items: [MemoryItem] {
        let interval = range.interval
        return memories.filter {
            !$0.isCaptureNoise &&
            $0.createdAt >= interval.start &&
            $0.createdAt <= interval.end
        }
    }

    var body: some View {
        let visibleItems = items
        let activeSeconds = activeTime(for: visibleItems)
        let apps = appUsage(for: visibleItems)
        let slices = categorySlices(for: visibleItems)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                glanceCard(
                    items: visibleItems,
                    activeSeconds: activeSeconds
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        activityByAppCard(apps)
                            .frame(minWidth: 440, maxWidth: .infinity)
                            .frame(height: 430, alignment: .top)

                        VStack(spacing: 16) {
                            timeDistributionCard(
                                slices,
                                activeSeconds: activeSeconds
                            )
                            .frame(height: 258, alignment: .top)

                            activityPatternsCard(visibleItems)
                                .frame(height: 156, alignment: .top)
                        }
                        .frame(minWidth: 440, maxWidth: .infinity)
                    }

                    VStack(spacing: 16) {
                        activityByAppCard(apps)
                        timeDistributionCard(
                            slices,
                            activeSeconds: activeSeconds
                        )
                        activityPatternsCard(visibleItems)
                    }
                }

                topItemsCard(Array(visibleItems.prefix(4)))
            }
            .padding(24)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.allApps.filterTint)
                .frame(width: 48, height: 48)
                .background(
                    MemoryTrailCategory.allApps.filterBackground,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Insights")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("A visual summary of your activity, time, and focus.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 18)

            Picker("Range", selection: $range) {
                ForEach(InsightsRange.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 340)
        }
    }

    private func glanceCard(
        items: [MemoryItem],
        activeSeconds: TimeInterval
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MemoryTrailCategory.web.filterTint)
                    .frame(width: 34, height: 34)
                    .background(
                        MemoryTrailCategory.web.filterBackground,
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(range.glanceTitle)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text(range.dateSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 150), spacing: 12),
                    count: 4
                ),
                spacing: 12
            ) {
                InsightMetricCard(
                    title: "Activities",
                    value: "\(items.count)",
                    symbol: "rectangle.stack.fill",
                    tint: MemoryTrailCategory.allApps.filterTint,
                    background: MemoryTrailCategory.allApps.filterBackground
                )

                InsightMetricCard(
                    title: "Apps Used",
                    value: "\(Set(items.map(\.sourceApp)).count)",
                    symbol: "square.grid.2x2.fill",
                    tint: MemoryTrailCategory.chat.filterTint,
                    background: MemoryTrailCategory.chat.filterBackground
                )

                InsightMetricCard(
                    title: "Active Time",
                    value: durationLabel(activeSeconds),
                    symbol: "clock.fill",
                    tint: MemoryTrailCategory.remoteAccess.filterTint,
                    background: MemoryTrailCategory.remoteAccess.filterBackground
                )

                InsightMetricCard(
                    title: "Files & Docs",
                    value: "\(filesAndDocumentsCount(in: items))",
                    symbol: "doc.fill",
                    tint: MemoryTrailCategory.files.filterTint,
                    background: MemoryTrailCategory.files.filterBackground
                )
            }
        }
        .padding(18)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private func activityByAppCard(_ apps: [InsightsAppUsage]) -> some View {
        InsightsSectionCard(
            title: "Activity by App",
            symbol: "square.stack.3d.up.fill",
            tint: MemoryTrailCategory.allApps.filterTint
        ) {
            if apps.isEmpty {
                InsightsEmptyRow(text: "No app activity in this period.")
            } else {
                VStack(spacing: 11) {
                    ForEach(apps.prefix(7)) { app in
                        HStack(spacing: 11) {
                            InsightsAppIcon(
                                bundleID: app.bundleID,
                                category: app.category,
                                size: 34
                            )

                            Text(app.name)
                                .font(.system(size: 13.5, weight: .semibold))
                                .lineLimit(1)
                                .frame(width: 122, alignment: .leading)

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(app.category.filterBackground)

                                    Capsule()
                                        .fill(app.category.filterTint)
                                        .frame(
                                            width: max(
                                                8,
                                                geometry.size.width * app.fraction
                                            )
                                        )
                                }
                            }
                            .frame(height: 8)

                            Text("\(Int((app.fraction * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)

                            Text(durationLabel(app.seconds))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private func timeDistributionCard(
        _ slices: [InsightsCategorySlice],
        activeSeconds: TimeInterval
    ) -> some View {
        InsightsSectionCard(
            title: "Time Distribution",
            symbol: "chart.pie.fill",
            tint: MemoryTrailCategory.web.filterTint
        ) {
            if slices.isEmpty {
                InsightsEmptyRow(text: "No category activity in this period.")
            } else {
                HStack(alignment: .center, spacing: 22) {
                    Spacer(minLength: 0)

                    ZStack {
                        ForEach(slices) { slice in
                            Circle()
                                .trim(from: slice.start, to: slice.end)
                                .stroke(
                                    slice.tint,
                                    style: StrokeStyle(
                                        lineWidth: 27,
                                        lineCap: .butt
                                    )
                                )
                                .rotationEffect(.degrees(-90))
                        }

                        VStack(spacing: 2) {
                            Text(durationLabel(activeSeconds))
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                            Text("Active Time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 146, height: 146)
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices.prefix(6)) { slice in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(slice.tint)
                                    .frame(width: 9, height: 9)

                                Text(slice.title)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1)

                                Spacer(minLength: 6)

                                Text("\(Int((slice.fraction * 100).rounded()))%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func topItemsCard(_ topItems: [MemoryItem]) -> some View {
        InsightsSectionCard(
            title: "Top Items",
            symbol: "doc.text.fill",
            tint: MemoryTrailCategory.files.filterTint
        ) {
            if topItems.isEmpty {
                InsightsEmptyRow(text: "No recent items in this period.")
            } else {
                VStack(spacing: 0) {
                    ForEach(topItems) { item in
                        HStack(spacing: 11) {
                            let category = MemoryTrailCategory.category(for: item)

                            InsightsAppIcon(
                                bundleID: item.sourceBundleID,
                                category: category,
                                size: 36
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .lineLimit(1)

                                Text("\(item.sourceApp) • \(item.createdAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: category.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(category.filterTint)
                                .frame(width: 26, height: 26)
                                .background(
                                    category.filterBackground,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .padding(.vertical, 8)

                        if item.id != topItems.last?.id {
                            Divider()
                                .opacity(0.55)
                        }
                    }
                }
            }
        }
    }

    private func activityPatternsCard(_ items: [MemoryItem]) -> some View {
        let peak = peakFocus(in: items)
        let topCategory = topCategory(in: items)
        let appCount = Set(items.map(\.sourceApp)).count

        return InsightsSectionCard(
            title: "Activity Patterns",
            symbol: "chart.bar.fill",
            tint: MemoryTrailCategory.productivity.filterTint
        ) {
            VStack(spacing: 6) {
                InsightsPatternRow(
                    symbol: "scope",
                    title: "Peak Focus",
                    detail: peak,
                    category: .remoteAccess
                )

                InsightsPatternRow(
                    symbol: topCategory.symbol,
                    title: "Top Work Type",
                    detail: topCategory.title,
                    category: topCategory
                )

                InsightsPatternRow(
                    symbol: "bolt.fill",
                    title: "Quick Insight",
                    detail: appCount == 1
                        ? "You worked primarily in one app."
                        : "You moved across \(appCount) apps in this period.",
                    category: .files
                )
            }
        }
    }

    private func filesAndDocumentsCount(in items: [MemoryItem]) -> Int {
        items.filter {
            let category = MemoryTrailCategory.category(for: $0)
            return category == .files ||
                $0.sourceKind == .file ||
                category == .productivity
        }.count
    }

    private func activeTime(for items: [MemoryItem]) -> TimeInterval {
        let ascending = items.sorted { $0.createdAt < $1.createdAt }
        guard ascending.count > 1 else { return 0 }

        let inactivityThreshold: TimeInterval = 5 * 60
        var seconds: TimeInterval = 0

        for index in 0..<(ascending.count - 1) {
            let gap = ascending[index + 1].createdAt
                .timeIntervalSince(ascending[index].createdAt)

            if gap > 0, gap <= inactivityThreshold {
                seconds += gap
            }
        }

        return seconds
    }

    private func durationLookup(for items: [MemoryItem]) -> [UUID: TimeInterval] {
        let ascending = items.sorted { $0.createdAt < $1.createdAt }
        guard ascending.count > 1 else { return [:] }

        let inactivityThreshold: TimeInterval = 5 * 60
        var result: [UUID: TimeInterval] = [:]

        for index in 0..<(ascending.count - 1) {
            let item = ascending[index]
            let gap = ascending[index + 1].createdAt
                .timeIntervalSince(item.createdAt)

            if gap > 0, gap <= inactivityThreshold {
                result[item.id, default: 0] += gap
            }
        }

        return result
    }

    private func appUsage(for items: [MemoryItem]) -> [InsightsAppUsage] {
        let durations = durationLookup(for: items)
        let groups = Dictionary(grouping: items) {
            "\($0.sourceApp)|\($0.sourceBundleID)"
        }

        var apps = groups.values.compactMap { group -> InsightsAppUsage? in
            guard let first = group.first else { return nil }

            return InsightsAppUsage(
                name: first.sourceApp.isEmpty ? "Unknown App" : first.sourceApp,
                bundleID: first.sourceBundleID,
                category: MemoryTrailCategory.category(for: first),
                count: group.count,
                seconds: group.reduce(0) {
                    $0 + durations[$1.id, default: 0]
                },
                fraction: 0
            )
        }
        .sorted {
            if $0.seconds == $1.seconds {
                return $0.count > $1.count
            }
            return $0.seconds > $1.seconds
        }

        let totalSeconds = apps.reduce(0) { $0 + $1.seconds }
        let totalCount = max(1, apps.reduce(0) { $0 + $1.count })

        apps = apps.map { app in
            var updated = app
            updated.fraction = totalSeconds > 0
                ? app.seconds / totalSeconds
                : Double(app.count) / Double(totalCount)
            return updated
        }

        return apps
    }

    private func categorySlices(
        for items: [MemoryItem]
    ) -> [InsightsCategorySlice] {
        var counts: [MemoryTrailCategory: Int] = [:]

        for item in items {
            counts[MemoryTrailCategory.category(for: item), default: 0] += 1
        }

        let total = max(1, counts.values.reduce(0, +))
        var cursor = 0.0

        return counts
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { category, count in
                let fraction = Double(count) / Double(total)
                let slice = InsightsCategorySlice(
                    title: category.title,
                    fraction: fraction,
                    start: cursor,
                    end: cursor + fraction,
                    tint: category.filterTint
                )
                cursor += fraction
                return slice
            }
    }

    private func peakFocus(in items: [MemoryItem]) -> String {
        guard !items.isEmpty else { return "No focus window yet" }

        let calendar = Calendar.current
        var counts: [Int: Int] = [:]

        for item in items {
            counts[calendar.component(.hour, from: item.createdAt), default: 0] += 1
        }

        guard let peakHour = counts.max(by: { $0.value < $1.value })?.key else {
            return "No focus window yet"
        }

        let start = calendar.date(
            bySettingHour: peakHour,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start

        return "Most active \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private func topCategory(in items: [MemoryItem]) -> MemoryTrailCategory {
        var counts: [MemoryTrailCategory: Int] = [:]
        for item in items {
            counts[MemoryTrailCategory.category(for: item), default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .other
    }

    private func durationLabel(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        if totalMinutes == 0 {
            return seconds > 0 ? "<1m" : "0m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private enum InsightsRange: String, CaseIterable, Identifiable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    var glanceTitle: String {
        switch self {
        case .today: "Today at a Glance"
        case .week: "This Week at a Glance"
        case .month: "This Month at a Glance"
        }
    }

    var interval: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        switch self {
        case .today:
            return DateInterval(start: today, end: now)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return DateInterval(start: start, end: now)
        case .month:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return DateInterval(start: start, end: now)
        }
    }

    var dateSubtitle: String {
        switch self {
        case .today:
            return Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        case .week:
            return "Rolling 7-day activity summary"
        case .month:
            return "Rolling 30-day activity summary"
        }
    }
}

private struct InsightsAppUsage: Identifiable {
    let name: String
    let bundleID: String
    let category: MemoryTrailCategory
    let count: Int
    let seconds: TimeInterval
    var fraction: Double

    var id: String { "\(name)|\(bundleID)" }
}

private struct InsightsCategorySlice: Identifiable {
    let title: String
    let fraction: Double
    let start: Double
    let end: Double
    let tint: Color

    var id: String { title }
}

private struct InsightMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(background, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            background.opacity(0.56),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct InsightsSectionCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let content: Content

    init(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct InsightsEmptyRow: View {
    let text: String

    var body: some View {
        ContentUnavailableView(
            "Nothing to show yet",
            systemImage: "chart.bar",
            description: Text(text)
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct InsightsAppIcon: View {
    let bundleID: String
    let category: MemoryTrailCategory
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(category.filterBackground)

            if let icon = AppIconCache.shared.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.10)
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(category.filterTint)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(category.filterTint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct InsightsPatternRow: View {
    let symbol: String
    let title: String
    let detail: String
    let category: MemoryTrailCategory

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(category.filterTint)
                .frame(width: 34, height: 34)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            category.filterBackground.opacity(0.52),
            in: RoundedRectangle(cornerRadius: 13)
        )
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
    case search
    case favorites
    case clipboard
    case insights
    case settings
}

enum MemoryTrailCategory: String, CaseIterable, Identifiable, Hashable {
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

    // Sidebar filter palette: approved Soft Blue treatment.
    // Kept separate from `tint` so timeline/insight colors are unchanged.
    var filterTint: Color {
        switch self {
        case .allApps: Color(red: 0.09, green: 0.50, blue: 1.00)
        case .web: Color(red: 0.11, green: 0.68, blue: 0.91)
        case .email: Color(red: 0.14, green: 0.52, blue: 1.00)
        case .chat: Color(red: 0.41, green: 0.40, blue: 0.91)
        case .files: Color(red: 0.93, green: 0.69, blue: 0.08)
        case .productivity: Color(red: 0.16, green: 0.67, blue: 0.89)
        case .development: Color(red: 0.15, green: 0.48, blue: 0.95)
        case .media: Color(red: 0.35, green: 0.52, blue: 0.91)
        case .design: Color(red: 0.46, green: 0.40, blue: 0.88)
        case .remoteAccess: Color(red: 0.12, green: 0.65, blue: 0.84)
        case .system, .other: Color(red: 0.54, green: 0.59, blue: 0.66)
        }
    }

    var filterBackground: Color {
        switch self {
        case .allApps: Color(red: 0.87, green: 0.93, blue: 1.00)
        case .web: Color(red: 0.89, green: 0.96, blue: 1.00)
        case .email: Color(red: 0.90, green: 0.94, blue: 1.00)
        case .chat: Color(red: 0.93, green: 0.92, blue: 1.00)
        case .files: Color(red: 1.00, green: 0.97, blue: 0.85)
        case .productivity: Color(red: 0.89, green: 0.96, blue: 1.00)
        case .development: Color(red: 0.90, green: 0.94, blue: 1.00)
        case .media: Color(red: 0.91, green: 0.94, blue: 1.00)
        case .design: Color(red: 0.94, green: 0.93, blue: 1.00)
        case .remoteAccess: Color(red: 0.89, green: 0.96, blue: 0.98)
        case .system, .other: Color(red: 0.94, green: 0.95, blue: 0.97)
        }
    }

    func matches(_ item: MemoryItem) -> Bool {
        if self == .allApps {
            return true
        }
        return Self.category(for: item) == self
    }

    static func category(for item: MemoryItem) -> MemoryTrailCategory {
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
