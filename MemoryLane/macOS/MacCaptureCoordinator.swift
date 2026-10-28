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
    private var mouseMonitor: Any?
    private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    private var lastWindowSignature = ""
    private var lastWindowLoggedAt = Date.distantPast
    private var enhancedAccessibilityPIDs: Set<pid_t> = []
    private weak var context: ModelContext?
    private var didRequestAccessibilityThisLaunch = false
    private(set) var accessibilityTrusted = AXIsProcessTrusted()

    private let fileAwareBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.preview",
        "com.microsoft.word",
        "com.microsoft.excel",
        "com.microsoft.powerpoint",
        "com.microsoft.onenote.mac",
        "com.microsoft.onenote"
    ]

    func start(context: ModelContext) {
        self.context = context
        requestAccessibilityPermissionIfNeeded()
        refreshAccessibilityStatus()
        startAppActivityCapture()
        startFocusedWindowCapture()
        startClickTargetCapture()
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

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
        enhancedAccessibilityPIDs.removeAll(keepingCapacity: true)
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

        enhancedAccessibilityPIDs.remove(application.processIdentifier)
        enableDetailedAccessibilityIfNeeded(for: application)

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

    private func enableDetailedAccessibilityIfNeeded(for application: NSRunningApplication) {
        let bundleID = (application.bundleIdentifier ?? "").lowercased()
        let shouldEnable =
            bundleID == "com.microsoft.outlook" ||
            bundleID == "com.microsoft.teams2" ||
            bundleID.contains("msteams") ||
            bundleID.contains("teams") ||
            bundleID.contains("electron") ||
            bundleID.contains("onenote")

        guard shouldEnable else { return }

        let pid = application.processIdentifier
        guard !enhancedAccessibilityPIDs.contains(pid) else { return }
        enhancedAccessibilityPIDs.insert(pid)

        let appElement = AXUIElementCreateApplication(pid)
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    private func startFocusedWindowCapture() {
        windowTimer?.invalidate()
        windowTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFocusedWindow()
            }
        }
    }

    private func startClickTargetCapture() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard AXIsProcessTrusted(), let point = event.cgEvent?.location else { return }

            Task { @MainActor in
                guard let self else { return }
                if let app = NSWorkspace.shared.frontmostApplication {
                    self.enableDetailedAccessibilityIfNeeded(for: app)
                }

                try? await Task.sleep(nanoseconds: 220_000_000)
                self.captureClickedContext(at: point)
            }
        }
    }

    private func captureClickedContext(at point: CGPoint) {
        let prefs = RecallPreferences.shared
        guard !prefs.capturePaused, prefs.captureAppActivity else { return }
        guard AXIsProcessTrusted() else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }

        let bundleID = app.bundleIdentifier ?? ""
        guard !prefs.isExcluded(bundleID: bundleID) else { return }
        guard bundleID != Bundle.main.bundleIdentifier else { return }

        enableDetailedAccessibilityIfNeeded(for: app)

        let lowerBundleID = bundleID.lowercased()

        if lowerBundleID == "com.microsoft.outlook" {
            captureOutlookSelectedSubject(application: app)
            return
        }

        if lowerBundleID == "com.apple.safari" || fileAwareBundleIDs.contains(lowerBundleID) {
            pollFocusedWindow()
            return
        }

        var hitElement: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard result == .success, let hitElement else { return }

        let activity: ActivityContext?
        if lowerBundleID == "com.microsoft.teams2" ||
            lowerBundleID.contains("msteams") ||
            lowerBundleID.contains("teams") ||
            lowerBundleID.contains("onenote") {
            activity = nearestRowOrSelectionContext(from: hitElement)
                ?? contextFromElementHierarchy(hitElement)
        } else {
            activity = contextFromElementHierarchy(hitElement)
        }

        guard let activity else { return }

        let appName = app.localizedName ?? "Application"
        let title = normalizedActivityTitle(
            activity.title,
            sourceURL: activity.sourceURL,
            applicationName: appName,
            bundleID: bundleID
        )

        guard !title.isEmpty, !isGenericWindowTitle(title, applicationName: appName) else { return }

        if bundleID.lowercased() == "com.microsoft.outlook",
           !isLikelyOutlookSubject(title) {
            return
        }

        logActivity(
            title: title,
            sourceURL: activity.sourceURL,
            applicationName: appName,
            bundleID: bundleID
        )
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

        enableDetailedAccessibilityIfNeeded(for: app)

        let appName = app.localizedName ?? "Application"
        let lowerBundleID = bundleID.lowercased()

        if lowerBundleID == "com.microsoft.outlook" {
            guard let subject = outlookSelectedSubject() else { return }
            logActivity(
                title: subject,
                sourceURL: nil,
                applicationName: appName,
                bundleID: bundleID
            )
            return
        }

        guard let windowContext = focusedWindowContext(
            pid: app.processIdentifier,
            bundleID: bundleID
        ) else { return }

        let activity = preferredActivityContext(windowContext: windowContext, bundleID: bundleID)
        let title = normalizedActivityTitle(
            activity.title,
            sourceURL: activity.sourceURL,
            applicationName: appName,
            bundleID: bundleID
        )

        guard !title.isEmpty, !isGenericWindowTitle(title, applicationName: appName) else { return }

        if bundleID.lowercased() == "com.microsoft.outlook",
           !isLikelyOutlookSubject(title) {
            return
        }

        logActivity(
            title: title,
            sourceURL: activity.sourceURL,
            applicationName: appName,
            bundleID: bundleID
        )
    }

    private func logActivity(
        title: String,
        sourceURL: String?,
        applicationName: String,
        bundleID: String
    ) {
        let signature = [
            bundleID.lowercased(),
            title.lowercased(),
            sourceURL?.lowercased() ?? ""
        ].joined(separator: "|")

        let now = Date()
        guard signature != lastWindowSignature else { return }
        guard now.timeIntervalSince(lastWindowLoggedAt) >= 0.6 else { return }

        lastWindowSignature = signature
        lastWindowLoggedAt = now

        guard let context else { return }

        context.insert(
            MemoryItem(
                title: title,
                body: detailedBody(
                    for: title,
                    applicationName: applicationName,
                    bundleID: bundleID,
                    sourceURL: sourceURL
                ),
                sourceApp: applicationName,
                sourceBundleID: bundleID,
                sourceKind: sourceKind(bundleID: bundleID, sourceURL: sourceURL),
                sourceURL: sourceURL
            )
        )
        try? context.save()
    }

    private func focusedWindowContext(pid: pid_t, bundleID: String) -> FocusedWindowContext? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let windowElement = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        let windowTitle = attributeString(windowElement, kAXTitleAttribute as CFString) ?? ""
        let document = attributeString(windowElement, kAXDocumentAttribute as CFString) ?? ""
        let windowURL = normalizedSourceURL(document) ?? attributeURL(windowElement)

        let lowerBundleID = bundleID.lowercased()
        let needsSelectionContext =
            lowerBundleID == "com.apple.mail" ||
            lowerBundleID == "com.microsoft.teams2" ||
            lowerBundleID.contains("msteams") ||
            lowerBundleID.contains("teams") ||
            lowerBundleID.contains("onenote")

        let selected = needsSelectionContext ? selectedContentContext(in: windowElement) : nil
        let focused = needsSelectionContext ? focusedContentContext(in: appElement) : nil
        let selectedTab = lowerBundleID == "com.apple.safari"
            ? selectedTabContext(in: windowElement)
            : nil

        let fallbackTitle = windowTitle.isEmpty ? document : windowTitle
        guard !fallbackTitle.isEmpty || selected != nil || focused != nil || selectedTab != nil else {
            return nil
        }

        return FocusedWindowContext(
            title: fallbackTitle,
            sourceURL: windowURL,
            selectedContent: selected,
            focusedContent: focused,
            selectedTab: selectedTab
        )
    }

    private struct ActivityContext {
        let title: String
        let sourceURL: String?
    }

    private struct FocusedWindowContext {
        let title: String
        let sourceURL: String?
        let selectedContent: ActivityContext?
        let focusedContent: ActivityContext?
        let selectedTab: ActivityContext?
    }

    private func preferredActivityContext(
        windowContext: FocusedWindowContext,
        bundleID: String
    ) -> ActivityContext {
        let lower = bundleID.lowercased()

        if lower == "com.apple.safari" {
            if let tab = windowContext.selectedTab,
               isMeaningfulInnerWindowTitle(tab.title) {
                return ActivityContext(
                    title: tab.title,
                    sourceURL: tab.sourceURL ?? windowContext.sourceURL
                )
            }
            return ActivityContext(title: windowContext.title, sourceURL: windowContext.sourceURL)
        }

        if lower == "com.microsoft.outlook" {
            if let subject = outlookSelectedSubject() {
                return ActivityContext(title: subject, sourceURL: nil)
            }

            let fallback = normalizeWindowTitle(
                windowContext.title,
                applicationName: "Microsoft Outlook",
                bundleID: bundleID
            )

            if isLikelyOutlookSubject(fallback) {
                return ActivityContext(title: fallback, sourceURL: windowContext.sourceURL)
            }

            return ActivityContext(title: "", sourceURL: nil)
        }

        if lower == "com.microsoft.teams2" ||
            lower.contains("msteams") ||
            lower.contains("teams") ||
            lower.contains("onenote") {
            if let selected = windowContext.selectedContent,
               isMeaningfulInnerWindowTitle(selected.title) {
                return ActivityContext(
                    title: selected.title,
                    sourceURL: selected.sourceURL ?? windowContext.sourceURL
                )
            }
            if let focused = windowContext.focusedContent,
               isMeaningfulInnerWindowTitle(focused.title) {
                return ActivityContext(
                    title: focused.title,
                    sourceURL: focused.sourceURL ?? windowContext.sourceURL
                )
            }
        }

        if let selected = windowContext.selectedContent,
           isMeaningfulInnerWindowTitle(selected.title),
           selected.title != windowContext.title {
            return ActivityContext(
                title: selected.title,
                sourceURL: selected.sourceURL ?? windowContext.sourceURL
            )
        }

        return ActivityContext(title: windowContext.title, sourceURL: windowContext.sourceURL)
    }

    private func captureOutlookSelectedSubject(application: NSRunningApplication) {
        guard let subject = outlookSelectedSubject() else { return }

        let appName = application.localizedName ?? "Microsoft Outlook"
        logActivity(
            title: subject,
            sourceURL: nil,
            applicationName: appName,
            bundleID: application.bundleIdentifier ?? "com.microsoft.outlook"
        )
    }

    private func outlookSelectedSubject() -> String? {
        let source = """
        tell application "Microsoft Outlook"
            try
                set selectedItems to selected objects
                if (count of selectedItems) is greater than 0 then
                    set theItem to item 1 of selectedItems
                    try
                        return subject of theItem as text
                    end try
                end if
            end try
        end tell
        return ""
        """

        guard let script = NSAppleScript(source: source) else { return nil }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil else { return nil }

        let subject = result.stringValue?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard isLikelyOutlookSubject(subject) else { return nil }
        return String(subject.prefix(250))
    }

    private func isLikelyOutlookSubject(_ value: String) -> Bool {
        let subject = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = subject.lowercased()

        guard subject.count >= 2, subject.count <= 250 else { return false }

        let exactGeneric = Set([
            "inbox",
            "mail",
            "calendar",
            "people",
            "contacts",
            "tasks",
            "microsoft outlook",
            "outlook"
        ])

        if exactGeneric.contains(lower) { return false }
        if lower.contains("unread message") && lower.hasPrefix("inbox") { return false }
        if lower.hasPrefix("from ") && lower.contains(" to ") && lower.contains(" events") { return false }
        if lower.contains("copyright ©") || lower.contains("all rights reserved") { return false }
        if lower.contains("one apple park way") { return false }

        // Accessibility rows often append Outlook UI metadata to a real subject.
        // The AppleScript path above returns only the subject, so reject those
        // composite strings instead of displaying a fake summarized title.
        if lower.contains("; has ") && lower.contains("attachment") { return false }
        if lower.contains("; sent by ") { return false }

        return true
    }

    private func selectedTabContext(in root: AXUIElement) -> ActivityContext? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 250 {
            let element = queue[index]
            index += 1
            inspected += 1

            var tabsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXTabsAttribute as CFString,
                &tabsValue
            ) == .success,
            let tabs = tabsValue as? [AXUIElement] {
                for tab in tabs where attributeBool(tab, kAXSelectedAttribute as CFString) == true {
                    if let context = bestContext(in: tab) {
                        return context
                    }
                }
            }

            appendChildren(of: element, to: &queue, limit: 60)
        }

        return selectedContentContext(in: root)
    }

    private func selectedContentContext(in root: AXUIElement) -> ActivityContext? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 350 {
            let element = queue[index]
            index += 1
            inspected += 1

            var selectedChildrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedChildrenAttribute as CFString,
                &selectedChildrenValue
            ) == .success,
            let selectedChildren = selectedChildrenValue as? [AXUIElement] {
                for selected in selectedChildren.prefix(5) {
                    if let context = bestContext(in: selected) {
                        return context
                    }
                }
            }

            if attributeBool(element, kAXSelectedAttribute as CFString) == true,
               let context = bestContext(in: element) {
                return context
            }

            appendChildren(of: element, to: &queue, limit: 80)
        }

        return nil
    }

    private func focusedContentContext(in appElement: AXUIElement) -> ActivityContext? {
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
        let role = attributeString(focused, kAXRoleAttribute as CFString)?.lowercased() ?? ""

        if role.contains("textfield") || role.contains("textarea") || role.contains("combobox") {
            return nil
        }

        return bestContext(in: focused)
    }

    private func nearestRowOrSelectionContext(from element: AXUIElement) -> ActivityContext? {
        var current: AXUIElement? = element
        var depth = 0

        while let element = current, depth < 10 {
            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            let selected = attributeBool(element, kAXSelectedAttribute as CFString) == true

            if selected || role.contains("row") || role.contains("cell") || role.contains("outline") || role.contains("list") {
                if let context = bestContext(in: element) {
                    return context
                }
            }

            current = parentElement(of: element)
            depth += 1
        }

        return nil
    }

    private func contextFromElementHierarchy(_ element: AXUIElement) -> ActivityContext? {
        var current: AXUIElement? = element
        var depth = 0
        var best: (context: ActivityContext, score: Int)?

        while let element = current, depth < 8 {
            if let context = bestContext(in: element) {
                let score = scoreContextText(context.title, sourceURL: context.sourceURL) - (depth * 12)
                if best == nil || score > best!.score {
                    best = (context, score)
                }
            }
            current = parentElement(of: element)
            depth += 1
        }

        return best?.context
    }

    private func parentElement(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func bestContext(in root: AXUIElement) -> ActivityContext? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var candidates: [(text: String, score: Int, url: String?)] = []

        while index < queue.count, index < 140 {
            let element = queue[index]
            index += 1
            let url = attributeURL(element)

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDescriptionAttribute as CFString
            ] {
                guard let text = attributeString(element, attribute) else { continue }
                let cleaned = text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if isMeaningfulInnerWindowTitle(cleaned) {
                    candidates.append((
                        text: cleaned,
                        score: scoreContextText(cleaned, sourceURL: url),
                        url: url
                    ))
                }
            }

            appendChildren(of: element, to: &queue, limit: 50)
        }

        guard let best = candidates.max(by: { $0.score < $1.score }) else {
            if let url = attributeURL(root) {
                return ActivityContext(title: urlDisplayTitle(url), sourceURL: url)
            }
            return nil
        }

        return ActivityContext(title: best.text, sourceURL: best.url)
    }

    private func appendChildren(of element: AXUIElement, to queue: inout [AXUIElement], limit: Int) {
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] {
            queue.append(contentsOf: children.prefix(limit))
        }
    }

    private func attributeString(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else { return nil }

        if let string = value as? String {
            let cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }

        if let url = value as? URL {
            return url.absoluteString
        }

        return nil
    }

    private func attributeBool(_ element: AXUIElement, _ attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let value
        else { return nil }

        return value as? Bool
    }

    private func attributeURL(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXURLAttribute as CFString,
            &value
        ) == .success,
        let value {
            if let url = value as? URL {
                return normalizedSourceURL(url.absoluteString)
            }
            if let string = value as? String {
                return normalizedSourceURL(string)
            }
        }

        if let document = attributeString(element, kAXDocumentAttribute as CFString) {
            return normalizedSourceURL(document)
        }

        return nil
    }

    private func normalizedSourceURL(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if cleaned.hasPrefix("/") || cleaned.hasPrefix("~/") {
            let path = (cleaned as NSString).expandingTildeInPath
            return URL(fileURLWithPath: path).absoluteString
        }

        guard let url = URL(string: cleaned) else { return nil }

        switch url.scheme?.lowercased() {
        case "http", "https", "file", "mailto", "message", "msteams", "ms-outlook", "outlook":
            return url.absoluteString
        default:
            return nil
        }
    }

    private func normalizedActivityTitle(
        _ rawTitle: String,
        sourceURL: String?,
        applicationName: String,
        bundleID: String
    ) -> String {
        let lower = bundleID.lowercased()

        if fileAwareBundleIDs.contains(lower),
           let sourceURL,
           let url = URL(string: sourceURL),
           url.isFileURL {
            let filename = url.lastPathComponent
            if !filename.isEmpty && filename != "/" {
                return filename
            }
        }

        return normalizeWindowTitle(rawTitle, applicationName: applicationName, bundleID: bundleID)
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
            " - Microsoft Outlook", " — Microsoft Outlook",
            " | Microsoft Teams", " - Microsoft Teams", " — Microsoft Teams",
            " - Safari", " — Safari",
            " - Mail", " — Mail",
            " - Google Chrome", " — Google Chrome",
            " - Microsoft Word", " — Microsoft Word",
            " - Microsoft Excel", " — Microsoft Excel",
            " - Microsoft PowerPoint", " — Microsoft PowerPoint",
            " - OneNote", " — OneNote",
            " - Preview", " — Preview"
        ]

        for suffix in suffixes where title.hasSuffix(suffix) {
            title.removeLast(suffix.count)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if title == applicationName { return "" }
        if bundleID.lowercased() == "com.apple.mail", title.lowercased() == "mail" { return "" }

        return String(title.prefix(250))
    }

    private func sourceKind(bundleID: String, sourceURL: String?) -> SourceKind {
        if let sourceURL,
           let url = URL(string: sourceURL),
           url.isFileURL {
            return .file
        }

        return fileAwareBundleIDs.contains(bundleID.lowercased()) ? .file : .appActivity
    }

    private func detailedBody(
        for title: String,
        applicationName: String,
        bundleID: String,
        sourceURL: String?
    ) -> String {
        let lower = bundleID.lowercased()

        if let sourceURL,
           let url = URL(string: sourceURL),
           url.isFileURL {
            let path = url.path(percentEncoded: false)
            switch lower {
            case "com.apple.finder":
                return "Finder location viewed: \(title) — \(path)"
            case "com.microsoft.word":
                return "Word document viewed: \(title) — \(path)"
            case "com.microsoft.excel":
                return "Excel workbook viewed: \(title) — \(path)"
            case "com.microsoft.powerpoint":
                return "PowerPoint presentation viewed: \(title) — \(path)"
            case "com.apple.preview":
                return "Preview file viewed: \(title) — \(path)"
            default:
                return "File viewed in \(applicationName): \(title) — \(path)"
            }
        }

        switch lower {
        case "com.apple.mail":
            return "Mail item viewed: \(title)"
        case "com.microsoft.outlook":
            return "Outlook item viewed: \(title)"
        case "com.microsoft.teams2":
            return "Teams conversation viewed: \(title)"
        case "com.microsoft.onenote.mac", "com.microsoft.onenote":
            return "OneNote page viewed: \(title)"
        case "com.apple.safari":
            return sourceURL.map { "Safari page viewed: \(title) — \($0)" } ?? "Safari page viewed: \(title)"
        case "com.google.chrome":
            return sourceURL.map { "Chrome page viewed: \(title) — \($0)" } ?? "Chrome page viewed: \(title)"
        default:
            return "Focused window in \(applicationName): \(title)"
        }
    }

    private func urlDisplayTitle(_ value: String) -> String {
        guard let url = URL(string: value) else { return value }
        if url.isFileURL {
            return url.lastPathComponent
        }
        return url.host(percentEncoded: false) ?? value
    }

    private func scoreContextText(_ text: String, sourceURL: String?) -> Int {
        let lower = text.lowercased()
        var score = min(text.count, 120)

        if text.contains(" ") { score += 30 }
        if text.count >= 8 && text.count <= 140 { score += 30 }
        if sourceURL != nil { score += 60 }
        if lower.contains("re:") || lower.contains("fw:") || lower.contains("fwd:") { score += 50 }
        if lower.contains(".doc") || lower.contains(".xlsx") || lower.contains(".ppt") || lower.contains(".pdf") { score += 45 }
        if lower.contains("today") || lower.contains("yesterday") { score -= 20 }
        if ["inbox", "mail", "focused", "other"].contains(lower) { score -= 120 }

        return score
    }

    private func isMeaningfulInnerWindowTitle(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.count <= 250 else { return false }

        let generic = Set([
            "button", "group", "table", "list", "row", "scroll area",
            "split group", "toolbar", "mail", "inbox", "focused", "other",
            "microsoft outlook", "microsoft teams", "teams", "safari", "window",
            "tab group", "web area", "main", "finder", "preview"
        ])

        return !generic.contains(value.lowercased())
    }

    private func isGenericWindowTitle(_ title: String, applicationName: String) -> Bool {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "",
            applicationName.lowercased(),
            "new tab",
            "start page",
            "untitled",
            "home",
            "settings",
            "preferences"
        ].contains(value)
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
