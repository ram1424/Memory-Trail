#if os(iOS)
import UIKit
import UniformTypeIdentifiers
import SwiftData

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()

        Task { @MainActor in
            await captureSharedContent()
        }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground
        statusLabel.text = "Saving to Recall…"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @MainActor
    private func captureSharedContent() async {
        do {
            guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else {
                finish()
                return
            }

            guard let captured = try await extractContent(from: inputItems) else {
                statusLabel.text = "Nothing supported was shared."
                try? await Task.sleep(for: .seconds(1))
                finish()
                return
            }

            let container = try RecallSharedStore.makeContainer()
            let context = ModelContext(container)
            context.insert(
                MemoryItem(
                    title: captured.title,
                    body: captured.body,
                    sourceApp: captured.sourceApp,
                    sourceBundleID: "",
                    sourceKind: captured.kind,
                    sourceURL: captured.url
                )
            )
            try context.save()

            statusLabel.text = "Saved to Recall"
            try? await Task.sleep(for: .milliseconds(450))
            finish()
        } catch {
            statusLabel.text = "Couldn’t save to Recall."
            try? await Task.sleep(for: .seconds(1))
            finish()
        }
    }

    private func extractContent(from items: [NSExtensionItem]) async throws -> CapturedShare? {
        for item in items {
            if let attributed = item.attributedContentText, attributed.length > 0 {
                let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return CapturedShare(
                        title: String(text.prefix(90)),
                        body: text,
                        kind: .note,
                        url: nil,
                        sourceApp: "Shared from iPhone"
                    )
                }
            }

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let loaded = try await provider.recallLoadItem(forTypeIdentifier: UTType.url.identifier) {
                    let url = (loaded as? URL) ?? (loaded as? NSURL).map { $0 as URL }
                    if let url {
                        return CapturedShare(
                            title: readableTitle(for: url),
                            body: url.absoluteString,
                            kind: .link,
                            url: url.absoluteString,
                            sourceApp: "Shared from iPhone"
                        )
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let loaded = try await provider.recallLoadItem(forTypeIdentifier: UTType.plainText.identifier) {
                    let text = (loaded as? String) ?? (loaded as? NSString).map(String.init)
                    if let text {
                        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            return CapturedShare(
                                title: String(cleaned.prefix(90)),
                                body: cleaned,
                                kind: .note,
                                url: nil,
                                sourceApp: "Shared from iPhone"
                            )
                        }
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   let loaded = try await provider.recallLoadItem(forTypeIdentifier: UTType.fileURL.identifier) {
                    let url = (loaded as? URL) ?? (loaded as? NSURL).map { $0 as URL }
                    if let url {
                        return CapturedShare(
                            title: url.lastPathComponent.isEmpty ? "Shared file" : url.lastPathComponent,
                            body: "File shared to Recall from iPhone.",
                            kind: .file,
                            url: nil,
                            sourceApp: "Files / Share Sheet"
                        )
                    }
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    return CapturedShare(
                        title: item.attributedTitle?.string ?? "Shared image",
                        body: "Image shared to Recall from iPhone.",
                        kind: .screenshot,
                        url: nil,
                        sourceApp: "Photos / Share Sheet"
                    )
                }
            }
        }
        return nil
    }

    private func readableTitle(for url: URL) -> String {
        if let host = url.host(), !host.isEmpty {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct CapturedShare {
    let title: String
    let body: String
    let kind: SourceKind
    let url: String?
    let sourceApp: String
}

private extension NSItemProvider {
    func recallLoadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item as? NSSecureCoding)
                }
            }
        }
    }
}
#endif
