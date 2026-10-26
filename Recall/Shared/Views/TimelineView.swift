import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]

    var body: some View {
        Group {
            if memories.isEmpty {
                ContentUnavailableView(
                    "Your timeline is empty",
                    systemImage: "sparkles",
                    description: Text("Add a memory or enable capture to start building your searchable work history.")
                )
            } else {
                List {
                    ForEach(groupedDays, id: \.day) { group in
                        Section(group.day.formatted(date: .abbreviated, time: .omitted)) {
                            ForEach(group.items) { item in
                                NavigationLink {
                                    MemoryDetailView(item: item)
                                } label: {
                                    MemoryRow(item: item)
                                }
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    modelContext.delete(group.items[index])
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.sourceKind.symbol)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                    }
                }

                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(item.sourceApp)
                    Text("•")
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
