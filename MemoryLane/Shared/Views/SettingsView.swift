import SwiftUI

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var customExclusions = ""

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section("Capture") {
                Toggle("Pause all capture", isOn: $preferences.capturePaused)
                Toggle("Remember app switches and focused windows", isOn: $preferences.captureAppActivity)
                Toggle("Remember copied text", isOn: $preferences.captureClipboard)

                if MacCaptureCoordinator.shared.hasAccessibilityPermission {
                    Label("Accessibility access enabled. Memory Lane can capture focused window titles for richer Timeline entries.", systemImage: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        MacCaptureCoordinator.shared.requestAccessibilityPermission()
                    } label: {
                        Label("Enable Accessibility Access", systemImage: "hand.raised")
                    }

                    Text("Required for granular macOS activity such as Safari page titles, Mail subjects, Outlook items, and Teams windows. macOS will ask you to allow Memory Lane in System Settings → Privacy & Security → Accessibility.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

                Label("Wallet and Passwords are excluded by default and cannot be enabled for capture. Memory Lane will not intentionally log activity or clipboard content while either app is active.", systemImage: "lock.shield.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Text("Memory Lane stores your activity timeline locally using SwiftData. No cloud account or analytics SDK is included.")
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
}
