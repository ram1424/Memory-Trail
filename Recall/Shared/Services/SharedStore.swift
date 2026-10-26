#if os(iOS)
import Foundation
import SwiftData

enum RecallSharedStore {
    static let appGroupID = "group.com.ram1424.recall"
    private static let storeName = "Recall.store"
    private static let inboxDirectoryName = "RecallInbox"

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([MemoryItem.self])
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw RecallSharedStoreError.appGroupUnavailable
        }

        let storeURL = groupURL.appendingPathComponent(storeName)
        let configuration = ModelConfiguration(
            "RecallShared",
            schema: schema,
            url: storeURL,
            allowsSave: true
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func enqueue(_ item: RecallPendingItem) throws {
        let directory = try inboxDirectory()
        let fileURL = directory.appendingPathComponent("\(item.id.uuidString).json")
        let data = try JSONEncoder().encode(item)
        try data.write(to: fileURL, options: .atomic)
    }

    @MainActor
    static func importPendingItems(into context: ModelContext) {
        guard let directory = try? inboxDirectory() else { return }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var importedAny = false

        for fileURL in files where fileURL.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let pending = try JSONDecoder().decode(RecallPendingItem.self, from: data)

                context.insert(
                    MemoryItem(
                        id: pending.id,
                        createdAt: pending.createdAt,
                        title: pending.title,
                        body: pending.body,
                        sourceApp: pending.sourceApp,
                        sourceBundleID: pending.sourceBundleID,
                        sourceKind: SourceKind(rawValue: pending.sourceKindRaw) ?? .note,
                        sourceURL: pending.sourceURL
                    )
                )

                try FileManager.default.removeItem(at: fileURL)
                importedAny = true
            } catch {
                continue
            }
        }

        if importedAny {
            try? context.save()
        }
    }

    private static func inboxDirectory() throws -> URL {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw RecallSharedStoreError.appGroupUnavailable
        }

        let directory = groupURL.appendingPathComponent(inboxDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

struct RecallPendingItem: Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    let body: String
    let sourceApp: String
    let sourceBundleID: String
    let sourceKindRaw: String
    let sourceURL: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        body: String,
        sourceApp: String,
        sourceBundleID: String = "",
        sourceKind: SourceKind,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceURL = sourceURL
    }
}

enum RecallSharedStoreError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "Recall could not access its shared App Group container."
    }
}
#endif
