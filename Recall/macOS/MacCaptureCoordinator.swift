#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import SwiftData

@MainActor
final class MacCaptureCoordinator {
    static let shared = MacCaptureCoordinator()

    private var appObserver: NSObjectProtocol?
    private var clipboardTimer: Timer?
    private var windowTimer: Timer?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var lastWindowSignature = ""
    private var lastWindowLoggedAt = Date.distantPast
    private weak var context: ModelContext?

    func start(context: ModelContext) {
        self.context = context
        startAppActivityCapture()
        startFocusedWindowCapture()
        startClipboardCapture()
    }

    func stop() {
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }

        clipboardTimer?.invalidate()
        clipboardTimer = nil

        windowTimer?.invalidate()
        windowTimer = nil
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    private func startAppActivityCapture() {
        guard appObserver == nil else { return }

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.capture(application: application)
            }
        }
    }

    private func capture(application: NSRunningApplication) {
        let prefs = RecallPreferences.shared
        guard !prefs.capturePaused, prefs.captureAppActivity else { return }

        let bundleID = application.bundleIdentifier ?? ""
        guard !prefs.isExcluded(bundleID: bundleID) else { return }
        guard bundleID != Bundle.main.bundleIdentifier else { return }

        let name = application.localizedName ?? "Application"

        if let context {
            context.insert(
                MemoryItem(
                    title: "Opened \(name)",
                    body: bundleID,
                    sourceApp: name,
                    sourceBundleID: bundleID,
                    sourceKind: .appActivity
                )
            )
            try? context.save()
        }

        lastWindowSignature = ""
    }

    private func startFocusedWindowCapture() {
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFocusedWindow()
            }
        }
    }

    private func pollFocusedWindow() {
        let prefs = RecallPreferences.shared
        guard !prefs.capturePaused, prefs.captureAppActivity else { return }
        guard AXIsProcessTrusted() else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let bundleID = app.bundleIdentifier ?? ""
        guard !prefs.isExcluded(bundleID: bundleID) else { return }
        guard bundleID != Bundle.main.bundleIdentifier else { return }

        guard let windowContext = focusedWindowContext(pid: app.processIdentifier) else { return }

        let appName = app.localizedName ?? "Application"
        let rawTitle = preferredActivityTitle(
            windowTitle: windowContext.title,
            selectedContent: windowContext.selectedContent,
            focusedContent: windowContext.focusedContent,
            bundleID: bundleID
        )
        let title = normalizeWindowTitle(
            rawTitle,
            applicationName: appName,
            bundleID: bundleID
        )

        guard !title.isEmpty else { return }
        guard !isGenericWindowTitle(title, applicationName: appName) else { return }

        let signature = "\(bundleID)|\(title.lowercased())"
        let now = Date()

        guard signature != lastWindowSignature else { return }
        guard now.timeIntervalSince(lastWindowLoggedAt) >= 1.0 else { return }

        lastWindowSignature = signature
        lastWindowLoggedAt = now

        if let context {
            context.insert(
                MemoryItem(
                    title: title,
                    body: detailedBody(for: title, applicationName: appName, bundleID: bundleID),
                    sourceApp: appName,
                    sourceBundleID: bundleID,
                    sourceKind: .appActivity,
                    sourceURL: windowContext.sourceURL
                )
            )
            try? context.save()
        }
    }

    private func focusedWindowContext(pid: pid_t) -> FocusedWindowContext? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard focusedResult == .success,
              let focusedWindowValue,
              CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let windowElement = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)

        var title = ""
        var titleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success, let value = titleValue as? String {
            title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var document = ""
        var documentValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            kAXDocumentAttribute as CFString,
            &documentValue
        ) == .success, let value = documentValue as? String {
            document = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if title.isEmpty {
            title = document
        }

        guard !title.isEmpty else { return nil }

        return FocusedWindowContext(
            title: title,
            sourceURL: normalizedSourceURL(document),
            selectedContent: selectedContentTitle(in: windowElement),
            focusedContent: focusedElementTitle(in: appElement)
        )
    }

    private func normalizedSourceURL(_ value: String) -> String? {
        guard !value.isEmpty, let url = URL(string: value) else { return nil }

        switch url.scheme?.lowercased() {
        case "http", "https", "file", "mailto", "message", "msteams", "ms-outlook", "outlook":
            return url.absoluteString
        default:
            return nil
        }
    }

    private struct FocusedWindowContext {
        let title: String
        let sourceURL: String?
        let selectedContent: String?
        let focusedContent: String?
    }

    private func preferredActivityTitle(
        windowTitle: String,
        selectedContent: String?,
        focusedContent: String?,
        bundleID: String
    ) -> String {
        let lowerBundleID = bundleID.lowercased()

        if lowerBundleID == "com.microsoft.outlook" {
            if let selectedContent, isMeaningfulInnerWindowTitle(selectedContent) {
                return selectedContent
            }
            if let focusedContent, isMeaningfulInnerWindowTitle(focusedContent) {
                return focusedContent
            }
        }

        if let selectedContent, isMeaningfulInnerWindowTitle(selectedContent) {
            return selectedContent
        }

        if let focusedContent, isMeaningfulInnerWindowTitle(focusedContent) {
            return focusedContent
        }

        return windowTitle
    }

    private func selectedContentTitle(in root: AXUIElement) -> String? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 300 {
            let element = queue[index]
            index += 1
            inspected += 1

            var selectedChildrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedChildrenAttribute as CFString,
                &selectedChildrenValue
            ) == .success,
               let selectedChildren = selectedChildrenValue as? [AXUIElement],
               let selected = selectedChildren.first,
               let title = bestText(in: selected) {
                return title
            }

            var selectedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedAttribute as CFString,
                &selectedValue
            ) == .success,
               let isSelected = selectedValue as? Bool,
               isSelected,
               let title = bestText(in: element) {
                return title
            }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(80))
            }
        }

        return nil
    }

    private func focusedElementTitle(in appElement: AXUIElement) -> String? {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focused = unsafeBitCast(focusedValue, to: AXUIElement.self)
        return bestText(in: focused)
    }

    private func bestText(in root: AXUIElement) -> String? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var candidates: [String] = []

        while index < queue.count, index < 120 {
            let element = queue[index]
            index += 1

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDescriptionAttribute as CFString
            ] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                   let text = value as? String {
                    let cleaned = text
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if isMeaningfulInnerWindowTitle(cleaned) {
                        candidates.append(cleaned)
                    }
                }
            }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
               let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(50))
            }
        }

        return candidates
            .filter { !$0.contains("@") || $0.contains(" ") }
            .sorted { lhs, rhs in
                scoreContextText(lhs) > scoreContextText(rhs)
            }
            .first
    }

    private func scoreContextText(_ text: String) -> Int {
        let lower = text.lowercased()
        var score = min(text.count, 120)

        if text.contains(" ") { score += 30 }
        if text.count >= 8 && text.count <= 140 { score += 30 }
        if lower.contains("re:") || lower.contains("fw:") || lower.contains("fwd:") { score += 40 }
        if lower.contains("today") || lower.contains("yesterday") { score -= 20 }
        if lower == "inbox" || lower == "mail" || lower == "focused" || lower == "other" { score -= 100 }

        return score
    }

    private func isMeaningfulInnerWindowTitle(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.count <= 250 else { return false }

        let generic = Set([
            "button", "group", "table", "list", "row", "scroll area",
            "split group", "toolbar", "mail", "inbox", "focused", "other",
            "microsoft outlook", "microsoft teams", "safari", "window"
        ])

        return !generic.contains(value.lowercased())
    }

    private func normalizeWindowTitle(
        _ rawTitle: String,
        applicationName: String,
        bundleID: String
    ) -> String {
        var title = rawTitle
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let suffixes = [
            " - Microsoft Outlook",
            " — Microsoft Outlook",
            " | Microsoft Teams",
            " - Microsoft Teams",
            " — Microsoft Teams",
            " - Safari",
            " — Safari",
            " - Mail",
            " — Mail",
            " - Google Chrome",
            " — Google Chrome"
        ]

        for suffix in suffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if title == applicationName {
            return ""
        }

        if bundleID == "com.apple.mail", title.lowercased() == "mail" {
            return ""
        }

        return String(title.prefix(250))
    }

    private func detailedBody(
        for title: String,
        applicationName: String,
        bundleID: String
    ) -> String {
        switch bundleID {
        case "com.apple.mail":
            return "Mail item viewed: \(title)"
        case "com.microsoft.Outlook", "com.microsoft.outlook":
            return "Outlook item viewed: \(title)"
        case "com.microsoft.teams2":
            return "Teams window viewed: \(title)"
        case "com.apple.Safari":
            return "Safari page viewed: \(title)"
        case "com.google.Chrome":
            return "Chrome page viewed: \(title)"
        default:
            return "Focused window in \(applicationName): \(title)"
        }
    }

    private func isGenericWindowTitle(_ title: String, applicationName: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let generic = [
            "",
            applicationName.lowercased(),
            "new tab",
            "start page",
            "untitled",
            "home",
            "settings",
            "preferences"
        ]
        return generic.contains(value)
    }

    private func startClipboardCapture() {
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollClipboard() }
        }
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pasteboard.changeCount

        let prefs = RecallPreferences.shared
        guard !prefs.capturePaused, prefs.captureClipboard else { return }
        guard let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        guard text.count <= 20_000 else { return }

        let active = NSWorkspace.shared.frontmostApplication
        let bundleID = active?.bundleIdentifier ?? ""
        guard !prefs.isExcluded(bundleID: bundleID) else { return }
        guard bundleID != Bundle.main.bundleIdentifier else { return }

        let source = active?.localizedName ?? "Clipboard"
        let preview = text.replacingOccurrences(of: "\n", with: " ")

        context?.insert(
            MemoryItem(
                title: String(preview.prefix(90)),
                body: text,
                sourceApp: source,
                sourceBundleID: bundleID,
                sourceKind: .clipboard
            )
        )
    }
}
#endif
