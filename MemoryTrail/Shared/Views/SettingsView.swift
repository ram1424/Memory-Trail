import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

extension Notification.Name {
    static let memoryTrailCheckForUpdates = Notification.Name("MemoryTrailCheckForUpdates")
}

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext
    @State private var captureCoordinator = MacCaptureCoordinator.shared
    @State private var customExclusions = ""
    @State private var showingInstalledAppPicker = false
    @State private var installedApps: [InstalledApplication] = []
    @State private var showingClearCacheSheet = false
    @State private var pendingHistoryClear: MemoryTrailHistoryClearRange?
    @State private var exportReceipt: MemoryTrailExportReceipt?
    @State private var showingStorageResult = false
    @State private var storageResultMessage = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var preferences = preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader
                settingsStatusStrip

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

                settingsCard("Storage & History", systemImage: "internaldrive.fill") {
                    storageAndHistoryContent
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
                        text: "Timeline data comes from local macOS app/window context, local files and paths, and the clipboard when enabled. Captured history is stored locally on this Mac using SwiftData and is automatically retained for 30 days by default."
                    )

                    privacyStatement(
                        icon: "icloud.slash.fill",
                        title: "No captured-data transmission",
                        text: "Memory Trail does not upload, sync, or send your captured timeline data outside of this computer."
                    )

                    privacyStatement(
                        icon: "link",
                        title: "No connectors of any kind",
                        text: "Memory Trail has no external data connectors. It does not connect your captured activity to cloud drives, email accounts, calendars, collaboration platforms, AI providers, analytics services, advertising systems, or other external services."
                    )

                    privacyStatement(
                        icon: "person.crop.circle.badge.xmark",
                        title: "No account to create",
                        text: "There is no Memory Trail account, sign-in, subscription account, remote profile, or cloud identity required to use the app."
                    )

                    privacyStatement(
                        icon: "icloud.slash.fill",
                        title: "No cloud processing or storage",
                        text: "Captured timeline data, clipboard history, files and paths, conversations, searches, Favorites, and manual memories are not processed, sent, synchronized, backed up, or stored on cloud services by Memory Trail."
                    )

                    privacyStatement(
                        icon: "brain.head.profile",
                        title: "No AI scraping or training",
                        text: "Memory Trail does not scrape your activity for AI, send captured data to AI providers, use it to train or fine-tune models, or perform remote AI summarization, profiling, embeddings, or inference."
                    )

                    privacyStatement(
                        icon: "checkmark.shield.fill",
                        title: "Verifiable source code",
                        text: "The source code is available publicly so you can review and verify how Memory Trail captures, processes, and stores data."
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Privacy Policy")
                            .font(.headline)

                        Text("Read the full policy covering local activity capture, Accessibility, clipboard history, exclusions, storage, update checks, GitHub network requests, retention, and deletion.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 10) {
                            Link(destination: URL(string: "https://github.com/ram1424/Memory-Trail/blob/main/PRIVACY.md")!) {
                                Label("View Privacy Policy", systemImage: "doc.text.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Link(destination: URL(string: "https://github.com/ram1424/Memory-Trail")!) {
                                Label("Review Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

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
                            "Version \(appVersion) • Build \(appBuild)",
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

                settingsFooter
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
        .onReceive(
            Timer.publish(
                every: 2.0,
                on: .main,
                in: .common
            ).autoconnect()
        ) { _ in
            captureCoordinator.refreshAccessibilityStatus()
        }
        .sheet(item: $pendingHistoryClear) { range in
            MemoryTrailHistoryClearSheet(
                range: range,
                onCancel: {
                    pendingHistoryClear = nil
                },
                onConfirm: {
                    clearHistory(range)
                }
            )
        }
        .sheet(item: $exportReceipt) { receipt in
            MemoryTrailExportSuccessSheet(
                receipt: receipt,
                onShowInFinder: {
#if os(macOS)
                    NSWorkspace.shared.activateFileViewerSelecting([receipt.url])
#endif
                },
                onDone: {
                    exportReceipt = nil
                }
            )
        }
        .alert("Storage & History", isPresented: $showingStorageResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(storageResultMessage)
        }
        .sheet(isPresented: $showingClearCacheSheet) {
            MemoryTrailClearCacheSheet {
                preferences.resetToDefaults()
                MacCaptureCoordinator.shared.clearRuntimeCache()
                customExclusions = preferences.customExcludedBundleIDs
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.allApps.filterTint)
                .frame(width: 48, height: 48)
                .background(
                    MemoryTrailCategory.allApps.filterBackground,
                    in: RoundedRectangle(cornerRadius: 14)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Tune what Memory Trail remembers, protects, and keeps close.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
        }
    }

    private var settingsStatusStrip: some View {
        HStack(spacing: 12) {
            settingsMetric(
                value: preferences.capturePaused ? "Paused" : "On",
                label: "Activity Capture",
                symbol: preferences.capturePaused ? "pause.circle.fill" : "record.circle.fill",
                category: .allApps
            )

            settingsMetric(
                value: captureCoordinator.hasAccessibilityPermission ? "Enabled" : "Needs Access",
                label: "Accessibility",
                symbol: captureCoordinator.hasAccessibilityPermission
                    ? "checkmark.shield.fill"
                    : "exclamationmark.shield.fill",
                category: .remoteAccess
            )

            settingsMetric(
                value: "\(excludedInstalledAppCount)",
                label: "Excluded Apps",
                symbol: "hand.raised.slash.fill",
                category: .files
            )

            settingsMetric(
                value: displayVersion,
                label: "Version / Build",
                symbol: "shippingbox.fill",
                category: .chat
            )
        }
    }

    private func settingsMetric(
        value: String,
        label: String,
        symbol: String,
        category: MemoryTrailCategory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(category.filterTint)
                .frame(width: 36, height: 36)
                .background(
                    category.filterBackground,
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(
            category.filterBackground.opacity(0.44),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(category.filterTint.opacity(0.10), lineWidth: 1)
        }
    }

    private var settingsFooter: some View {
        HStack {
            Link(destination: URL(string: "https://github.com/ram1424/Memory-Trail")!) {
                Label("Memory Trail on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)

            Spacer()

            Text("Version \(appVersion) • Build \(appBuild) • Created By: Roman Zakharov")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let category = settingsCategory(for: title)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(category.filterTint)
                    .frame(width: 34, height: 34)
                    .background(
                        category.filterBackground,
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            MemoryTrailPalette.elevatedStrong.opacity(0.96),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(category.filterTint.opacity(0.10), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var storageAndHistoryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MemoryTrailCategory.files.filterTint)
                    .frame(width: 38, height: 38)
                    .background(
                        MemoryTrailCategory.files.filterBackground,
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("30-day local history")
                        .font(.subheadline.weight(.semibold))

                    Text("Memory Trail keeps captured history on this Mac for 30 days by default. Items older than 30 days are removed automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Local database")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(MemoryTrailStorage.storeURL.path)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("All activity remains local unless you explicitly export a JSON copy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                exportActivityAsJSON()
            } label: {
                Label("Export Activity as JSON", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Clear history")
                    .font(.subheadline.weight(.semibold))

                Text("Choose how much recent activity to remove. These actions permanently delete matching local timeline, clipboard, favorite, and manual-memory records.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    historyClearButton(.lastWeek)
                    historyClearButton(.lastMonth)
                    historyClearButton(.all)
                }
            }
        }
    }

    private func historyClearButton(_ range: MemoryTrailHistoryClearRange) -> some View {
        Button(role: .destructive) {
            pendingHistoryClear = range
        } label: {
            Label(range.buttonTitle, systemImage: range.symbol)
        }
        .buttonStyle(.bordered)
    }

    private func clearHistory(_ range: MemoryTrailHistoryClearRange) {
        do {
            let descriptor = FetchDescriptor<MemoryItem>()
            let allItems = try modelContext.fetch(descriptor)
            let cutoff = range.cutoffDate

            let matches = allItems.filter { item in
                guard let cutoff else { return true }
                return item.createdAt >= cutoff
            }

            for item in matches {
                modelContext.delete(item)
            }

            try modelContext.save()
            pendingHistoryClear = nil
            storageResultMessage = "Deleted \(matches.count) local history item\(matches.count == 1 ? "" : "s") from \(range.title.lowercased())."
            showingStorageResult = true
        } catch {
            storageResultMessage = "Memory Trail could not clear the selected history: \(error.localizedDescription)"
            showingStorageResult = true
        }
    }

    private func exportActivityAsJSON() {
#if os(macOS)
        do {
            var descriptor = FetchDescriptor<MemoryItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 100_000
            let items = try modelContext.fetch(descriptor)

            let export = MemoryTrailActivityExport(
                exportedAt: Date(),
                version: appVersion,
                build: appBuild,
                retentionDays: MemoryTrailStorage.retentionDays,
                items: items.map { MemoryTrailActivityExport.Item($0) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(export)

            let panel = NSSavePanel()
            panel.title = "Export Memory Trail Activity"
            panel.prompt = "Export"
            panel.nameFieldStringValue = "MemoryTrail-Activity-\(Self.exportDateFormatter.string(from: Date())).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }

            try data.write(to: url, options: .atomic)
            exportReceipt = MemoryTrailExportReceipt(
                url: url,
                itemCount: items.count,
                byteCount: Int64(data.count)
            )
        } catch {
            storageResultMessage = "Memory Trail could not export activity: \(error.localizedDescription)"
            showingStorageResult = true
        }
#endif
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func settingsCategory(for title: String) -> MemoryTrailCategory {
        switch title {
        case "Capture": .allApps
        case "Excluded Apps & Services": .files
        case "Updates": .web
        case "Help": .chat
        case "Storage & History": .files
        case "Privacy": .remoteAccess
        default: .other
        }
    }

    private func privacyStatement(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MemoryTrailCategory.remoteAccess.filterTint)
                .frame(width: 30, height: 30)
                .background(
                    MemoryTrailCategory.remoteAccess.filterBackground,
                    in: RoundedRectangle(cornerRadius: 8)
                )

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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.3"
    }

    private var appBuild: Int {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return Int(value) ?? 0
    }

    private var displayVersion: String {
        "\(appVersion) • Build \(appBuild)"
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


enum MemoryTrailHistoryClearRange: Identifiable {
    case lastWeek
    case lastMonth
    case all

    var id: String { title }

    var title: String {
        switch self {
        case .lastWeek: "Last 7 Days"
        case .lastMonth: "Last 30 Days"
        case .all: "All History"
        }
    }

    var buttonTitle: String {
        switch self {
        case .lastWeek: "Last Week"
        case .lastMonth: "Last Month"
        case .all: "All History"
        }
    }

    var symbol: String {
        switch self {
        case .lastWeek: "calendar.badge.minus"
        case .lastMonth: "calendar"
        case .all: "trash.fill"
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        switch self {
        case .lastWeek:
            return calendar.date(byAdding: .day, value: -7, to: Date())
        case .lastMonth:
            return calendar.date(byAdding: .day, value: -30, to: Date())
        case .all:
            return nil
        }
    }

    var confirmationMessage: String {
        switch self {
        case .lastWeek:
            "This permanently deletes all locally stored activity from the last 7 days."
        case .lastMonth:
            "This permanently deletes all locally stored activity from the last 30 days."
        case .all:
            "This permanently deletes all locally stored Memory Trail history."
        }
    }

    var dialogTitle: String {
        switch self {
        case .lastWeek: "Clear Last Week?"
        case .lastMonth: "Clear Last Month?"
        case .all: "Clear All History?"
        }
    }

    var funMessage: String {
        switch self {
        case .lastWeek:
            "Sweep away the last 7 days and keep your trail fresh!"
        case .lastMonth:
            "Time for a monthly tidy-up! Remove the last 30 days of activity."
        case .all:
            "The full reset! Wipe the slate clean and start a brand-new trail."
        }
    }

    var actionTitle: String {
        switch self {
        case .lastWeek: "Sweep Last Week"
        case .lastMonth: "Tidy Last Month"
        case .all: "Start Fresh"
        }
    }

    var accent: Color {
        switch self {
        case .lastWeek:
            Color(red: 0.05, green: 0.43, blue: 0.98)
        case .lastMonth:
            Color(red: 0.48, green: 0.18, blue: 0.96)
        case .all:
            Color(red: 0.94, green: 0.08, blue: 0.28)
        }
    }

    var backgroundColors: [Color] {
        switch self {
        case .lastWeek:
            [Color(red: 0.89, green: 0.96, blue: 1.0), .white]
        case .lastMonth:
            [Color(red: 0.95, green: 0.91, blue: 1.0), .white]
        case .all:
            [Color(red: 1.0, green: 0.91, blue: 0.94), .white]
        }
    }

    var waveColor: Color {
        accent.opacity(0.10)
    }
}

struct MemoryTrailExportReceipt: Identifiable {
    let url: URL
    let itemCount: Int
    let byteCount: Int64

    var id: String { url.path }

    var formattedSize: String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
}

struct MemoryTrailExportSuccessSheet: View {
    let receipt: MemoryTrailExportReceipt
    let onShowInFinder: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.31, blue: 0.82),
                    Color(red: 0.18, green: 0.20, blue: 0.62),
                    Color(red: 0.26, green: 0.17, blue: 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Memory Trail")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                MemoryTrailExportArtwork()
                    .frame(height: 225)

                VStack(spacing: 8) {
                    Text("Activity Exported!")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your trail. Your data. Your file.")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .italic()
                        .foregroundStyle(.white.opacity(0.86))
                }

                HStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color(red: 0.64, green: 0.69, blue: 1.0))
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(receipt.url.lastPathComponent)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text("\(receipt.itemCount.formatted()) items  •  \(receipt.formattedSize)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    Spacer(minLength: 8)

                    Button {
                        onShowInFinder()
                    } label: {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 42, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .help("Show in Finder")
                }
                .padding(14)
                .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }

                Button {
                    onDone()
                } label: {
                    Label("Done", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .frame(minWidth: 170)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(28)
        }
        .frame(width: 660, height: 650)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct MemoryTrailExportArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.69, blue: 1.0).opacity(0.72),
                    Color(red: 0.98, green: 0.63, blue: 0.61).opacity(0.46),
                    Color(red: 0.18, green: 0.31, blue: 0.70).opacity(0.20)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.yellow.opacity(0.95), .orange.opacity(0.16)],
                        center: .center,
                        startRadius: 8,
                        endRadius: 58
                    )
                )
                .frame(width: 88, height: 88)
                .offset(x: -112, y: 18)

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 132))
                .foregroundStyle(Color(red: 0.27, green: 0.38, blue: 0.72).opacity(0.68))
                .offset(y: 38)

            HStack(spacing: 24) {
                ForEach(0..<6, id: \.self) { index in
                    Image(systemName: "tree.fill")
                        .font(.system(size: CGFloat(25 + (index % 3) * 8)))
                        .foregroundStyle(Color(red: 0.10, green: 0.27, blue: 0.52).opacity(0.78))
                }
            }
            .offset(y: 64)

            MemoryTrailRoadShape()
                .stroke(
                    LinearGradient(
                        colors: [.yellow.opacity(0.96), .white.opacity(0.82)],
                        startPoint: .bottom,
                        endPoint: .top
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: 270, height: 130)
                .offset(x: -82, y: 44)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(0.96))
                    .frame(width: 142, height: 150)
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)

                VStack(spacing: 10) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color(red: 0.42, green: 0.32, blue: 0.96))

                    Text("JSON")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.49, green: 0.28, blue: 0.96),
                                    Color(red: 0.34, green: 0.36, blue: 0.95)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                }

                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(
                            colors: [.green, Color(red: 0.23, green: 0.72, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        in: Circle()
                    )
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                    .offset(x: 71, y: 58)
            }
            .offset(x: 104, y: -2)
        }
    }
}

private struct MemoryTrailRoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX * 0.15, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.midX * 1.62, y: rect.minY),
            control1: CGPoint(x: rect.midX * 1.25, y: rect.maxY * 0.72),
            control2: CGPoint(x: rect.midX * 0.45, y: rect.maxY * 0.30)
        )
        return path
    }
}

