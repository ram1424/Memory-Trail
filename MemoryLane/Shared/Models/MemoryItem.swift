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

    var searchableText: String {
        [title, body, sourceApp, sourceBundleID, sourceURL ?? ""]
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
