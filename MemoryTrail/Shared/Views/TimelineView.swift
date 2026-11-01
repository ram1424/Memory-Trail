import AppKit
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecallPreferences.self) private var preferences
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    @Binding var category: MemoryTrailCategory

    @State private var selectedMemoryID: UUID?
    @State private var dayOffset = 0
    @State private var showingClearTimelineConfirmation = false
    @State private var now = Date()
    @AppStorage("today.showPanels") private var showsPanels = true

    var body: some View {
        let dayItems = itemsForSelectedDay
        let visibleItems = filteredItems(dayItems)
        let durations = durationLookup(for: dayItems)

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar(dayItems: dayItems)
                quickFilters(dayItems: dayItems)

                Divider()
                    .opacity(0.45)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if visibleItems.isEmpty {
                            emptyState
                        } else {
                            dayHeading(count: visibleItems.count)
                            activityList(
                                visibleItems,
                                durations: durations
                            )
                        }
                    }
                    .padding(20)
                }
            }
            .frame(minWidth: 590, maxWidth: .infinity)

            if showsPanels {
                Divider()
                    .opacity(0.55)

                TimelineSummaryColumn(
                    dayItems: dayItems,
                    selectedItem: selectedItem,
                    selectedDuration: selectedItem.map { durations[$0.id] ?? 0 } ?? 0,
                    selectedDay: selectedDay,
                    preferences: preferences,
                    onFavorite: toggleFavorite,
                    onDelete: deleteSelectedItem
                )
                .frame(width: 365)
            }
        }
        .background(
            LinearGradient(
                colors: [
                    MemoryTrailPalette.canvasTop,
                    MemoryTrailPalette.canvasBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    showingClearTimelineConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(memories.isEmpty)
                .help("Clear Timeline")
            }
        }
        .confirmationDialog(
            "Clear Timeline?",
            isPresented: $showingClearTimelineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Entire Timeline", role: .destructive) {
                clearTimeline()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all \(memories.count) timeline items from Memory Trail.")
        }
        .onAppear {
            ensureSelection(in: visibleItems)
        }
        .onChange(of: visibleItems.map(\.id)) { _, _ in
            ensureSelection(in: visibleItems)

            if category != .allApps,
               !dayItems.contains(where: { category.matches($0) }) {
                category = .allApps
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { value in
            now = value
        }
    }

    private func topBar(dayItems: [MemoryItem]) -> some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsPanels.toggle()
                }
            } label: {
                Label(
                    showsPanels ? "Hide Panels" : "Show Panels",
                    systemImage: "sidebar.right"
                )
                .font(.system(size: 13.5, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .background(
                MemoryTrailPalette.elevatedStrong.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            }
            .help(
                showsPanels
                    ? "Hide Today Summary and Activity Details"
                    : "Show Today Summary and Activity Details"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func quickFilters(dayItems: [MemoryItem]) -> some View {
        let used = Set(dayItems.map { MemoryTrailCategory.category(for: $0) })
        let dynamicOptions = [.allApps] + MemoryTrailCategory.allCases.filter {
            $0 != .allApps && used.contains($0)
        }
        let primaryOptions = Array(dynamicOptions.prefix(6))
        let overflowOptions = Array(dynamicOptions.dropFirst(6))

        return HStack(spacing: 8) {
            ForEach(primaryOptions) { option in
                let count = dayItems.filter { option.matches($0) }.count
                Button {
                    withAnimation(.easeOut(duration: 0.12)) {
                        category = option
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(option == .productivity ? "Apps" : quickTitle(for: option))
                        Text("(\(count))")
                            .foregroundStyle(category == option ? Color.white.opacity(0.88) : Color.secondary)
                    }
                    .font(.system(size: 12.5, weight: category == option ? .semibold : .medium))
                    .foregroundStyle(category == option ? Color.white : Color.primary)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(
                        category == option
                            ? Color.accentColor
                            : MemoryTrailPalette.elevated.opacity(0.92),
                        in: Capsule()
                    )
                    .overlay {
                        if category != option {
                            Capsule()
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if !overflowOptions.isEmpty {
                Menu {
                    ForEach(overflowOptions) { option in
                        Button {
                            category = option
                        } label: {
                            Label(option.title, systemImage: option.symbol)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(MemoryTrailPalette.elevated.opacity(0.92), in: Circle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Circle()
                    .fill(preferences.capturePaused ? Color.orange : Color.green)
                    .frame(width: 9, height: 9)

                Text(preferences.capturePaused ? "Paused" : "Capturing")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                Button {
                    dayOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                }

                Text(dayOffset == 0 ? "Today" : selectedDay.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 76)

                Button {
                    if dayOffset < 0 {
                        dayOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                }
                .disabled(dayOffset >= 0)
            }
            .buttonStyle(.plain)
            .background(MemoryTrailPalette.elevated.opacity(0.94), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func quickTitle(for category: MemoryTrailCategory) -> String {
        switch category {
        case .allApps: "All"
        case .web: "Web"
        case .email: "Email"
        case .chat: "Chat"
        case .files: "Files"
        default: category.title
        }
    }

    private func dayHeading(count: Int) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dayOffset == 0 ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 27, weight: .bold, design: .rounded))

                Text(selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(count) activit\(count == 1 ? "y" : "ies")")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func activityList(
        _ items: [MemoryItem],
        durations: [UUID: TimeInterval]
    ) -> some View {
        LazyVStack(spacing: 1) {
            ForEach(items) { item in
                BrightTimelineRow(
                    item: item,
                    duration: durations[item.id] ?? 0,
                    isSelected: selectedMemoryID == item.id,
                    latestBadge: latestBadge(for: item),
                    timelineTint: .blue,
                    onSelect: {
                        selectedMemoryID = item.id
                    },
                    onFavorite: {
                        item.isFavorite.toggle()
                        try? modelContext.save()
                    },
                    onDelete: {
                        if selectedMemoryID == item.id {
                            selectedMemoryID = nil
                        }
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                )
            }
        }
        .padding(10)
        .background(
            MemoryTrailPalette.surface.opacity(0.88),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            memories.isEmpty ? "Your timeline is empty" : "No matching activity",
            systemImage: memories.isEmpty ? "sparkles" : "magnifyingglass",
            description: Text(memories.isEmpty
                ? "Open a few apps to start building your private activity history."
                : "Try a different activity filter or day.")
        )
        .frame(maxWidth: .infinity, minHeight: 460)
        .background(MemoryTrailPalette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 22))
    }

    private var selectedDay: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
    }

    private var itemsForSelectedDay: [MemoryItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        return memories.filter {
            $0.createdAt >= start &&
            $0.createdAt < end &&
            !$0.isCaptureNoise
        }
    }

    private func filteredItems(_ dayItems: [MemoryItem]) -> [MemoryItem] {
        dayItems.filter { category.matches($0) }
    }

    private func latestBadge(for item: MemoryItem) -> LatestActivityBadge? {
        guard dayOffset == 0,
              item.id == itemsForSelectedDay.first?.id
        else {
            return nil
        }

        let age = max(0, now.timeIntervalSince(item.createdAt))
        if age <= 2 * 60 {
            return .live
        }

        return .latest
    }

    private func durationLookup(for items: [MemoryItem]) -> [UUID: TimeInterval] {
        var result: [UUID: TimeInterval] = [:]
        result.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            let duration: TimeInterval

            if index == 0 {
                duration = Calendar.current.isDateInToday(item.createdAt)
                    ? min(max(0, now.timeIntervalSince(item.createdAt)), 30 * 60)
                    : 0
            } else {
                let newer = items[index - 1]
                duration = min(max(0, newer.createdAt.timeIntervalSince(item.createdAt)), 90 * 60)
            }

            result[item.id] = duration
        }

        return result
    }

    private var selectedItem: MemoryItem? {
        guard let selectedMemoryID else { return nil }
        return memories.first { $0.id == selectedMemoryID }
    }

    private func ensureSelection(in items: [MemoryItem]) {
        if let selectedMemoryID, items.contains(where: { $0.id == selectedMemoryID }) {
            return
        }
        selectedMemoryID = items.first?.id
    }

    private func toggleFavorite() {
        guard let selectedItem else { return }
        selectedItem.isFavorite.toggle()
        try? modelContext.save()
    }

    private func deleteSelectedItem() {
        guard let selectedItem else { return }
        modelContext.delete(selectedItem)
        try? modelContext.save()
        selectedMemoryID = nil
    }

    private func clearTimeline() {
        for item in memories {
            modelContext.delete(item)
        }
        try? modelContext.save()
        selectedMemoryID = nil
    }
}

private enum LatestActivityBadge {
    case live
    case latest

    var title: String {
        switch self {
        case .live: "Live Activity"
        case .latest: "Latest"
        }
    }

    var tint: Color {
        switch self {
        case .live: .green
        case .latest: .blue
        }
    }
}

private struct BrightTimelineRow: View {
    let item: MemoryItem
    let duration: TimeInterval
    let isSelected: Bool
    let latestBadge: LatestActivityBadge?
    let timelineTint: Color
    let onSelect: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)

            ZStack {
                Rectangle()
                    .fill(timelineTint.opacity(0.55))
                    .frame(width: 2)

                Circle()
                    .fill(timelineTint)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 16, height: 58)

            sourceIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)

                    if let latestBadge {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(latestBadge.tint)
                                .frame(width: 6, height: 6)

                            Text(latestBadge.title)
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(latestBadge.tint)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(latestBadge.tint.opacity(0.12), in: Capsule())
                    }
                }

                Text(item.sourceApp)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(activityLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(activityTint)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(activityTint.opacity(0.12), in: Capsule())

            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.isFavorite ? Color.orange : Color.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            Menu {
                Button("Copy Details", systemImage: "doc.on.doc") {
                    copyDetails()
                }

                Button("Open Source App", systemImage: "arrow.up.forward.app") {
                    openSource()
                }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    onDelete()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 30)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: 62)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.08)
                : MemoryTrailPalette.elevated.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.08),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onTapGesture(perform: onSelect)
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(activityTint)
                .frame(width: 34, height: 34)
                .background(activityTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private var fallbackSymbol: String {
        switch MemoryTrailCategory.category(for: item) {
        case .web: "globe"
        case .email: "envelope.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .files: "folder.fill"
        case .productivity: "doc.text.fill"
        case .development: "chevron.left.forwardslash.chevron.right"
        case .media: "play.fill"
        case .design: "paintbrush.fill"
        case .remoteAccess: "display"
        case .system: "gearshape.fill"
        default: item.sourceKind.symbol
        }
    }

    private var activityLabel: String {
        let app = "\(item.sourceApp) \(item.displayTitle)".lowercased()

        if app.contains("outlook") || app.contains("mail") { return "Email" }
        if app.contains("teams") || app.contains("slack") || app.contains("messages") { return "Chat" }
        if app.contains("excel") || app.contains(".xlsx") { return "Spreadsheet" }
        if app.contains("onenote") || app.contains("notes") { return "Notes" }
        if app.contains("word") || app.contains(".doc") { return "Document" }
        if app.contains("powerpoint") || app.contains(".ppt") { return "Presentation" }
        if MemoryTrailCategory.category(for: item) == .web { return "Web" }
        if item.sourceKind == .clipboard { return "Clipboard" }
        if item.sourceKind == .file { return "File" }
        return MemoryTrailCategory.category(for: item).title
    }

    private var activityTint: Color {
        switch activityLabel {
        case "Email", "Document": .blue
        case "Web", "Spreadsheet": .green
        case "Chat", "Notes": .purple
        case "Presentation": .orange
        case "File", "Clipboard": .orange
        default: MemoryTrailCategory.category(for: item).tint
        }
    }

    private func copyDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            [item.displayTitle, item.body, item.sourceApp, item.sourceURL ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            forType: .string
        )
    }

    private func openSource() {
        if let sourceURL = item.sourceURL,
           let url = URL(string: sourceURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            return
        }

        guard !item.sourceBundleID.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.sourceBundleID)
        else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct TimelineSummaryColumn: View {
    let dayItems: [MemoryItem]
    let selectedItem: MemoryItem?
    let selectedDuration: TimeInterval
    let selectedDay: Date
    let preferences: RecallPreferences
    let onFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusBar
                summaryCard

                if let selectedItem {
                    detailCard(selectedItem)
                } else {
                    ContentUnavailableView(
                        "Select an activity",
                        systemImage: "cursorarrow.click.2",
                        description: Text("Choose an item in Today to see its details.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .background(MemoryTrailPalette.elevated.opacity(0.90), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(14)
        }
        .background(MemoryTrailPalette.surface)
    }

    private var statusBar: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(preferences.capturePaused ? Color.orange : Color.green)
                .frame(width: 10, height: 10)

            Text(preferences.capturePaused ? "Paused" : "Capturing")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Image(systemName: "calendar")
                .foregroundStyle(.secondary)

            Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Today Summary", systemImage: "chart.bar.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SummaryMetricTile(
                    value: "\(dayItems.count)",
                    label: "Total Activities",
                    symbol: "chart.bar.fill",
                    tint: .cyan
                )

                SummaryMetricTile(
                    value: "\(Set(dayItems.map(\.sourceApp)).count)",
                    label: "Apps Used",
                    symbol: "square.grid.2x2.fill",
                    tint: .blue
                )

                SummaryMetricTile(
                    value: activeTimeLabel,
                    label: "Active Time",
                    symbol: "clock.fill",
                    tint: .teal
                )

                SummaryMetricTile(
                    value: "\(dayItems.filter { $0.sourceKind == .clipboard }.count)",
                    label: "Clipboard Items",
                    symbol: "doc.on.clipboard.fill",
                    tint: .orange
                )
            }
        }
        .padding(16)
        .background(MemoryTrailPalette.elevatedStrong.opacity(0.94), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func detailCard(_ item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                detailIcon(item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 5) {
                        Text(item.sourceApp)
                        Text("•")
                        Text(detailType(item))
                        Text("•")
                        Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                        if selectedDuration >= 60 {
                            Text("•")
                            Text(durationLabel)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(item.isFavorite ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        onDelete()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Divider()

            detailLine("App", item.sourceApp)
            detailLine("Type", detailType(item))
            detailLine("Time", item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let sender = sender(from: item.body) {
                detailLine("From", sender)
            }

            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                detailLine(sourceURL.hasPrefix("/") ? "Path" : "URL", sourceURL)
            }

            detailLine("Window", item.displayTitle)

            Divider()

            Button {
                open(item)
            } label: {
                Label(openButtonTitle(item), systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.displayTitle, forType: .string)
            } label: {
                Label("Copy Subject", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(MemoryTrailPalette.elevatedStrong.opacity(0.96), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func detailIcon(_ item: MemoryItem) -> some View {
        if let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 44, height: 44)
        } else {
            Image(systemName: MemoryTrailCategory.category(for: item).symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.category(for: item).tint)
                .frame(width: 44, height: 44)
                .background(
                    MemoryTrailCategory.category(for: item).tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
    }

    private var activeTimeLabel: String {
        guard dayItems.count > 1 else {
            return "0m"
        }

        // Active Time measures observed elapsed work, not the number of events.
        // Consecutive records belong to the same active session only when they
        // are close together. Clicking several times in a few seconds therefore
        // adds only those few seconds instead of a forced minute per click.
        let inactivityThreshold: TimeInterval = 5 * 60
        let ascending = dayItems.sorted { $0.createdAt < $1.createdAt }
        var seconds: TimeInterval = 0

        for index in 0..<(ascending.count - 1) {
            let gap = ascending[index + 1].createdAt.timeIntervalSince(ascending[index].createdAt)

            if gap > 0, gap <= inactivityThreshold {
                seconds += gap
            }
        }

        let totalSeconds = max(0, Int(seconds))
        if totalSeconds == 0 {
            return "0m"
        }
        if totalSeconds < 60 {
            return "<1m"
        }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    private var durationLabel: String {
        let minutes = max(1, Int(selectedDuration / 60))
        return "\(minutes) min"
    }

    private func detailType(_ item: MemoryItem) -> String {
        switch MemoryTrailCategory.category(for: item) {
        case .email: "Email"
        case .chat: "Chat"
        case .web: "Web"
        case .files: "File"
        case .productivity: "Document"
        case .development: "Development"
        case .media: "Media"
        case .design: "Design"
        case .remoteAccess: "Remote Access"
        case .system: "System"
        default: item.sourceKind.rawValue
        }
    }

    private func sender(from body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("from:") else { return nil }
        let value = String(trimmed.dropFirst("from:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func openButtonTitle(_ item: MemoryItem) -> String {
        let app = item.sourceApp
        return app.isEmpty ? "Open Source" : "Open in \(app)"
    }

    private func open(_ item: MemoryItem) {
        if let sourceURL = item.sourceURL,
           let url = URL(string: sourceURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            return
        }

        guard !item.sourceBundleID.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.sourceBundleID)
        else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct SummaryMetricTile: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 66)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        }
    }
}

struct MemoryRow: View {
    let item: MemoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            sourceIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if !secondaryTitle.isEmpty {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }

                if !item.body.isEmpty && item.body != secondaryTitle {
                    Text(item.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    Text(item.sourceApp)
                    Text("•")
                    Text(item.sourceKind.rawValue)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(MemoryTrailPalette.elevated.opacity(0.94), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: item.sourceKind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundStyle(.tint)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var primaryTitle: String {
        item.sourceKind == .appActivity ? item.sourceApp : item.title
    }

    private var secondaryTitle: String {
        guard item.sourceKind == .appActivity else { return "" }
        return item.title.hasPrefix("Opened ") ? "" : item.displayTitle
    }
}

@MainActor
final class AppIconCache {
    static let shared = AppIconCache()

    private let cache = NSCache<NSString, NSImage>()
    private var unresolved = Set<String>()

    func icon(for bundleID: String) -> NSImage? {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let key = normalized.lowercased() as NSString

        if let cached = cache.object(forKey: key) {
            return cached
        }

        if unresolved.contains(key as String) {
            return nil
        }

        let icon: NSImage?

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalized) {
            icon = NSWorkspace.shared.icon(forFile: appURL.path)
        } else if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            icon = runningApp.icon ?? runningApp.bundleURL.map {
                NSWorkspace.shared.icon(forFile: $0.path)
            }
        } else {
            icon = nil
        }

        if let icon {
            cache.setObject(icon, forKey: key)
            return icon
        }

        unresolved.insert(key as String)
        return nil
    }
}