struct MemoryTrailHistoryClearSheet: View {
    let range: MemoryTrailHistoryClearRange
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: range.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 22) {
                MemoryTrailHistoryIllustration(range: range)
                    .frame(height: 190)

                VStack(spacing: 8) {
                    Text(range.dialogTitle)
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.05, green: 0.12, blue: 0.31))

                    Text(range.funMessage)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color(red: 0.10, green: 0.18, blue: 0.35).opacity(0.84))
                        .frame(maxWidth: 470)
                }

                HStack(spacing: 14) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minWidth: 130)

                    Button(role: .destructive) {
                        onConfirm()
                    } label: {
                        Label(range.actionTitle, systemImage: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(minWidth: 190)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(range.accent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
        .frame(width: 620, height: 510)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct MemoryTrailHistoryIllustration: View {
    let range: MemoryTrailHistoryClearRange

    var body: some View {
        ZStack {
            MemoryTrailFunWave()
                .fill(range.waveColor)
                .frame(height: 105)
                .offset(y: 61)

            switch range {
            case .lastWeek:
                ZStack {
                    MemoryTrailCalendarTile(number: "7", tint: range.accent)
                    Text("😎")
                        .font(.system(size: 42))
                        .offset(x: 18, y: -17)
                    Text("👍")
                        .font(.system(size: 30))
                        .offset(x: 70, y: 0)
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(.white.opacity(0.80))
                        .rotationEffect(.degrees(14))
                        .offset(x: 115, y: -40)
                }

            case .lastMonth:
                ZStack {
                    MemoryTrailCalendarTile(number: "30", tint: range.accent)
                        .offset(x: -28)
                    Text("🧹")
                        .font(.system(size: 54))
                        .rotationEffect(.degrees(-18))
                        .offset(x: 46, y: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.yellow)
                        .offset(x: 86, y: -52)
                }

            case .all:
                ZStack {
                    VStack(spacing: -30) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 13)
                                .fill(.white.opacity(0.94))
                                .frame(width: 145, height: 78)
                                .overlay {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(range.accent.opacity(0.72))
                                }
                                .offset(x: CGFloat(index * 8))
                        }
                    }
                    .rotationEffect(.degrees(-4))

                    Text("😎")
                        .font(.system(size: 42))
                        .offset(x: 16, y: -18)
                    Text("🏖️")
                        .font(.system(size: 72))
                        .offset(x: 92, y: -48)
                }
            }
        }
    }
}

