import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var query = ""

    private var results: [MemoryItem] {
        memories.filter { SearchService.matches($0, query: query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Search your history")
                        .font(.title2.weight(.semibold))
                    Text("Find apps, window titles, links, notes, and copied text.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search what you remember…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.body)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(.quaternary, lineWidth: 1)
                }

                if query.isEmpty {
                    ContentUnavailableView(
                        "Search your memory",
                        systemImage: "brain.head.profile",
                        description: Text("Try a project name, app, person, URL, phrase, or something you copied.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity, minHeight: 360)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(results.count) result\(results.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(results) { item in
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
            .padding(24)
        }
        .navigationTitle("Search")
    }
}
