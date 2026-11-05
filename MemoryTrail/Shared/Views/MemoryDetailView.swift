import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: MemoryItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                contentCard
                contextCard
                actionsCard
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(
            LinearGradient(
                colors: [
                    MemoryTrailPalette.canvasTop,
                    MemoryTrailPalette.canvasBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle(item.title)
#if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Close Details", systemImage: "xmark")
                }
                .help("Close activity details")
                .keyboardShortcut("[", modifiers: .command)
            }
        }
#endif
    }

    private var headerCard: some View {
        HStack(spacing: 16) {
            detailIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(item.sourceApp)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(item.title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    item.isFavorite.toggle()
                } label: {
                    Image(
                        systemName:
                            item.isFavorite
                            ? "star.fill"
                            : "star"
                    )
                    .font(
                        .system(
                            size: 18,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(
                        item.isFavorite
                        ? .yellow
                        : .secondary
                    )
                    .frame(width: 38, height: 38)
                    .background(
                        .thinMaterial,
                        in: RoundedRectangle(
                            cornerRadius: 11
                        )
                    )
                }
                .buttonStyle(.plain)
                .help(
                    item.isFavorite
                    ? "Remove from Favorites"
                    : "Add to Favorites"
                )

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(
                            .system(
                                size: 16,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(
                            .thinMaterial,
                            in: RoundedRectangle(
                                cornerRadius: 11
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Close activity details")
                .accessibilityLabel(
                    "Close activity details"
                )
            }
        }
        .padding(20)
        .background(MemoryTrailPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Memory")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Title", text: $item.title)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.quaternary, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Details")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Details", text: $item.body, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(5...16)
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.82), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.quaternary, lineWidth: 1)
                    }
            }
        }
        .padding(20)
        .background(MemoryTrailPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Context")
                .font(.headline)

            metadataRow(label: "Source", value: item.sourceApp, symbol: "app")
            Divider()
            metadataRow(label: "Type", value: item.sourceKind.rawValue, symbol: item.sourceKind.symbol)
            Divider()
            metadataRow(
                label: "Captured",
                value: item.createdAt.formatted(date: .abbreviated, time: .shortened),
                symbol: "clock"
            )

            if let url = item.sourceURL,
               !url.isEmpty,
               let link = URL(string: url) {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label("Source Link", systemImage: "link")
                        .font(.subheadline.weight(.semibold))

                    Link(destination: link) {
                        Label("Open Source", systemImage: "arrow.up.right.square")
                    }

                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }
            }
        }
        .padding(20)
        .background(MemoryTrailPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var actionsCard: some View {
        HStack(spacing: 12) {
#if os(macOS)
            if !item.sourceBundleID.isEmpty {
                Button {
                    openSourceApplication()
                } label: {
                    Label("Open \(item.sourceApp)", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }
#endif

            Spacer()

            Toggle("Favorite", isOn: $item.isFavorite)
                .toggleStyle(.switch)
                .labelsHidden()

            Text(item.isFavorite ? "Favorited" : "Favorite")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(MemoryTrailPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var detailIcon: some View {
#if os(macOS)
        if item.sourceKind == .appActivity,
           let icon = applicationIcon(bundleID: item.sourceBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 46, height: 46)
                .padding(7)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        } else {
            fallbackIcon
        }
#else
        fallbackIcon
#endif
    }

    private var fallbackIcon: some View {
        Image(systemName: item.sourceKind.symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.tint)
            .frame(width: 60, height: 60)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metadataRow(label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)

            Text(value)
                .font(.subheadline.weight(.medium))
                .textSelection(.enabled)

            Spacer()
        }
    }

#if os(macOS)
    private func applicationIcon(bundleID: String) -> NSImage? {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalized)
        else {
            return nil
        }

        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    private func openSourceApplication() {
        guard !item.sourceBundleID.isEmpty,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: item.sourceBundleID
              )
        else {
            return
        }

        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
#endif
}
