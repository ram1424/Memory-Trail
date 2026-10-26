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

        guard let rawTitle = focusedWindowTitle(pid: app.processIdentifier) else { return }

        let appName = app.localizedName ?? "Application"
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

        context?.insert(
            MemoryItem(
                title: title,
                body: detailedBody(for: title, applicationName: appName, bundleID: bundleID),
                sourceApp: appName,
                sourceBundleID: bundleID,
                sourceKind: .appActivity
            )
        )
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
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

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        if titleResult == .success, let title = titleValue as? String {
            let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        var documentValue: CFTypeRef?
        let documentResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXDocumentAttribute as CFString,
            &documentValue
        )

        if documentResult == .success, let document = documentValue as? String {
            return document.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
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
