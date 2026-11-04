import AppKit
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecallPreferences.self) private var preferences

    let memories: [MemoryItem]
    @Binding var category: MemoryTrailCategory

    @State private var selectedMemoryID: UUID?
    @State private var dayOffset = 0
    @State private var pendingTimelineClear: MemoryTrailHistoryClearRange?
    @State private var now = Date()

    var body: some View {
        let dayItems = itemsForSelectedDay
        let visibleItems = filteredItems(dayItems)
        let durations = durationLookup(for: dayItems)
        let latestItemID = dayItems.first?.id
        let topApps = appUsage(for: dayItems)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                todayHeader

                atAGlanceCard(
                    items: dayItems,
                    activeSeconds: activeTime(for: dayItems)
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        timelineCard(
                            visibleItems,
                            dayItems: dayItems,
                            durations: durations,
                            latestItemID: latestItemID
                        )
                        .frame(minWidth: 620, maxWidth: .infinity)

                        VStack(spacing: 14) {
                            topAppsCard(topApps)
                            keyTakeawaysCard(dayItems)
                            recentDocumentsCard(dayItems)
                        }
                        .frame(width: 390)
                    }

                    VStack(spacing: 16) {
                        timelineCard(
                            visibleItems,
                            dayItems: dayItems,
                            durations: durations,
                            latestItemID: latestItemID
                        )

                        topAppsCard(topApps)
                        keyTakeawaysCard(dayItems)
                        recentDocumentsCard(dayItems)
                    }
                }
            }
            .padding(20)
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
                    pendingTimelineClear = .all
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(memories.isEmpty)
                .help("Clear Timeline")
            }
        }
        .sheet(item: $pendingTimelineClear) { range in
            MemoryTrailHistoryClearSheet(
                range: range,
                onCancel: {
                    pendingTimelineClear = nil
                },
                onConfirm: {
                    clearTimeline()
                    pendingTimelineClear = nil
                }
            )
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

    private var todayHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.allApps.filterTint)
                .frame(width: 48, height: 48)
                .background(
                    MemoryTrailCategory.allApps.filterBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(dayOffset == 0 ? "Today" : selectedDay.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 29, weight: .bold, design: .rounded))

                Text("Your activity, files, and conversations at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Circle()
                    .fill(preferences.capturePaused ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)

                Text(preferences.capturePaused ? "Paused" : "Capturing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(
                MemoryTrailPalette.elevatedStrong.opacity(0.92),
                in: Capsule()
            )

            if dayOffset != 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        dayOffset = 0
                    }
                } label: {
                    Label("Go to Today", systemImage: "arrow.uturn.forward.circle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MemoryTrailCategory.allApps.filterTint)
                .background(
                    MemoryTrailCategory.allApps.filterBackground,
                    in: Capsule()
                )
                .help("Return to today")
            }

            HStack(spacing: 0) {
                Button {
                    dayOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }

                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text(selectedDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .frame(minWidth: 138)

                Button {
                    if dayOffset < 0 {
                        dayOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .disabled(dayOffset >= 0)
            }
            .buttonStyle(.plain)
            .background(
                MemoryTrailPalette.elevatedStrong.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
    }

    private func atAGlanceCard(
        items: [MemoryItem],
        activeSeconds: TimeInterval
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(
                dayOffset == 0 ? "Today at a Glance" : "Day at a Glance",
                systemImage: "square.stack.3d.up.fill"
            )
            .font(.system(size: 17, weight: .bold, design: .rounded))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    glanceMetric(
                        value: "\(items.count)",
                        label: "Activities",
                        symbol: "rectangle.stack.fill",
                        category: .allApps
                    )

                    glanceMetric(
                        value: "\(Set(items.map(\.sourceApp)).count)",
                        label: "Apps Used",
                        symbol: "square.grid.2x2.fill",
                        category: .chat
                    )

                    glanceMetric(
                        value: durationLabel(activeSeconds),
                        label: "Active Time",
                        symbol: "clock.fill",
                        category: .remoteAccess
                    )

                    glanceMetric(
                        value: "\(filesAndDocumentsCount(in: items))",
                        label: "Files & Documents",
                        symbol: "doc.fill",
                        category: .files
                    )

                    glanceMetric(
                        value: "\(items.filter { $0.sourceKind == .clipboard }.count)",
                        label: "Clipboard Items",
                        symbol: "doc.on.clipboard.fill",
                        category: .design
                    )
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170), spacing: 10)],
                    spacing: 10
                ) {
                    glanceMetric(
                        value: "\(items.count)",
                        label: "Activities",
                        symbol: "rectangle.stack.fill",
                        category: .allApps
                    )
                    glanceMetric(
                        value: "\(Set(items.map(\.sourceApp)).count)",
                        label: "Apps Used",
                        symbol: "square.grid.2x2.fill",
                        category: .chat
                    )
                    glanceMetric(
                        value: durationLabel(activeSeconds),
                        label: "Active Time",
                        symbol: "clock.fill",
                        category: .remoteAccess
                    )
                    glanceMetric(
                        value: "\(filesAndDocumentsCount(in: items))",
                        label: "Files & Documents",
                        symbol: "doc.fill",
                        category: .files
                    )
                    glanceMetric(
                        value: "\(items.filter { $0.sourceKind == .clipboard }.count)",
                        label: "Clipboard Items",
                        symbol: "doc.on.clipboard.fill",
                        category: .design
                    )
                }
            }
        }
        .padding(16)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private func glanceMetric(
        value: String,
        label: String,
        symbol: String,
        category: MemoryTrailCategory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(category.filterTint)
                .frame(width: 38, height: 38)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            category.filterBackground.opacity(0.48),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(category.filterTint.opacity(0.10), lineWidth: 1)
        }
    }

    private func timelineCard(
        _ items: [MemoryItem],
        dayItems: [MemoryItem],
        durations: [UUID: TimeInterval],
        latestItemID: UUID?
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MemoryTrailCategory.allApps.filterTint)
                    .frame(width: 42, height: 42)
                    .background(
                        MemoryTrailCategory.allApps.filterBackground,
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(dayOffset == 0 ? "Today’s Timeline" : "Activity Timeline")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("A chronological view of your activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                timelineFilter(dayItems: dayItems)
            }

            Divider()
                .opacity(0.55)

            if items.isEmpty {
                ContentUnavailableView(
                    memories.isEmpty ? "Your timeline is empty" : "No matching activity",
                    systemImage: memories.isEmpty ? "sparkles" : "magnifyingglass",
                    description: Text(memories.isEmpty
                        ? "Open a few apps to start building your private activity history."
                        : "Try a different activity filter or day.")
                )
                .frame(maxWidth: .infinity, minHeight: 430)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(items) { item in
                        BrightTimelineRow(
                            item: item,
                            duration: durations[item.id] ?? 0,
                            isSelected: selectedMemoryID == item.id,
                            latestBadge: latestBadge(
                                for: item,
                                latestItemID: latestItemID
                            ),
                            timelineTint: MemoryTrailCategory
                                .category(for: item)
                                .filterTint,
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
            }
        }
        .padding(16)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(MemoryTrailCategory.allApps.filterTint.opacity(0.16), lineWidth: 1)
        }
    }

    private func timelineFilter(dayItems: [MemoryItem]) -> some View {
        let used = Set(dayItems.map { MemoryTrailCategory.category(for: $0) })
        let options = [.allApps] + MemoryTrailCategory.allCases.filter {
            $0 != .allApps && used.contains($0)
        }

        return Menu {
            ForEach(options) { option in
                Button {
                    category = option
                } label: {
                    Label(
                        option.title,
                        systemImage: category == option
                            ? "checkmark.circle.fill"
                            : option.symbol
                    )
                }
            }
        } label: {
            HStack(spacing: 7) {
                Text(category == .allApps ? "All Activity" : category.title)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                MemoryTrailPalette.surface.opacity(0.94),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func topAppsCard(_ apps: [TodayAppUsage]) -> some View {
        dashboardCard(
            title: "Top Apps Today",
            symbol: "square.stack.3d.up.fill",
            tint: MemoryTrailCategory.allApps.filterTint
        ) {
            if apps.isEmpty {
                smallEmptyState("No app activity yet.")
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(apps.prefix(6))) { app in
                        VStack(spacing: 6) {
                            TodayAppIcon(
                                bundleID: app.bundleID,
                                category: app.category,
                                size: 42
                            )

                            Text(app.name)
                                .font(.system(size: 10.5, weight: .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.72)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)

                            Text(durationLabel(app.seconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
    }

    private func keyTakeawaysCard(_ items: [MemoryItem]) -> some View {
        let topCategory = topCategory(in: items)
        let appCount = Set(items.map(\.sourceApp)).count

        return dashboardCard(
            title: "Key Takeaways",
            symbol: "sparkles",
            tint: MemoryTrailCategory.chat.filterTint
        ) {
            VStack(spacing: 9) {
                takeawayRow(
                    symbol: "scope",
                    title: "Peak Focus",
                    detail: peakFocus(in: items),
                    category: .remoteAccess
                )

                takeawayRow(
                    symbol: topCategory.symbol,
                    title: "Top Work Type",
                    detail: topCategory.title,
                    category: topCategory
                )

                takeawayRow(
                    symbol: "bolt.fill",
                    title: "App Switching",
                    detail: appCount <= 1
                        ? "You stayed focused in one app."
                        : "\(appCount) apps used during this period.",
                    category: .files
                )
            }
        }
    }

    private func recentDocumentsCard(_ items: [MemoryItem]) -> some View {
        let documents = items.filter {
            let category = MemoryTrailCategory.category(for: $0)
            return category == .files ||
                category == .productivity ||
                $0.sourceKind == .file
        }
        .prefix(3)

        return dashboardCard(
            title: "Recent Files & Documents",
            symbol: "doc.text.fill",
            tint: MemoryTrailCategory.files.filterTint
        ) {
            if documents.isEmpty {
                smallEmptyState("No recent files or documents.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(documents)) { item in
                        Button {
                            open(item)
                        } label: {
                            HStack(spacing: 10) {
                                let itemCategory = MemoryTrailCategory.category(for: item)

                                TodayAppIcon(
                                    bundleID: item.sourceBundleID,
                                    category: itemCategory,
                                    size: 32
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.displayTitle)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(itemCategory.filterTint)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        if item.id != documents.last?.id {
                            Divider()
                                .opacity(0.5)
                        }
                    }
                }
            }
        }
    }

    private func dashboardCard<Content: View>(
        title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        }
    }

    private func takeawayRow(
        symbol: String,
        title: String,
        detail: String,
        category: MemoryTrailCategory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(category.filterTint)
                .frame(width: 32, height: 32)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 9)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            category.filterBackground.opacity(0.48),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private func smallEmptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }

    private var selectedDay: Date {
        Calendar.current.date(
            byAdding: .day,
            value: dayOffset,
            to: Date()
        ) ?? Date()
    }

    private var itemsForSelectedDay: [MemoryItem] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start

        var result: [MemoryItem] = []
        for item in memories {
            if item.createdAt >= end {
                continue
            }
            if item.createdAt < start {
                break
            }
            if !item.isCaptureNoise {
                result.append(item)
            }
        }
        return result
    }

    private func filteredItems(_ dayItems: [MemoryItem]) -> [MemoryItem] {
        dayItems.filter { category.matches($0) }
    }

    private func latestBadge(
        for item: MemoryItem,
        latestItemID: UUID?
    ) -> LatestActivityBadge? {
        guard dayOffset == 0,
              item.id == latestItemID
        else {
            return nil
        }

        let age = max(0, now.timeIntervalSince(item.createdAt))
        return age <= 2 * 60 ? .live : .latest
    }

    private func durationLookup(
        for items: [MemoryItem]
    ) -> [UUID: TimeInterval] {
        let ascending = items.sorted { $0.createdAt < $1.createdAt }
        guard !ascending.isEmpty else { return [:] }

        var result: [UUID: TimeInterval] = [:]
        let inactivityThreshold: TimeInterval = 5 * 60

        for index in 0..<(max(0, ascending.count - 1)) {
            let item = ascending[index]
            let gap = ascending[index + 1].createdAt
                .timeIntervalSince(item.createdAt)

            if gap > 0, gap <= inactivityThreshold {
                result[item.id, default: 0] += gap
            }
        }

        if let latest = ascending.last,
           Calendar.current.isDateInToday(latest.createdAt) {
            let age = min(max(0, now.timeIntervalSince(latest.createdAt)), inactivityThreshold)
            result[latest.id, default: 0] += age
        }

        return result
    }

    private func activeTime(for items: [MemoryItem]) -> TimeInterval {
        durationLookup(for: items).values.reduce(0, +)
    }

    private func appUsage(for items: [MemoryItem]) -> [TodayAppUsage] {
        let durations = durationLookup(for: items)
        let groups = Dictionary(grouping: items) { item in
            item.sourceBundleID.isEmpty
                ? item.sourceApp.lowercased()
                : item.sourceBundleID.lowercased()
        }

        return groups.values.compactMap { group -> TodayAppUsage? in
            guard let first = group.first else { return nil }

            return TodayAppUsage(
                name: first.sourceApp.isEmpty ? "Unknown App" : first.sourceApp,
                bundleID: first.sourceBundleID,
                category: MemoryTrailCategory.category(for: first),
                count: group.count,
                seconds: group.reduce(0) {
                    $0 + durations[$1.id, default: 0]
                }
            )
        }
        .sorted {
            if $0.seconds == $1.seconds {
                return $0.count > $1.count
            }
            return $0.seconds > $1.seconds
        }
    }

    private func filesAndDocumentsCount(in items: [MemoryItem]) -> Int {
        items.filter {
            let itemCategory = MemoryTrailCategory.category(for: $0)
            return itemCategory == .files ||
                itemCategory == .productivity ||
                $0.sourceKind == .file
        }.count
    }

    private func topCategory(in items: [MemoryItem]) -> MemoryTrailCategory {
        var counts: [MemoryTrailCategory: Int] = [:]

        for item in items {
            counts[MemoryTrailCategory.category(for: item), default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key ?? .other
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
            of: selectedDay
        ) ?? selectedDay
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start

        return "Most active \(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
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

    private func ensureSelection(in items: [MemoryItem]) {
        if let selectedMemoryID,
           items.contains(where: { $0.id == selectedMemoryID }) {
            return
        }

        selectedMemoryID = items.first?.id
    }

    private func open(_ item: MemoryItem) {
        if let sourceURL = item.sourceURL,
           let url = URL(string: sourceURL),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
            return
        }

        guard !item.sourceBundleID.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: item.sourceBundleID
              )
        else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func clearTimeline() {
        for item in memories {
            modelContext.delete(item)
        }

        try? modelContext.save()
        selectedMemoryID = nil
    }
}

private struct TodayAppUsage: Identifiable {
    let name: String
    let bundleID: String
    let category: MemoryTrailCategory
    let count: Int
    let seconds: TimeInterval

    var id: String {
        bundleID.isEmpty ? name : bundleID
    }
}

private struct TodayAppIcon: View {
    let bundleID: String
    let category: MemoryTrailCategory
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            )
            .fill(category.filterBackground)

            if let icon = AppIconCache.shared.icon(for: bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(size * 0.10)
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: size * 0.43, weight: .semibold))
                    .foregroundStyle(category.filterTint)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(
                cornerRadius: size * 0.28,
                style: .continuous
            )
            .stroke(category.filterTint.opacity(0.16), lineWidth: 1)
        }
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
                    tint: MemoryTrailCategory.allApps.filterTint,
                    background: MemoryTrailCategory.allApps.filterBackground
                )

                SummaryMetricTile(
                    value: "\(Set(dayItems.map(\.sourceApp)).count)",
                    label: "Apps Used",
                    symbol: "square.grid.2x2.fill",
                    tint: MemoryTrailCategory.chat.filterTint,
                    background: MemoryTrailCategory.chat.filterBackground
                )

                SummaryMetricTile(
                    value: activeTimeLabel,
                    label: "Active Time",
                    symbol: "clock.fill",
                    tint: MemoryTrailCategory.remoteAccess.filterTint,
                    background: MemoryTrailCategory.remoteAccess.filterBackground
                )

                SummaryMetricTile(
                    value: "\(dayItems.filter { $0.sourceKind == .clipboard }.count)",
                    label: "Clipboard Items",
                    symbol: "doc.on.clipboard.fill",
                    tint: MemoryTrailCategory.files.filterTint,
                    background: MemoryTrailCategory.files.filterBackground
                )
            }

            if !topSummaryApps.isEmpty {
                Divider()
                    .opacity(0.55)

                VStack(alignment: .leading, spacing: 9) {
                    Text("Top Apps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(topSummaryApps) { item in
                            let category = MemoryTrailCategory.category(for: item)

                            VStack(spacing: 5) {
                                summaryAppIcon(item, category: category)

                                Text(item.sourceApp)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 66)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(MemoryTrailPalette.elevatedStrong.opacity(0.94), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        }
    }

    private var topSummaryApps: [MemoryItem] {
        let groups = Dictionary(grouping: dayItems) { item in
            item.sourceBundleID.isEmpty
                ? item.sourceApp.lowercased()
                : item.sourceBundleID.lowercased()
        }

        return groups.values
            .sorted {
                if $0.count == $1.count {
                    return ($0.first?.sourceApp ?? "") < ($1.first?.sourceApp ?? "")
                }
                return $0.count > $1.count
            }
            .compactMap(\.first)
            .prefix(4)
            .map { $0 }
    }

    @ViewBuilder
    private func summaryAppIcon(
        _ item: MemoryItem,
        category: MemoryTrailCategory
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(category.filterBackground)

            if let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: category.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(category.filterTint)
            }
        }
        .frame(width: 38, height: 38)
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(category.filterTint.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func detailCard(_ item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                detailIcon(item)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                        GridRow {
                            Text("App")
                                .foregroundStyle(.tertiary)
                                .frame(width: 48, alignment: .leading)
                            Text(item.sourceApp)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }

                        GridRow {
                            Text("Type")
                                .foregroundStyle(.tertiary)
                                .frame(width: 48, alignment: .leading)
                            Text(detailType(item))
                                .lineLimit(1)
                        }

                        GridRow {
                            Text("Time")
                                .foregroundStyle(.tertiary)
                                .frame(width: 48, alignment: .leading)
                            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                                .lineLimit(1)
                        }

                        if selectedDuration >= 60 {
                            GridRow {
                                Text("Duration")
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 48, alignment: .leading)
                                Text(durationLabel)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 8) {
                    Button(action: onFavorite) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.isFavorite ? Color.orange : Color.secondary)
                            .frame(width: 28, height: 28)
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
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
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
    let background: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(background, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tint.opacity(0.12), lineWidth: 0.8)
                }

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
        .background(background.opacity(0.58), in: RoundedRectangle(cornerRadius: 13))
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
