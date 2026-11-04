import SwiftUI
import SwiftData

struct FavoritesView: View {
    let memories: [MemoryItem]

    private var favorites: [MemoryItem] {
        memories.filter(\.isFavorite)
    }

    var body: some View {
        let favorites = self.favorites
        let apps = Set(favorites.map(\.sourceApp)).count
        let today = favorites.filter { Calendar.current.isDateInToday($0.createdAt) }.count

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                favoritesHeader

                HStack(spacing: 12) {
                    favoriteMetric(
                        value: "\(favorites.count)",
                        label: "Saved Favorites",
                        symbol: "star.fill",
                        category: .files
                    )
                    favoriteMetric(
                        value: "\(apps)",
                        label: "Apps Represented",
                        symbol: "square.grid.2x2.fill",
                        category: .chat
                    )
                    favoriteMetric(
                        value: "\(today)",
                        label: "Added Today",
                        symbol: "calendar",
                        category: .remoteAccess
                    )
                }

                if favorites.isEmpty {
                    emptyFavorites
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Your Favorites", systemImage: "star.square.fill")
                            .font(.system(size: 18, weight: .bold, design: .rounded))

                        LazyVStack(spacing: 9) {
                            ForEach(favorites) { item in
                                NavigationLink {
                                    MemoryDetailView(item: item)
                                } label: {
                                    favoriteRow(item)
                                }
                                .buttonStyle(.plain)
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
            }
            .padding(24)
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
    }

    private var favoritesHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.files.filterTint)
                .frame(width: 48, height: 48)
                .background(
                    MemoryTrailCategory.files.filterBackground,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Favorites")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Star the moments worth retracing — Favorites turn important activity into shortcuts back to the work that mattered.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }

    private func favoriteMetric(
        value: String,
        label: String,
        symbol: String,
        category: MemoryTrailCategory
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(category.filterTint)
                .frame(width: 38, height: 38)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            category.filterBackground.opacity(0.46),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(category.filterTint.opacity(0.10), lineWidth: 1)
        }
    }

    private var emptyFavorites: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(MemoryTrailCategory.files.filterBackground)
                    .frame(width: 92, height: 92)

                Image(systemName: "star.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(MemoryTrailCategory.files.filterTint)
            }

            Text("Build your shortcut back")
                .font(.system(size: 25, weight: .bold, design: .rounded))

            Text("Star the moments worth retracing. Favorites turn important activity into shortcuts back to the work, pages, conversations, and files that mattered.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

            Label(
                "Use the star on any timeline item to add it here.",
                systemImage: "star.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(MemoryTrailCategory.files.filterTint)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                MemoryTrailCategory.files.filterBackground,
                in: Capsule()
            )
        }
        .frame(maxWidth: .infinity, minHeight: 390)
        .padding(30)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.95),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private func favoriteRow(_ item: MemoryItem) -> some View {
        let category = MemoryTrailCategory.category(for: item)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
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
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(item.sourceApp) • \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "star.fill")
                .foregroundStyle(MemoryTrailCategory.files.filterTint)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            category.filterBackground.opacity(0.34),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(category.filterTint.opacity(0.08), lineWidth: 1)
        }
    }
}