private struct MemoryTrailCalendarTile: View {
    let number: String
    let tint: Color

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 19)
                .fill(tint)
                .frame(width: 132, height: 44)
                .overlay(alignment: .top) {
                    HStack(spacing: 56) {
                        Capsule().fill(.white.opacity(0.9)).frame(width: 10, height: 25)
                        Capsule().fill(.white.opacity(0.9)).frame(width: 10, height: 25)
                    }
                    .offset(y: -9)
                }

            Text(number)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(width: 132, height: 100)
                .background(.white.opacity(0.97))
        }
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .shadow(color: tint.opacity(0.24), radius: 18, y: 9)
    }
}

private struct MemoryTrailFunWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.45))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.32),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.68, y: rect.height * 0.82)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct MemoryTrailActivityExport: Encodable {
    let exportedAt: Date
    let version: String
    let build: Int
    let retentionDays: Int
    let items: [Item]

    struct Item: Encodable {
        let id: UUID
        let createdAt: Date
        let title: String
        let body: String
        let sourceApp: String
        let sourceBundleID: String
        let sourceKind: String
        let sourceURL: String?
        let isFavorite: Bool

        init(_ item: MemoryItem) {
            id = item.id
            createdAt = item.createdAt
            title = item.title
            body = item.body
            sourceApp = item.sourceApp
            sourceBundleID = item.sourceBundleID
            sourceKind = item.sourceKindRaw
            sourceURL = item.sourceURL
            isFavorite = item.isFavorite
        }
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
