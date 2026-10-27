import AppKit
import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var showingClearTimelineConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header

                if memories.isEmpty {
                    ContentUnavailableView(
                        "Your timeline is empty",
                        systemImage: "sparkles",
                        description: Text("Open a few apps or add a memory to start building your searchable work history.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    ForEach(groupedDays, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.day.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            LazyVStack(spacing: 8) {
                                ForEach(group.items) { item in
                                    NavigationLink {
                                        MemoryDetailView(item: item)
                                    } label: {
                                        MemoryRow(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
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
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your recent activity")
                    .font(.title2.weight(.semibold))
                Text(memories.isEmpty ? "Nothing captured yet" : "\(memories.count) memories captured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func clearTimeline() {
        for item in memories {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Unable to clear Memory Lane timeline: \(error)")
        }
    }

    private var groupedDays: [(day: Date, items: [MemoryItem])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: memories) { item in
            calendar.startOfDay(for: item.createdAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            (day, grouped[day] ?? [])
        }
    }
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
