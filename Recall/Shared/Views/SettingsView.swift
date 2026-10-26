import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @State private var testCaptureSaved = false
    @State private var customExclusions = ""

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Capture") {
                Toggle("Pause all capture", isOn: $preferences.capturePaused)
#if os(macOS)
                Toggle("Remember app switches", isOn: $preferences.captureAppActivity)
                Toggle("Remember copied text", isOn: $preferences.captureClipboard)
#elseif os(iOS)
                Label("Use the Share Sheet for rich context, or create Shortcuts automations to log app opens automatically.", systemImage: "bolt.horizontal.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DisclosureGroup("Automatic App-Open Logging Setup") {
                    Text("In the Shortcuts app, create a Personal Automation. Choose App → Is Opened → select an app such as Safari or Teams → Run Immediately. Add the Recall action “Log App Open” and set App Name to the app you selected. Repeat for each app you want Recall to log.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Example: When Safari is opened → Log App Open → App Name: Safari")
                        .font(.caption)
                }

                Button {
                    saveTestCapture()
                } label: {
                    Label(testCaptureSaved ? "Test Capture Saved" : "Create Test Capture", systemImage: testCaptureSaved ? "checkmark.circle.fill" : "waveform.path.ecg")
                }
#endif
            }

            Section("Excluded Apps & Services") {
                Menu {
                    ForEach(RecallExclusionOption.catalog) { option in
                        Toggle(isOn: exclusionBinding(for: option)) {
                            Label(option.name, systemImage: option.systemImage)
                        }
                        .disabled(option.isAlwaysExcluded)
                    }
                } label: {
                    Label("Choose Apps & Services", systemImage: "hand.raised")
                }

                ForEach(selectedOptions) { option in
                    HStack {
                        Label(option.name, systemImage: option.systemImage)
                        Spacer()
                        Text(option.isAlwaysExcluded ? "Always excluded" : "Excluded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DisclosureGroup("Advanced: Custom bundle IDs") {
                    TextField("com.example.app,com.example.other", text: $customExclusions, axis: .vertical)
                        .lineLimit(2...5)
                        .onSubmit {
                            preferences.updateCustomExclusions(from: customExclusions)
                            customExclusions = preferences.customExcludedBundleIDs
                        }

                    Button("Apply Custom Exclusions") {
                        preferences.updateCustomExclusions(from: customExclusions)
                        customExclusions = preferences.customExcludedBundleIDs
                    }
                    .buttonStyle(.borderless)
                }

                Label("Wallet and Passwords are excluded by default and cannot be enabled for capture. Recall will not intentionally log activity or clipboard content while either app is active.", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Text("This MVP stores your Recall timeline locally using SwiftData. No cloud account or analytics SDK is included.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            customExclusions = preferences.customExcludedBundleIDs
        }
    }

    private var selectedOptions: [RecallExclusionOption] {
        RecallExclusionOption.catalog.filter { preferences.isExcluded(option: $0) }
    }

    private func exclusionBinding(for option: RecallExclusionOption) -> Binding<Bool> {
        Binding(
            get: { preferences.isExcluded(option: option) },
            set: { preferences.setExcluded($0, option: option) }
        )
    }

#if os(iOS)
    private func saveTestCapture() {
        let item = MemoryItem(
            title: "iPhone test capture",
            body: "This test entry was created from Recall Settings to verify that the iOS SwiftData store and Timeline are functioning.",
            sourceApp: "Recall",
            sourceBundleID: Bundle.main.bundleIdentifier ?? "",
            sourceKind: .note
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
            testCaptureSaved = true
        } catch {
            assertionFailure("Unable to save test capture: \(error)")
        }
    }
#endif
}
