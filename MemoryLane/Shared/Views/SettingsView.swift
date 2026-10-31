import SwiftUI

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var captureCoordinator = MacCaptureCoordinator.shared
    @State private var customExclusions = ""
    @State private var showingClearCacheConfirmation = false
    @State private var cacheClearedMessage = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var preferences = preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Control what Memory Lane remembers and how it behaves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                settingsCard("Capture", systemImage: "record.circle") {
                    Toggle("Pause all capture", isOn: $preferences.capturePaused)
                    Toggle("Remember app switches and focused windows", isOn: $preferences.captureAppActivity)
                    Toggle("Remember copied text", isOn: $preferences.captureClipboard)

                    Divider()

                    if captureCoordinator.hasAccessibilityPermission {
                        Label("Accessibility access enabled. Focused-window title capture is active.", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Accessibility access is not active. App switches can still be logged, but Safari/Outlook/Mail/Teams window titles cannot be captured.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        HStack {
                            Button {
                                captureCoordinator.requestAccessibilityPermission()
                            } label: {
                                Label("Request Access", systemImage: "hand.raised.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open Accessibility Settings") {
                                captureCoordinator.openAccessibilitySettings()
                            }

                            Button("Recheck") {
                                captureCoordinator.refreshAccessibilityStatus()
                            }
                        }

                        Text("Memory Lane requests Accessibility access automatically on launch. If macOS does not show the prompt, use Request Access or open Accessibility Settings, then enable Memory Lane.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard("Excluded Apps & Services", systemImage: "hand.raised.slash") {
                    Menu {
                        ForEach(RecallExclusionOption.catalog) { option in
                            Toggle(isOn: exclusionBinding(for: option)) {
                                Label(option.name, systemImage: option.systemImage)
                            }
                            .disabled(option.isAlwaysExcluded)
                        }
                    } label: {
                        Label("Choose Apps & Services", systemImage: "plus.circle")
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

                    Label("Wallet and Passwords are always excluded. Memory Lane will not intentionally log activity or clipboard content while either app is active.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsCard("Help", systemImage: "questionmark.circle") {
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("Show Welcome Tutorial", systemImage: "sparkles")
                    }

                    Text("Replay the first-launch walkthrough for Memory Lane.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsCard("Data & Privacy", systemImage: "externaldrive.fill") {
                    Text("Memory Lane stores your activity timeline locally using SwiftData. No cloud account or analytics SDK is included.")
                        .foregroundStyle(.secondary)

                    Divider()

                    Button(role: .destructive) {
                        showingClearCacheConfirmation = true
                    } label: {
                        Label("Clear App Cache", systemImage: "trash.slash")
                    }

                    Text("Resets cached capture state and Memory Lane preferences without deleting your Timeline history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if cacheClearedMessage {
                        Label("App cache cleared.", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Label("About Memory Lane", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))

                    Text("Version \(appVersion) (Build \(buildNumber))")
                        .font(.caption2)

                    Text("Created By: Roman Zakharov")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .padding(24)
        }
        .background(
            LinearGradient(
                colors: [MemoryLanePalette.canvasTop, MemoryLanePalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("")
        .onAppear {
            customExclusions = preferences.customExcludedBundleIDs
            captureCoordinator.refreshAccessibilityStatus()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            captureCoordinator.refreshAccessibilityStatus()
        }
        .confirmationDialog(
            "Clear App Cache?",
            isPresented: $showingClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear App Cache", role: .destructive) {
                preferences.resetToDefaults()
                MacCaptureCoordinator.shared.clearRuntimeCache()
                customExclusions = preferences.customExcludedBundleIDs
                cacheClearedMessage = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This resets capture state and preferences to defaults. Your Timeline entries will not be deleted.")
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            content()
        }
        .padding(18)
        .background(MemoryLanePalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
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
