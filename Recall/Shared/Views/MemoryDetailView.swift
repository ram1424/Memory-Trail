import SwiftUI

struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: MemoryItem

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $item.title)
                TextField("Details", text: $item.body, axis: .vertical)
                    .lineLimit(5...20)
            }

            Section("Context") {
                LabeledContent("Source", value: item.sourceApp)
                LabeledContent("Type", value: item.sourceKind.rawValue)
                LabeledContent("Captured", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let url = item.sourceURL, !url.isEmpty {
                    LabeledContent("URL") {
                        if let link = URL(string: url) {
                            Link(url, destination: link)
                        } else {
                            Text(url)
                        }
                    }
                }
            }

            Section {
                Toggle("Favorite", isOn: $item.isFavorite)
            }
        }
        .navigationTitle(item.title)
#if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    dismiss()
                } label: {
                    Label("Back to Timeline", systemImage: "chevron.left")
                }
                .help("Return to Timeline")
                .keyboardShortcut("[", modifiers: .command)
            }
        }
#endif
    }
}
