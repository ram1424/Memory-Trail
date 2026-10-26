#if os(iOS)
import Foundation
import SwiftData

enum RecallSharedStore {
    static let appGroupID = "group.com.ram1424.recall"
    private static let storeName = "Recall.store"

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([MemoryItem.self])
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
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
}

enum RecallSharedStoreError: LocalizedError {
    case appGroupUnavailable
    var errorDescription: String? { "Recall could not access its shared App Group container." }
}
#endif
