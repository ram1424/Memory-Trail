import SwiftUI
import SwiftData

struct SearchView: View {
    @Query(sort: \MemoryItem.createdAt, order: .reverse) private var memories: [MemoryItem]
    @State private var query = ""

    private var results: [MemoryItem] {
        memories.filter { SearchService.matches($0, query: query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search what you remember…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .padding()

            if query.isEmpty {
                ContentUnavailableView(
                    "Search your memory",
                    systemImage: "brain.head.profile",
                    description: Text("Try a project name, app, person, URL, phrase, or something you copied.")
                )
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { item in
                    NavigationLink {
                        MemoryDetailView(item: item)
                    } label: {
                        MemoryRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Search")
    }
}
