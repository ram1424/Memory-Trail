import Foundation
import Observation

struct RecallExclusionOption: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let isAlwaysExcluded: Bool

    static let catalog: [RecallExclusionOption] = [
        .init(id: "com.apple.Passbook", name: "Wallet", systemImage: "wallet.pass", isAlwaysExcluded: true),
        .init(id: "com.apple.Passwords", name: "Passwords", systemImage: "key.fill", isAlwaysExcluded: true),
        .init(id: "com.1password.1password", name: "1Password", systemImage: "lock.shield", isAlwaysExcluded: false),
        .init(id: "com.apple.keychainaccess", name: "Keychain Access", systemImage: "key", isAlwaysExcluded: false),
        .init(id: "com.apple.MobileSMS", name: "Messages", systemImage: "message", isAlwaysExcluded: false),
        .init(id: "com.apple.mail", name: "Mail", systemImage: "envelope", isAlwaysExcluded: false),
        .init(id: "com.apple.Safari", name: "Safari", systemImage: "safari", isAlwaysExcluded: false),
        .init(id: "com.google.Chrome", name: "Google Chrome", systemImage: "globe", isAlwaysExcluded: false),
        .init(id: "com.microsoft.teams2", name: "Microsoft Teams", systemImage: "person.2", isAlwaysExcluded: false),
        .init(id: "com.tinyspeck.slackmacgap", name: "Slack", systemImage: "bubble.left.and.bubble.right", isAlwaysExcluded: false)
    ]

    static let mandatoryBundleIDs: Set<String> = Set(catalog.filter(\.isAlwaysExcluded).map(\.id))
}

@Observable
final class RecallPreferences {
    static let shared = RecallPreferences()

    private enum Key {
        static let capturePaused = "capturePaused"
        static let captureAppActivity = "captureAppActivity"
        static let captureClipboard = "captureClipboard"
        static let excludedBundleIDs = "excludedBundleIDs"
    }

    var capturePaused: Bool {
        didSet { defaults.set(capturePaused, forKey: Key.capturePaused) }
    }

    var captureAppActivity: Bool {
        didSet { defaults.set(captureAppActivity, forKey: Key.captureAppActivity) }
    }

    var captureClipboard: Bool {
        didSet { defaults.set(captureClipboard, forKey: Key.captureClipboard) }
    }

    /// Comma-separated bundle identifiers retained for simple UserDefaults persistence and
    /// compatibility with earlier Recall MVP builds.
    var excludedBundleIDs: String {
        didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) }
    }

    private let defaults = UserDefaults.standard

    private init() {
        capturePaused = defaults.object(forKey: Key.capturePaused) as? Bool ?? false
        captureAppActivity = defaults.object(forKey: Key.captureAppActivity) as? Bool ?? true
        captureClipboard = defaults.object(forKey: Key.captureClipboard) as? Bool ?? true

        let saved = defaults.string(forKey: Key.excludedBundleIDs)
        let savedSet = Self.parseBundleIDs(saved ?? "")
        let merged = savedSet.union(RecallExclusionOption.mandatoryBundleIDs)
        excludedBundleIDs = Self.serializeBundleIDs(merged)
        defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs)
    }

    var excludedBundleIDSet: Set<String> {
        Self.parseBundleIDs(excludedBundleIDs).union(RecallExclusionOption.mandatoryBundleIDs)
    }

    func isExcluded(bundleID: String) -> Bool {
        excludedBundleIDSet.contains(bundleID)
    }

    func isExcluded(option: RecallExclusionOption) -> Bool {
        option.isAlwaysExcluded || excludedBundleIDSet.contains(option.id)
    }

    func setExcluded(_ excluded: Bool, option: RecallExclusionOption) {
        guard !option.isAlwaysExcluded else { return }
        var values = excludedBundleIDSet
        if excluded {
            values.insert(option.id)
        } else {
            values.remove(option.id)
        }
        values.formUnion(RecallExclusionOption.mandatoryBundleIDs)
        excludedBundleIDs = Self.serializeBundleIDs(values)
    }

    func updateCustomExclusions(from text: String) {
        let catalogIDs = Set(RecallExclusionOption.catalog.map(\.id))
        let selectedCatalogIDs = excludedBundleIDSet.intersection(catalogIDs)
        let customIDs = Self.parseBundleIDs(text)
        excludedBundleIDs = Self.serializeBundleIDs(selectedCatalogIDs.union(customIDs).union(RecallExclusionOption.mandatoryBundleIDs))
    }

    var customExcludedBundleIDs: String {
        let catalogIDs = Set(RecallExclusionOption.catalog.map(\.id))
        let custom = excludedBundleIDSet.subtracting(catalogIDs)
        return custom.sorted().joined(separator: ",")
    }

    private static func parseBundleIDs(_ value: String) -> Set<String> {
        Set(value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static func serializeBundleIDs(_ values: Set<String>) -> String {
        values.sorted().joined(separator: ",")
    }
}
