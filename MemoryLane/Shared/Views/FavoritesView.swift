import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(filter: #Predicate<MemoryItem> { $0.isFavorite }, sort: \MemoryItem.createdAt, order: .reverse)
    private var favorites: [MemoryItem]

    var body: some View {
        Group {
            if favorites.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Favorite an important memory to keep it close."))
            } else {
                List(favorites) { item in
                    NavigationLink {
                        MemoryDetailView(item: item)
                    } label: {
                        MemoryRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Favorites")
    }
}
