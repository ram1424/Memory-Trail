import SwiftUI
import SwiftData

struct FavoritesView: View {
    @Query(filter: #Predicate<MemoryItem> { $0.isFavorite }, sort: \MemoryItem.createdAt, order: .reverse)
    private var favorites: [MemoryItem]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Favorites")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("Keep important memories close.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "star.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.yellow)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Favorite an important memory to keep it close.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(favorites) { item in
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
        .navigationTitle("")
    }
}
