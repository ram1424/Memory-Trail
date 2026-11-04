import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let memoryTrailCheckForUpdates = Notification.Name("MemoryTrailCheckForUpdates")
}

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var captureCoordinator = MacCaptureCoordinator.shared
    @State private var customExclusions = ""
    @State private var showingInstalledAppPicker = false
    @State private var installedApps: [InstalledApplication] = []
    @State private var showingClearCacheSheet = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var preferences = preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Control what Memory Trail remembers and how it behaves.")
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

                        Text("Memory Trail requests Accessibility access automatically on launch. If macOS does not show the prompt, use Request Access or open Accessibility Settings, then enable Memory Trail.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard("Excluded Apps & Services", systemImage: "hand.raised.slash") {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Choose installed apps Memory Trail should ignore.")
                                .font(.subheadline)

                            Text("\(excludedInstalledAppCount) installed app\(excludedInstalledAppCount == 1 ? "" : "s") currently excluded.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            refreshInstalledApps()
                            showingInstalledAppPicker = true
                        } label: {
                            Label("Select Installed Apps", systemImage: "plus.app.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    ForEach(alwaysExcludedOptions) { option in
                        HStack(spacing: 10) {
                            Image(systemName: option.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(option.name)
                                    .font(.subheadline.weight(.medium))
                                Text("Always excluded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !otherExcludedInstalledApps.isEmpty {
                        Divider()

                        Text("Selected installed apps")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(otherExcludedInstalledApps.prefix(8)) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)

                                Text(app.name)
                                    .font(.subheadline)

                                Spacer()

                                Button {
                                    preferences.setExcluded(false, bundleID: app.bundleID)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove exclusion")
                            }
                        }

                        if otherExcludedInstalledApps.count > 8 {
                            Text("+ \(otherExcludedInstalledApps.count - 8) more")
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

                    Label("Passwords and Wallet are always excluded. Additional apps you select are ignored for both activity and clipboard capture.", systemImage: "lock.shield.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsCard("Updates", systemImage: "arrow.triangle.2.circlepath") {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stay on the freshest trail")
                                .font(.subheadline.weight(.semibold))

                            Text("Memory Trail checks for new releases when it launches and periodically while it’s running.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            NotificationCenter.default.post(
                                name: .memoryTrailCheckForUpdates,
                                object: nil
                            )
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Divider()

                    HStack {
                        Label(
                            "Version \(appVersion) • Build \(buildNumber)",
                            systemImage: "shippingbox.fill"
                        )
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)

                        Spacer()

                        Text("Automatic checks enabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsCard("Help", systemImage: "questionmark.circle") {
                    Button {
                        hasCompletedOnboarding = false
                    } label: {
                        Label("Show Welcome Tutorial", systemImage: "sparkles")
                    }

                    Text("Replay the first-launch walkthrough for Memory Trail.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                settingsCard("Privacy", systemImage: "lock.shield.fill") {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Privacy-first by design")
                            .font(.title3.weight(.semibold))

                        Text("Memory Trail is a private, locally run macOS app. Its captured activity history is processed and stored on this computer.")
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    privacyStatement(
                        icon: "internaldrive.fill",
                        title: "Sourced and stored locally",
                        text: "Timeline data comes from local macOS app/window context, local files and paths, and the clipboard when enabled. Captured history is stored locally on this Mac using SwiftData."
                    )

                    privacyStatement(
                        icon: "icloud.slash.fill",
                        title: "No captured-data transmission",
                        text: "Memory Trail does not upload, sync, or send your captured timeline data outside of this computer."
                    )

                    privacyStatement(
                        icon: "link",
                        title: "No external data connectors",
                        text: "Memory Trail does not use external data connectors, cloud sync, analytics services, or a remote account for its capture and storage workflow."
                    )

                    privacyStatement(
                        icon: "checkmark.shield.fill",
                        title: "Verifiable source code",
                        text: "The source code is available publicly so you can review and verify how Memory Trail captures, processes, and stores data."
                    )

                    Link(destination: URL(string: "https://github.com/ram1424/Memory-Lane")!) {
                        Label("Review Memory Trail Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Divider()

                    Button {
                        showingClearCacheSheet = true
                    } label: {
                        Label("Clear App Cache", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.bordered)

                    Text("Resets cached capture state and Memory Trail preferences without deleting your activity history.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Link(destination: URL(string: "https://github.com/ram1424/Memory-Lane")!) {
                        HStack(spacing: 5) {
                            Label("About Memory Trail", systemImage: "info.circle")
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .help("Open the Memory Trail GitHub page")

                    Text("Version \(appVersion) (Build \(buildNumber))")
                        .font(.caption2)

                    Text("Created By: Roman Zakharov")
                        .font(.caption2)

                    Text("Source code, privacy details, documentation, and the latest release are available on GitHub.")
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
                colors: [MemoryTrailPalette.canvasTop, MemoryTrailPalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("")
        .sheet(isPresented: $showingInstalledAppPicker) {
            InstalledAppPicker(
                apps: installedApps,
                preferences: preferences
            )
            .frame(minWidth: 720, minHeight: 620)
        }
        .onAppear {
            customExclusions = preferences.customExcludedBundleIDs
            refreshInstalledApps()
            captureCoordinator.refreshAccessibilityStatus()
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            captureCoordinator.refreshAccessibilityStatus()
        }
        .sheet(isPresented: $showingClearCacheSheet) {
            MemoryTrailClearCacheSheet {
                preferences.resetToDefaults()
                MacCaptureCoordinator.shared.clearRuntimeCache()
                customExclusions = preferences.customExcludedBundleIDs
            }
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
        .background(MemoryTrailPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func privacyStatement(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 30, height: 30)
                .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var alwaysExcludedOptions: [RecallExclusionOption] {
        RecallExclusionOption.catalog.filter(\.isAlwaysExcluded)
    }

    private var otherExcludedInstalledApps: [InstalledApplication] {
        installedApps.filter {
            preferences.isExcluded(bundleID: $0.bundleID) &&
            !RecallExclusionOption.mandatoryBundleIDs.contains($0.bundleID)
        }
    }

    private var excludedInstalledAppCount: Int {
        installedApps.filter { preferences.isExcluded(bundleID: $0.bundleID) }.count
    }

    private func refreshInstalledApps() {
#if os(macOS)
        installedApps = InstalledApplication.discover()
#endif
    }

}


private struct MemoryTrailClearCacheSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onClear: () -> Void
    @State private var didClear = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.97, blue: 1.00),
                    Color.white,
                    Color(red: 0.96, green: 0.98, blue: 1.00)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill((didClear ? Color.green : Color.blue).opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 48)
                .offset(x: 150, y: -150)

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill((didClear ? Color.green : Color.blue).opacity(0.11))
                        .frame(width: 94, height: 94)

                    Image(systemName: didClear ? "sparkles" : "externaldrive.badge.xmark")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(didClear ? .green : .blue)
                }
                .shadow(
                    color: (didClear ? Color.green : Color.blue).opacity(0.14),
                    radius: 18,
                    y: 7
                )

                Text(didClear ? "Fresh trail. Same memories." : "Clear the clutter?")
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                Text(
                    didClear
                        ? "Memory Trail’s temporary capture state and preferences are refreshed. Your Timeline entries stayed exactly where they belong."
                        : "This refreshes cached capture state and restores preferences to their defaults. Your Timeline history will not be deleted."
                )
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)

                if didClear {
                    Label("Cache cleared successfully", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Color.green.opacity(0.08), in: Capsule())

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else {
                    HStack(spacing: 10) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            onClear()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                didClear = true
                            }
                        } label: {
                            Label("Clear Cache", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(30)
        }
        .frame(width: 500, height: 390)
    }
}


#if os(macOS)
private struct InstalledApplication: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let url: URL

    var id: String { bundleID }

    static func discover() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var byBundleID: [String: InstalledApplication] = [:]
        for root in roots {
            scan(root: root, depth: 0, maxDepth: 2, into: &byBundleID)
        }

        return byBundleID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func scan(
        root: URL,
        depth: Int,
        maxDepth: Int,
        into apps: inout [String: InstalledApplication]
    ) {
        guard depth <= maxDepth,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              )
        else {
            return
        }

        for url in entries {
            if url.pathExtension.lowercased() == "app",
               let bundle = Bundle(url: url),
               let bundleID = bundle.bundleIdentifier,
               !bundleID.isEmpty {
                let name =
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                    url.deletingPathExtension().lastPathComponent

                apps[bundleID] = InstalledApplication(
                    bundleID: bundleID,
                    name: name,
                    url: url
                )
                continue
            }

            guard depth < maxDepth,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else {
                continue
            }

            scan(root: url, depth: depth + 1, maxDepth: maxDepth, into: &apps)
        }
    }
}

private struct InstalledAppPicker: View {
    @Environment(\.dismiss) private var dismiss
    let apps: [InstalledApplication]
    let preferences: RecallPreferences

    @State private var searchText = ""

    private var filteredApps: [InstalledApplication] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }

        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exclude Installed Apps")
                        .font(.system(size: 24, weight: .bold, design: .rounded))

                    Text("Selected apps will be ignored by Memory Trail capture.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search installed apps", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
                MemoryTrailPalette.elevatedStrong.opacity(0.94),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MemoryTrailPalette.border, lineWidth: 1)
            }
            .padding(16)

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filteredApps) { app in
                        InstalledAppRow(app: app, preferences: preferences)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(
            LinearGradient(
                colors: [MemoryTrailPalette.canvasTop, MemoryTrailPalette.canvasBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct InstalledAppRow: View {
    let app: InstalledApplication
    let preferences: RecallPreferences

    private var isMandatory: Bool {
        RecallExclusionOption.mandatoryBundleIDs.contains(app.bundleID)
    }

    private var exclusionBinding: Binding<Bool> {
        Binding(
            get: { preferences.isExcluded(bundleID: app.bundleID) },
            set: { preferences.setExcluded($0, bundleID: app.bundleID) }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline.weight(.medium))

                Text(app.bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isMandatory {
                Label("Always excluded", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: exclusionBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 58)
        .background(
            preferences.isExcluded(bundleID: app.bundleID)
                ? Color.accentColor.opacity(0.08)
                : MemoryTrailPalette.elevated.opacity(0.82),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    preferences.isExcluded(bundleID: app.bundleID)
                        ? Color.accentColor.opacity(0.28)
                        : MemoryTrailPalette.border,
                    lineWidth: 1
                )
        }
    }
}
#endif
