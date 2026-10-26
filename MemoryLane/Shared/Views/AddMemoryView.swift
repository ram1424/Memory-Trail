import SwiftUI
import SwiftData

struct AddMemoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var bodyText = ""
    @State private var sourceKind: SourceKind = .note
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Memory") {
                    TextField("Title", text: $title)
                    TextField("What do you want to remember?", text: $bodyText, axis: .vertical)
                        .lineLimit(4...10)
                    Picker("Type", selection: $sourceKind) {
                        ForEach(SourceKind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }

                Section("Optional") {
                    TextField("URL", text: $url)
#if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
#endif
                }
            }
            .navigationTitle("Add Memory")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let item = MemoryItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            body: bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
                            sourceKind: sourceKind,
                            sourceURL: url.isEmpty ? nil : url
                        )
                        modelContext.insert(item)
                        do {
                            try modelContext.save()
                            dismiss()
                        } catch {
                            assertionFailure("Unable to save memory: \(error)")
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
