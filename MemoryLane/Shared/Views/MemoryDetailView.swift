import SwiftUI
#if os(macOS)
import AppKit
#endif

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
                if let url = item.sourceURL,
                   !url.isEmpty,
                   let link = URL(string: url) {
                    LabeledContent("Source Link") {
                        Link(destination: link) {
                            Label("Open Source", systemImage: "arrow.up.right.square")
                        }
                    }

                    Text(url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

#if os(macOS)
                if !item.sourceBundleID.isEmpty {
                    LabeledContent("Application") {
                        Button {
                            openSourceApplication()
                        } label: {
                            Label("Open \(item.sourceApp)", systemImage: "macwindow")
                        }
                        .buttonStyle(.link)
                    }
                }
#endif
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

#if os(macOS)
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
