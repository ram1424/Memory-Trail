import Foundation
import SwiftData

@Model
final class MemoryItem {
    var id: UUID
    var createdAt: Date
    var title: String
    var body: String
    var sourceApp: String
    var sourceBundleID: String
    var sourceKindRaw: String
    var sourceURL: String?
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        title: String,
        body: String = "",
        sourceApp: String = "Memory Lane",
        sourceBundleID: String = "",
        sourceKind: SourceKind = .note,
        sourceURL: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.body = body
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceURL = sourceURL
        self.isFavorite = isFavorite
    }

    var sourceKind: SourceKind {
        get { SourceKind(rawValue: sourceKindRaw) ?? .note }
        set { sourceKindRaw = newValue.rawValue }
    }

    var displayTitle: String {
        guard isOutlookActivity else { return title }

        let value = title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        if lower.contains(", sent by "),
           lower.contains("; has "),
           lower.contains("attachment"),
           let range = value.range(of: ", sent by ", options: .caseInsensitive) {
            let subjectOnly = String(value[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !subjectOnly.isEmpty {
                return subjectOnly
            }
        }

        return value
    }

    var isOutlookCaptureNoise: Bool {
        guard isOutlookActivity else { return false }

        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        if lower.hasPrefix("inbox;") && lower.contains("unread message") { return true }
        if lower.hasPrefix("from ") && lower.contains(" to ") && lower.contains(" events") { return true }
        if lower.contains("copyright ©") || lower.contains("all rights reserved") { return true }
        if lower.contains("one apple park way") { return true }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return true }
        if lower.contains("urldefense.com/") || lower.contains("safelinks.protection.outlook.com/") { return true }
        if lower.contains("outlook.office.com/") { return true }

        return [
            "inbox",
            "mail",
            "calendar",
            "people",
            "contacts",
            "tasks",
            "microsoft outlook",
            "outlook"
        ].contains(lower)
    }

    private var isOutlookActivity: Bool {
        sourceBundleID.lowercased() == "com.microsoft.outlook"
            || sourceApp.lowercased().contains("outlook")
    }

    var searchableText: String {
        [displayTitle, body, sourceApp, sourceBundleID, sourceURL ?? ""]
            .joined(separator: " ")
            .lowercased()
    }
}

enum SourceKind: String, CaseIterable, Identifiable {
    case note = "Note"
    case appActivity = "App Activity"
    case clipboard = "Clipboard"
    case link = "Link"
    case file = "File"
    case screenshot = "Screenshot"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .note: "note.text"
        case .appActivity: "macwindow"
        case .clipboard: "doc.on.clipboard"
        case .link: "link"
        case .file: "doc"
        case .screenshot: "camera.viewfinder"
        }
    }
}
