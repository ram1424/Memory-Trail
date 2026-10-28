#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MacCaptureCoordinator {
    static let shared = MacCaptureCoordinator()

    private var appObserver: NSObjectProtocol?
    private var clipboardTimer: Timer?
    private var windowTimer: Timer?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var lastWindowSignature = ""
    private var lastWindowLoggedAt = Date.distantPast
    private weak var context: ModelContext?
    private var didRequestAccessibilityThisLaunch = false
    private(set) var accessibilityTrusted = AXIsProcessTrusted()

    func start(context: ModelContext) {
        self.context = context
        refreshAccessibilityStatus()

        startAppActivityCapture()
        startFocusedWindowCapture()
        startClipboardCapture()
    }

    func ensureAccessibilityAccessOnLaunch() async {
        refreshAccessibilityStatus()
        guard !accessibilityTrusted else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        requestAccessibilityPermissionIfNeeded()

        try? await Task.sleep(nanoseconds: 900_000_000)
        refreshAccessibilityStatus()

        guard !accessibilityTrusted else { return }

        // macOS owns the Privacy & Security authorization switch. If access was
        // not granted from the system prompt, take the user directly to the
        // Accessibility pane where Memory Lane can be enabled.
        openAccessibilitySettings()
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

        NSApplication.shared.activate(ignoringOtherApps: true)
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityStatus()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !didRequestAccessibilityThisLaunch else { return }
        didRequestAccessibilityThisLaunch = true

        guard !AXIsProcessTrusted() else { return }
        requestAccessibilityPermission()
    }

    var hasAccessibilityPermission: Bool {
        accessibilityTrusted
    }

    func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        if trusted && !accessibilityTrusted {
            lastWindowSignature = ""
            lastWindowLoggedAt = .distantPast
        }
        accessibilityTrusted = trusted
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func clearRuntimeCache() {
        lastWindowSignature = ""
        lastWindowLoggedAt = .distantPast
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        didRequestAccessibilityThisLaunch = false
        accessibilityTrusted = AXIsProcessTrusted()

        if !accessibilityTrusted {
            requestAccessibilityPermissionIfNeeded()
        }
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

        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted {
            if trusted {
                lastWindowSignature = ""
                lastWindowLoggedAt = .distantPast
            }
            accessibilityTrusted = trusted
        }

        guard trusted else {
            requestAccessibilityPermissionIfNeeded()
            return
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let bundleID = app.bundleIdentifier ?? ""
        guard !prefs.isExcluded(bundleID: bundleID) else { return }
        guard bundleID != Bundle.main.bundleIdentifier else { return }

        guard let windowContext = focusedWindowContext(pid: app.processIdentifier) else { return }

        let appName = app.localizedName ?? "Application"
        let title = normalizeWindowTitle(
            windowContext.title,
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
            sourceURL: normalizedSourceURL(document)
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

        if let context {
            context.insert(
                MemoryItem(
                    title: String(preview.prefix(90)),
                    body: text,
                    sourceApp: source,
                    sourceBundleID: bundleID,
                    sourceKind: .clipboard
                )
            )
            try? context.save()
        }
    }
}
#endif
