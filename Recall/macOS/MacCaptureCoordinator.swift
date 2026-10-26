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

        context?.insert(
            MemoryItem(
                title: "Opened \(name)",
                body: bundleID,
                sourceApp: name,
                sourceBundleID: bundleID,
                sourceKind: .appActivity
            )
        )

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
        let rawContextTitle = preferredContextTitle(
            windowTitle: windowContext.title,
            focusedElementCandidates: windowContext.focusedElementCandidates,
            applicationName: appName,
            bundleID: bundleID
        )
        let title = normalizeWindowTitle(
            rawContextTitle,
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
            focusedElementCandidates: focusedElementCandidates(from: appElement)
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
        let focusedElementCandidates: [String]
    }

    private func focusedElementCandidates(from appElement: AXUIElement) -> [String] {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            return []
        }

        var element = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var candidates: [String] = []
        var visited = Set<String>()

        for _ in 0..<6 {
            for attribute in [
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDescriptionAttribute as CFString,
                kAXHelpAttribute as CFString
            ] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
                   let text = value as? String {
                    let cleaned = text
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard isUsefulAccessibilityText(cleaned) else { continue }
                    let key = cleaned.lowercased()
                    if visited.insert(key).inserted {
                        candidates.append(cleaned)
                    }
                }
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue,
            CFGetTypeID(parentValue) == AXUIElementGetTypeID()
            else {
                break
            }

            element = unsafeBitCast(parentValue, to: AXUIElement.self)
        }

        return candidates
    }

    private func isUsefulAccessibilityText(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.count <= 300 else { return false }

        let generic = Set([
            "button", "group", "scroll area", "split group", "toolbar",
            "table", "list", "web area", "text field", "static text",
            "mail", "microsoft outlook", "microsoft teams", "safari",
            "google chrome", "window"
        ])

        return !generic.contains(value.lowercased())
    }

    private func preferredContextTitle(
        windowTitle: String,
        focusedElementCandidates: [String],
        applicationName: String,
        bundleID: String
    ) -> String {
        let normalizedWindow = normalizeWindowTitle(
            windowTitle,
            applicationName: applicationName,
            bundleID: bundleID
        )

        let appSpecificGenericTerms: [String]
        switch bundleID.lowercased() {
        case "com.apple.mail":
            appSpecificGenericTerms = ["inbox", "all inboxes", "mail"]
        case "com.microsoft.outlook":
            appSpecificGenericTerms = ["mail", "inbox", "calendar", "microsoft outlook"]
        case "com.microsoft.teams2":
            appSpecificGenericTerms = ["chat", "activity", "teams", "microsoft teams"]
        default:
            appSpecificGenericTerms = []
        }

        for candidate in focusedElementCandidates {
            let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = cleaned.lowercased()

            if cleaned == normalizedWindow { continue }
            if cleaned == applicationName { continue }
            if appSpecificGenericTerms.contains(lower) { continue }

            return cleaned
        }

        return normalizedWindow.isEmpty ? windowTitle : normalizedWindow
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
