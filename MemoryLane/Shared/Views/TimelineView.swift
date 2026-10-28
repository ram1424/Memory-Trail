import AppKit
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(RecallPreferences.self) private var preferences
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    @State private var showingClearTimelineConfirmation = false
    @State private var selectedMemoryID: UUID?
    @State private var searchText = ""
    @State private var filter: TimelineFilter = .all
    @State private var density: TimelineDensity = .comfortable
    @State private var dayOffset = 0
    @State private var now = Date()
    @AppStorage("timelineShowsInspector") private var showsInspector = true

    var body: some View {
        VStack(spacing: 0) {
            timelineToolbar
            filterBar
            Divider()

            HStack(spacing: 0) {
                timelineContent
                    .frame(minWidth: 560, maxWidth: .infinity)

                if showsInspector, let item = selectedItem {
                    Divider()
                    TimelineInspector(
                        item: item,
                        previousItem: adjacentItem(to: item, direction: .older),
                        nextItem: adjacentItem(to: item, direction: .newer),
                        duration: duration(for: item),
                        isActive: isActive(item)
                    )
                    .frame(width: 350)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) {
                    showingClearTimelineConfirmation = true
                } label: {
                    Label("Clear Timeline", systemImage: "trash")
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
            Text("This permanently deletes all \(memories.count) timeline items from Memory Lane. This action cannot be undone.")
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { value in
            now = value
        }
    }

    private var timelineToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button {
                    dayOffset -= 1
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 30, height: 28)
                }

                Divider()
                    .frame(height: 18)

                Button {
                    if dayOffset < 0 {
                        dayOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 30, height: 28)
                }
                .disabled(dayOffset >= 0)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(.quaternary, lineWidth: 1)
            }

            Button {
                dayOffset = 0
            } label: {
                Label(dayOffset == 0 ? "Today" : selectedDay.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(.quaternary, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search your work…", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 180)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.quaternary, lineWidth: 1)
            }

            Menu {
                Picker("Activity", selection: $filter) {
                    ForEach(TimelineFilter.allCases) { option in
                        Label(option.title, systemImage: option.symbol)
                            .tag(option)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(filter == .all ? "All Activity" : filter.title)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.subheadline)
                .padding(.horizontal, 10)
                .frame(height: 30)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer(minLength: 8)

            HStack(spacing: 7) {
                Circle()
                    .fill(preferences.capturePaused ? .orange : .green)
                    .frame(width: 8, height: 8)
                Text(preferences.capturePaused ? "Paused" : "Capturing")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(TimelineFilter.quickFilters) { option in
                Button {
                    filter = option
                } label: {
                    Text(option.title)
                        .font(.caption.weight(filter == option ? .semibold : .medium))
                        .foregroundStyle(filter == option ? Color.white : Color.primary)
                        .padding(.horizontal, 13)
                        .frame(height: 28)
                        .background(
                            filter == option ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Picker("Density", selection: $density) {
                ForEach(TimelineDensity.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showsInspector.toggle()
                }
            } label: {
                Image(systemName: showsInspector ? "info.circle.fill" : "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(showsInspector ? Color.accentColor : Color.secondary)
            .background(
                showsInspector ? Color.accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .help(showsInspector ? "Hide Details" : "Show Details")
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private var timelineContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if filteredItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: memories.isEmpty ? "sparkles" : "magnifyingglass")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(memories.isEmpty ? "Your timeline is empty" : "No matching activity")
                            .font(.title3.weight(.semibold))

                        Text(memories.isEmpty
                            ? "Open a few apps or add a memory to start building your searchable work history."
                            : "Try another day, filter, or search term.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)
                    }
                    .frame(maxWidth: .infinity, minHeight: 470)
                } else {
                    Section {
                        VStack(spacing: 10) {
                            ActivityHeatmap(items: dayItems, selectedDay: selectedDay, now: now)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 12)

                        VStack(spacing: density.rowSpacing) {
                            ForEach(filteredItems) { item in
                                TimelineActivityRow(
                                    item: item,
                                    duration: duration(for: item),
                                    isActive: isActive(item),
                                    isSelected: selectedMemoryID == item.id,
                                    density: density
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        selectedMemoryID = item.id
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    } header: {
                        dayHeader
                    }
                }
            }
        }
    }

    private var dayHeader: some View {
        HStack {
            Text(dayHeaderTitle)
                .font(.subheadline.weight(.bold))
                .textCase(.uppercase)

            Spacer()

            if !filteredItems.isEmpty {
                Text(totalVisibleDurationLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
    }

    private var selectedDay: Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: Calendar.current.startOfDay(for: now)) ?? now
    }

    private var dayHeaderTitle: String {
        if Calendar.current.isDateInToday(selectedDay) {
            return "Today · \(selectedDay.formatted(.dateTime.month(.wide).day().year()))"
        }
        if Calendar.current.isDateInYesterday(selectedDay) {
            return "Yesterday · \(selectedDay.formatted(.dateTime.month(.wide).day().year()))"
        }
        return selectedDay.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    private var dayItems: [MemoryItem] {
        memories.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: selectedDay) }
    }

    private var filteredItems: [MemoryItem] {
        dayItems.filter { item in
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || item.searchableText.localizedCaseInsensitiveContains(searchText)
            return matchesSearch && filter.matches(item)
        }
    }

    private var selectedItem: MemoryItem? {
        guard let selectedMemoryID else { return nil }
        return memories.first { $0.id == selectedMemoryID }
    }

    private var totalVisibleDurationLabel: String {
        let seconds = filteredItems.reduce(0.0) { partial, item in
            partial + duration(for: item)
        }
        return Self.durationFormatter.string(from: seconds) ?? ""
    }

    private func duration(for item: MemoryItem) -> TimeInterval {
        guard let index = memories.firstIndex(where: { $0.id == item.id }) else { return 0 }

        if index == 0 {
            let elapsed = max(0, now.timeIntervalSince(item.createdAt))
            return min(elapsed, 60 * 30)
        }

        let newer = memories[index - 1]
        let delta = max(0, newer.createdAt.timeIntervalSince(item.createdAt))
        return min(delta, 60 * 90)
    }

    private func isActive(_ item: MemoryItem) -> Bool {
        guard !preferences.capturePaused,
              memories.first?.id == item.id,
              item.sourceKind == .appActivity
        else {
            return false
        }

        return now.timeIntervalSince(item.createdAt) < 15 * 60
    }

    private func adjacentItem(to item: MemoryItem, direction: AdjacentDirection) -> MemoryItem? {
        guard let index = memories.firstIndex(where: { $0.id == item.id }) else { return nil }

        switch direction {
        case .newer:
            guard index > 0 else { return nil }
            return memories[index - 1]
        case .older:
            guard index + 1 < memories.count else { return nil }
            return memories[index + 1]
        }
    }

    private func clearTimeline() {
        selectedMemoryID = nil
        for item in memories {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to clear Memory Lane timeline: \(error)")
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

private struct TimelineActivityRow: View {
    let item: MemoryItem
    let duration: TimeInterval
    let isActive: Bool
    let isSelected: Bool
    let density: TimelineDensity

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1)
                Circle()
                    .fill(isActive ? Color.green : Color.accentColor)
                    .frame(width: isActive ? 12 : 9, height: isActive ? 12 : 9)
                    .overlay {
                        if isActive {
                            Circle()
                                .stroke(Color.green.opacity(0.25), lineWidth: 5)
                        }
                    }
                Rectangle()
                    .fill(Color.secondary.opacity(0.22))
                    .frame(width: 1)
            }
            .frame(width: 20)
            .frame(minHeight: density.rowHeight)

            HStack(spacing: 12) {
                sourceIcon

                VStack(alignment: .leading, spacing: density == .comfortable ? 4 : 2) {
                    HStack(spacing: 7) {
                        Text(primaryTitle)
                            .font(.system(size: density == .comfortable ? 15 : 14, weight: .semibold))
                            .lineLimit(1)

                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }

                    if !secondaryTitle.isEmpty {
                        Text(secondaryTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if density == .comfortable {
                        HStack(spacing: 6) {
                            Text(item.sourceApp)
                            Text("·")
                            Text(categoryLabel)
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    if isActive {
                        Label("Active now", systemImage: "circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else if duration >= 60 {
                        Text(Self.durationFormatter.string(from: duration) ?? "")
                            .font(.subheadline.weight(.semibold))
                    }

                    if density == .comfortable, duration >= 60 {
                        let end = item.createdAt.addingTimeInterval(duration)
                        Text("\(item.createdAt.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, density == .comfortable ? 14 : 12)
            .padding(.vertical, density == .comfortable ? 12 : 8)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor).opacity(0.72),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if item.sourceKind == .appActivity,
           let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        } else {
            Image(systemName: item.sourceKind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.tint)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var primaryTitle: String {
        if item.sourceKind == .appActivity, !item.title.hasPrefix("Opened ") {
            return item.title
        }
        return item.sourceKind == .appActivity ? item.sourceApp : item.title
    }

    private var secondaryTitle: String {
        guard item.sourceKind == .appActivity else {
            return item.body
        }
        return primaryTitle == item.sourceApp ? item.body : item.sourceApp
    }

    private var categoryLabel: String {
        TimelineFilter.category(for: item).title
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

private struct TimelineInspector: View {
    @Bindable var item: MemoryItem
    let previousItem: MemoryItem?
    let nextItem: MemoryItem?
    let duration: TimeInterval
    let isActive: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inspectorHeader

                Divider()

                metadataSection

                if let previousItem {
                    Divider()
                    adjacentActivity(title: "Previous Activity", item: previousItem)
                }

                if let nextItem {
                    adjacentActivity(title: "Next Activity", item: nextItem)
                }

                Divider()

                actions
            }
            .padding(18)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.36))
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                inspectorIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(item.sourceApp)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    item.isFavorite.toggle()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            if isActive {
                Label("Active now", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorRow(symbol: "clock", label: "Time", value: timeValue)
            inspectorRow(symbol: "hourglass", label: "Duration", value: durationLabel)
            inspectorRow(symbol: "app", label: "Application", value: item.sourceApp)
            inspectorRow(symbol: item.sourceKind.symbol, label: "Type", value: item.sourceKind.rawValue)

            if !item.body.isEmpty {
                inspectorRow(symbol: "text.alignleft", label: "Details", value: item.body)
            }

            if let sourceURL = item.sourceURL, !sourceURL.isEmpty {
                inspectorRow(symbol: "link", label: "Source", value: sourceURL)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if !item.sourceBundleID.isEmpty {
                Button {
                    openSourceApplication()
                } label: {
                    Label("Open App", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            HStack(spacing: 8) {
                Button {
                    copyDetails()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }

                Button {
                    item.isFavorite.toggle()
                } label: {
                    Label(item.isFavorite ? "Favorited" : "Favorite", systemImage: item.isFavorite ? "star.fill" : "star")
                }
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var inspectorIcon: some View {
        if item.sourceKind == .appActivity,
           let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 42, height: 42)
                .padding(6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
        } else {
            Image(systemName: item.sourceKind.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 54, height: 54)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func inspectorRow(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func adjacentActivity(title: String, item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 9) {
                if item.sourceKind == .appActivity,
                   let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: item.sourceKind.symbol)
                        .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var timeValue: String {
        if isActive {
            return "\(item.createdAt.formatted(date: .omitted, time: .shortened)) – Present"
        }
        let end = item.createdAt.addingTimeInterval(duration)
        return "\(item.createdAt.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    private var durationLabel: String {
        if duration < 60 {
            return "Less than a minute"
        }
        return Self.durationFormatter.string(from: duration) ?? ""
    }

    private func openSourceApplication() {
        guard !item.sourceBundleID.isEmpty,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.sourceBundleID)
        else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func copyDetails() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            [item.title, item.body, item.sourceApp, item.sourceURL ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: "\n"),
            forType: .string
        )
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()
}

private struct ActivityHeatmap: View {
    let items: [MemoryItem]
    let selectedDay: Date
    let now: Date

    private var buckets: [Int] {
        var counts = Array(repeating: 0, count: 48)
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: selectedDay)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? selectedDay

        let relevant = items
            .filter { $0.sourceKind == .appActivity || $0.sourceKind == .file || $0.sourceKind == .link }
            .sorted { $0.createdAt < $1.createdAt }

        for (index, item) in relevant.enumerated() {
            let nextDate: Date
            if index + 1 < relevant.count {
                nextDate = relevant[index + 1].createdAt
            } else {
                nextDate = min(now, item.createdAt.addingTimeInterval(8 * 60))
            }

            let spanEnd = min(nextDate, item.createdAt.addingTimeInterval(30 * 60), dayEnd.addingTimeInterval(-1))
            let clampedStart = max(item.createdAt, dayStart)
            guard spanEnd >= clampedStart else { continue }

            let startMinutes = max(0, Int(clampedStart.timeIntervalSince(dayStart) / 60))
            let endMinutes = min(1439, Int(spanEnd.timeIntervalSince(dayStart) / 60))
            let startIndex = min(47, max(0, startMinutes / 30))
            let endIndex = min(47, max(startIndex, endMinutes / 30))

            for bucket in startIndex...endIndex {
                counts[bucket] += 1
            }
        }

        return counts
    }

    var body: some View {
        let values = buckets
        let maxCount = max(values.max() ?? 0, 1)

        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("Activity Overview", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("12 AM")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("12 PM")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("11:59 PM")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 2) {
                ForEach(values.indices, id: \.self) { index in
                    let count = values[index]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            count == 0
                                ? Color.secondary.opacity(0.08)
                                : Color.accentColor.opacity(0.20 + (0.72 * Double(count) / Double(maxCount)))
                        )
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 11)
        }
        .padding(.horizontal, 2)
    }
}

private enum TimelineFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case web
    case email
    case chat
    case files
    case clipboard
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .web: "Web"
        case .email: "Email"
        case .chat: "Chat"
        case .files: "Files"
        case .clipboard: "Clipboard"
        case .favorites: "Favorites"
        }
    }

    var symbol: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .web: "safari"
        case .email: "envelope"
        case .chat: "bubble.left.and.bubble.right"
        case .files: "folder"
        case .clipboard: "doc.on.clipboard"
        case .favorites: "star"
        }
    }

    static let quickFilters: [TimelineFilter] = [.all, .web, .email, .chat, .files, .clipboard, .favorites]

    func matches(_ item: MemoryItem) -> Bool {
        switch self {
        case .all:
            return true
        case .favorites:
            return item.isFavorite
        default:
            return Self.category(for: item) == self
        }
    }

    static func category(for item: MemoryItem) -> TimelineFilter {
        if item.sourceKind == .clipboard {
            return .clipboard
        }
        if item.sourceKind == .file || item.sourceKind == .screenshot {
            return .files
        }

        let haystack = "\(item.sourceApp) \(item.sourceBundleID)".lowercased()
        if haystack.contains("safari") || haystack.contains("chrome") || haystack.contains("firefox") || haystack.contains("edge") || haystack.contains("arc") {
            return .web
        }
        if haystack.contains("outlook") || haystack.contains("mail") {
            return .email
        }
        if haystack.contains("teams") || haystack.contains("slack") || haystack.contains("messages") || haystack.contains("discord") {
            return .chat
        }

        return .files
    }
}

private enum TimelineDensity: String, CaseIterable, Identifiable, Hashable {
    case compact
    case comfortable

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var rowHeight: CGFloat { self == .comfortable ? 78 : 58 }
    var rowSpacing: CGFloat { self == .comfortable ? 8 : 5 }
}

private enum AdjacentDirection {
    case newer
    case older
}

struct MemoryRow: View {
    let item: MemoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            sourceIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(primaryTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
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
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if item.sourceKind == .appActivity,
           let icon = AppIconCache.shared.icon(for: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 30, height: 30)
                .padding(4)
                .frame(width: 38, height: 38)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: item.sourceKind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(.tint)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var primaryTitle: String {
        item.sourceKind == .appActivity ? item.sourceApp : item.title
    }

    private var secondaryTitle: String {
        guard item.sourceKind == .appActivity else { return "" }
        return item.title.hasPrefix("Opened ") ? "" : item.title
    }
}

@MainActor
private final class AppIconCache {
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
