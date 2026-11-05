import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(RecallPreferences.self) private var preferences
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \MemoryItem.createdAt, order: .reverse)
    private var memories: [MemoryItem]

    @State private var customExclusions = ""
    @State private var pendingClear: AppStoreClearRange?
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var preferences = preferences

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Settings")
                        .font(.largeTitle.bold())
                    Text("Mac App Store Edition — sandboxed and local-first.")
                        .foregroundStyle(.secondary)
                }

                card("Capture", systemImage: "record.circle") {
                    Toggle(
                        "Pause all capture",
                        isOn: $preferences.capturePaused
                    )
                    Toggle(
                        "Remember application switches",
                        isOn: $preferences.captureAppActivity
                    )
                    Toggle(
                        "Remember copied text",
                        isOn: $preferences.captureClipboard
                    )

                    Divider()

                    Label(
                        "Sandbox-safe capture",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.headline)

                    Text(
                        "This edition records application activation events published by macOS. It does not inspect Outlook messages, browser tabs, Teams conversations, or other apps’ focused windows with Accessibility APIs."
                    )
                    .foregroundStyle(.secondary)

                    Text(
                        "Clipboard Capture is off by default. Turn it on only if you want copied text stored in your local history."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                card(
                    "Excluded Apps & Services",
                    systemImage: "hand.raised.slash"
                ) {
                    Text(
                        "Passwords and Wallet are always excluded. You can also enter bundle identifiers for apps whose activation or clipboard activity should be ignored."
                    )
                    .foregroundStyle(.secondary)

                    ForEach(
                        RecallExclusionOption.catalog.filter(\.isAlwaysExcluded)
                    ) { option in
                        HStack(spacing: 10) {
                            Image(systemName: option.systemImage)
                                .frame(width: 24)
                            Text(option.name)
                            Spacer()
                            Label("Always excluded", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    TextField(
                        "com.example.app, com.example.other",
                        text: $customExclusions,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .onSubmit { applyCustomExclusions() }

                    Button("Apply Custom Exclusions") {
                        applyCustomExclusions()
                    }
                    .buttonStyle(.bordered)
                }

                card(
                    "Storage & History",
                    systemImage: "internaldrive.fill"
                ) {
                    LabeledContent(
                        "Stored activities",
                        value: "\(memories.count)"
                    )
                    LabeledContent(
                        "Retention",
                        value: "\(MemoryTrailStorage.retentionDays) days"
                    )

                    Text(MemoryTrailStorage.storeURL.path)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Divider()

                    HStack {
                        Button {
                            exportActivity()
                        } label: {
                            Label(
                                "Export Activity as JSON",
                                systemImage: "square.and.arrow.up"
                            )
                        }

                        Menu("Clear History") {
                            Button("Last 7 Days", role: .destructive) {
                                pendingClear = .week
                            }
                            Button("Last 30 Days", role: .destructive) {
                                pendingClear = .month
                            }
                            Divider()
                            Button("All History", role: .destructive) {
                                pendingClear = .all
                            }
                        }
                    }

                    Text(
                        "Exports use the standard macOS save panel, so this sandboxed build can write only to a location you explicitly choose."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                card("Privacy", systemImage: "lock.shield.fill") {
                    privacyRow(
                        "shippingbox.fill",
                        "App Sandbox enabled",
                        "The Mac App Store edition runs inside Apple’s App Sandbox."
                    )
                    privacyRow(
                        "internaldrive.fill",
                        "Stored locally",
                        "App-switch history, optional clipboard text, manual memories, Favorites, and searches stay in the local app container."
                    )
                    privacyRow(
                        "accessibility",
                        "No Accessibility inspection",
                        "This edition does not read Outlook subjects, Teams conversation titles, browser tabs, or other apps’ focused-window content."
                    )
                    privacyRow(
                        "icloud.slash.fill",
                        "No cloud timeline",
                        "Memory Trail does not upload or synchronize your captured history."
                    )

                    Button("View Privacy Policy") {
                        if let url = URL(
                            string:
                                "https://github.com/ram1424/Memory-Trail/blob/main/PRIVACY.md"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                card(
                    "App Store & Updates",
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.object(
                            forInfoDictionaryKey:
                                "CFBundleShortVersionString"
                        ) as? String ?? "—"
                    )
                    LabeledContent(
                        "Build",
                        value: Bundle.main.object(
                            forInfoDictionaryKey:
                                "CFBundleVersion"
                        ) as? String ?? "—"
                    )
                    Text(
                        "Updates for this edition are delivered through the Mac App Store. The direct-download GitHub updater is intentionally not included."
                    )
                    .foregroundStyle(.secondary)
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        .onAppear {
            customExclusions = preferences.customExcludedBundleIDs
        }
        .confirmationDialog(
            "Clear Memory Trail History?",
            isPresented: Binding(
                get: { pendingClear != nil },
                set: { if !$0 { pendingClear = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(
                pendingClear?.buttonTitle ?? "Clear",
                role: .destructive
            ) {
                if let pendingClear {
                    clearHistory(pendingClear)
                }
                pendingClear = nil
            }
            Button("Cancel", role: .cancel) {
                pendingClear = nil
            }
        } message: {
            Text(pendingClear?.message ?? "")
        }
    }

    @ViewBuilder
    private func card<Content: View>(
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            MemoryTrailPalette.elevated,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MemoryTrailPalette.border, lineWidth: 1)
        }
    }

    private func privacyRow(
        _ icon: String,
        _ title: String,
        _ text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyCustomExclusions() {
        preferences.updateCustomExclusions(from: customExclusions)
        customExclusions = preferences.customExcludedBundleIDs
        statusMessage = "Exclusions updated."
    }

    private func clearHistory(_ range: AppStoreClearRange) {
        let cutoff: Date?

        switch range {
        case .week:
            cutoff = Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: Date()
            )
        case .month:
            cutoff = Calendar.current.date(
                byAdding: .day,
                value: -30,
                to: Date()
            )
        case .all:
            cutoff = nil
        }

        do {
            let items = try modelContext.fetch(
                FetchDescriptor<MemoryItem>()
            )
            var deleted = 0

            for item in items {
                if cutoff == nil || item.createdAt >= cutoff! {
                    modelContext.delete(item)
                    deleted += 1
                }
            }

            try modelContext.save()
            statusMessage =
                "Deleted \(deleted) local activit\(deleted == 1 ? "y" : "ies")."
        } catch {
            statusMessage =
                "Could not clear history: \(error.localizedDescription)"
        }
    }

    private func exportActivity() {
        do {
            let items = try modelContext.fetch(
                FetchDescriptor<MemoryItem>(
                    sortBy: [
                        SortDescriptor(
                            \MemoryItem.createdAt,
                            order: .reverse
                        )
                    ]
                )
            )

            let payload = AppStoreActivityExport(
                exportedAt: Date(),
                retentionDays: MemoryTrailStorage.retentionDays,
                items: items.map { .init($0) }
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)

            let panel = NSSavePanel()
            panel.title = "Export Memory Trail Activity"
            panel.prompt = "Export"
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue =
                "MemoryTrail-Activity-\(Self.exportDateFormatter.string(from: Date())).json"

            guard panel.runModal() == .OK,
                  let url = panel.url
            else { return }

            try data.write(to: url, options: .atomic)
            statusMessage =
                "Exported \(items.count) activities to \(url.lastPathComponent)."
        } catch {
            statusMessage =
                "Could not export activity: \(error.localizedDescription)"
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private enum AppStoreClearRange {
    case week
    case month
    case all

    var buttonTitle: String {
        switch self {
        case .week: "Clear Last 7 Days"
        case .month: "Clear Last 30 Days"
        case .all: "Clear All History"
        }
    }

    var message: String {
        switch self {
        case .week:
            "This permanently deletes local activity from the last 7 days."
        case .month:
            "This permanently deletes local activity from the last 30 days."
        case .all:
            "This permanently deletes all locally stored Memory Trail activity."
        }
    }
}

private struct AppStoreActivityExport: Encodable {
    let exportedAt: Date
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
            sourceKind = item.sourceKind.rawValue
            sourceURL = item.sourceURL
            isFavorite = item.isFavorite
        }
    }
}
