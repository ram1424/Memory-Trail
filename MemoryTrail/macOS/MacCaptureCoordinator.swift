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

    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored private var clipboardTimer: Timer?
    @ObservationIgnored private var windowTimer: Timer?
    @ObservationIgnored private var mouseMonitor: Any?
    @ObservationIgnored private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var lastWindowSignature = ""
    @ObservationIgnored private var lastWindowLoggedAt = Date.distantPast
    @ObservationIgnored private var lastExpensiveWindowPollAt = Date.distantPast
    @ObservationIgnored private var enhancedAccessibilityPIDs: Set<pid_t> = []
    @ObservationIgnored private var teamsGroupExpansionCache: [String: TeamsGroupExpansionCacheEntry] = [:]
    @ObservationIgnored private weak var context: ModelContext?
    @ObservationIgnored private var didRequestAccessibilityThisLaunch = false
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
        guard trusted != accessibilityTrusted else { return }

        if trusted {
            lastWindowSignature = ""
            lastWindowLoggedAt = .distantPast
            lastExpensiveWindowPollAt = .distantPast
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
        lastExpensiveWindowPollAt = .distantPast
        teamsGroupExpansionCache.removeAll(keepingCapacity: true)
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
        lastExpensiveWindowPollAt = .distantPast
        teamsGroupExpansionCache.removeAll(keepingCapacity: true)

        let name = application.localizedName ?? "Application"
        let lowerBundleID = bundleID.lowercased()

        if lowerBundleID == "com.microsoft.outlook" ||
            isChatBundleID(lowerBundleID) ||
            lowerBundleID.contains("onenote") {
            // Let complex app UIs settle, then read the selected item rather
            // than logging only the application/window name.
            lastWindowSignature = ""
            lastWindowLoggedAt = .distantPast

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.pollFocusedWindow(forceExpensiveApps: true)
            }
            return
        }

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

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.pollFocusedWindow(forceExpensiveApps: true)
        }
    }

    private func enableDetailedAccessibilityIfNeeded(for application: NSRunningApplication) {
        let bundleID = (application.bundleIdentifier ?? "").lowercased()
        let shouldEnable =
            bundleID == "com.microsoft.outlook" ||
            isChatBundleID(bundleID) ||
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

        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFocusedWindow()
            }
        }
        timer.tolerance = 0.60
        windowTimer = timer
    }

    private func startClickTargetCapture() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            guard AXIsProcessTrusted(), let point = event.cgEvent?.location else { return }

            Task { @MainActor in
                guard let self,
                      let app = NSWorkspace.shared.frontmostApplication
                else {
                    return
                }

                let bundleID = app.bundleIdentifier ?? ""
                guard bundleID != Bundle.main.bundleIdentifier else {
                    return
                }

                self.enableDetailedAccessibilityIfNeeded(for: app)

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

        var hitElement: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        let result = AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        if lowerBundleID == "com.microsoft.outlook" {
            if result == .success,
               let hitElement,
               let subject = outlookSubjectFromClickedElement(hitElement) {
                let sender = outlookSenderFromElement(hitElement)
                    ?? outlookSelectedSender(pid: app.processIdentifier)
                logActivity(
                    title: subject,
                    sourceURL: nil,
                    applicationName: app.localizedName ?? "Microsoft Outlook",
                    bundleID: bundleID,
                    baseDetail: sender.map { "From: \($0)" }
                )
                return
            }

            // If the actual clicked Outlook element is not an email row,
            // do not infer activity from whatever message happens to be selected.
            return
        }

        if isTeamsBundleID(lowerBundleID) {
            var conversation: String?

            // Use the clicked chat row first, matching the older working path.
            if result == .success,
               let hitElement,
               let row = nearestAccessibilityRow(from: hitElement),
               let parsed = teamsNameFromSelectedElement(row) {
                conversation = parsed.name
            }

            // New Teams does not always expose the clicked row consistently,
            // so fall back to the selected conversation or focused window title.
            if conversation == nil {
                conversation = teamsSelectedConversationTitle(pid: app.processIdentifier)
                    ?? teamsConversationTitleFromFocusedWindow(pid: app.processIdentifier)
            }

            guard let conversation else { return }

            let expandedConversation = expandedTeamsGroupConversationTitle(
                conversation,
                pid: app.processIdentifier
            )

            logActivity(
                title: expandedConversation,
                sourceURL: nil,
                applicationName: app.localizedName ?? "Microsoft Teams",
                bundleID: bundleID
            )
            return
        }

        if isChatBundleID(lowerBundleID) {
            var conversation: String?

            if result == .success, let hitElement {
                conversation = genericChatConversationFromClickedElement(
                    hitElement,
                    applicationName: app.localizedName ?? "Chat"
                )
            }

            if conversation == nil {
                conversation = genericChatConversationTitle(
                    pid: app.processIdentifier,
                    bundleID: bundleID,
                    applicationName: app.localizedName ?? "Chat"
                )
            }

            guard let conversation else { return }

            logActivity(
                title: conversation,
                sourceURL: nil,
                applicationName: app.localizedName ?? "Chat",
                bundleID: bundleID
            )
            return
        }

        if lowerBundleID.contains("onenote") {
            if result == .success,
               let hitElement,
               let hierarchy = oneNoteHierarchyFromClickedElement(
                    hitElement,
                    pid: app.processIdentifier
               ),
               !hierarchy.displayTitle.isEmpty {
                logActivity(
                    title: hierarchy.displayTitle,
                    sourceURL: nil,
                    applicationName: app.localizedName ?? "Microsoft OneNote",
                    bundleID: bundleID
                )
                return
            }

            if let hierarchy = oneNoteSelectedHierarchy(pid: app.processIdentifier),
               !hierarchy.displayTitle.isEmpty {
                logActivity(
                    title: hierarchy.displayTitle,
                    sourceURL: nil,
                    applicationName: app.localizedName ?? "Microsoft OneNote",
                    bundleID: bundleID
                )
                return
            }

            pollFocusedWindow(forceExpensiveApps: true)
            return
        }

        if lowerBundleID == "com.apple.safari" ||
            fileAwareBundleIDs.contains(lowerBundleID) {
            pollFocusedWindow()
            return
        }

        guard result == .success, let hitElement else { return }

        let activity = contextFromElementHierarchy(hitElement)

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

    private func pollFocusedWindow(forceExpensiveApps: Bool = false) {
        let prefs = RecallPreferences.shared
        guard !prefs.capturePaused, prefs.captureAppActivity else { return }

        let trusted = AXIsProcessTrusted()
        if trusted != accessibilityTrusted {
            if trusted {
                lastWindowSignature = ""
                lastWindowLoggedAt = .distantPast
                lastExpensiveWindowPollAt = .distantPast
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

        let isExpensiveAccessibilityApp =
            lowerBundleID == "com.microsoft.outlook" ||
            isChatBundleID(lowerBundleID) ||
            lowerBundleID.contains("onenote")

        if isExpensiveAccessibilityApp && !forceExpensiveApps {
            let now = Date()
            guard now.timeIntervalSince(lastExpensiveWindowPollAt) >= 9.0 else {
                return
            }
            lastExpensiveWindowPollAt = now
        } else if isExpensiveAccessibilityApp {
            lastExpensiveWindowPollAt = Date()
        }

        if lowerBundleID == "com.microsoft.outlook" {
            guard let subject = outlookSelectedSubject(pid: app.processIdentifier) else { return }
            let sender = outlookSelectedSender(pid: app.processIdentifier)
            logActivity(
                title: subject,
                sourceURL: nil,
                applicationName: appName,
                bundleID: bundleID,
                baseDetail: sender.map { "From: \($0)" }
            )
            return
        }

        if isTeamsBundleID(lowerBundleID) {
            guard let conversation = teamsSelectedConversationTitle(pid: app.processIdentifier)
                ?? teamsConversationTitleFromFocusedWindow(pid: app.processIdentifier)
            else {
                return
            }

            logActivity(
                title: conversation,
                sourceURL: nil,
                applicationName: appName,
                bundleID: bundleID
            )
            return
        }

        if isChatBundleID(lowerBundleID),
           let conversation = genericChatConversationTitle(
                pid: app.processIdentifier,
                bundleID: bundleID,
                applicationName: appName
           ) {
            logActivity(
                title: conversation,
                sourceURL: nil,
                applicationName: appName,
                bundleID: bundleID
            )
            return
        }

        if lowerBundleID.contains("onenote"),
           let hierarchy = oneNoteSelectedHierarchy(pid: app.processIdentifier),
           !hierarchy.displayTitle.isEmpty {
            logActivity(
                title: hierarchy.displayTitle,
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
        bundleID: String,
        baseDetail: String? = nil
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

        let lowerBundleID = bundleID.lowercased()
        let storedBody: String

        if lowerBundleID == "com.microsoft.outlook" {
            storedBody = baseDetail ?? ""
        } else if isTeamsBundleID(lowerBundleID) {
            storedBody = ""
        } else {
            // App activity is intentionally minimal: title + app identity +
            // optional source URL/path are enough to retrace the work.
            storedBody = ""
        }

        context.insert(
            MemoryItem(
                title: title,
                body: storedBody,
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
            isChatBundleID(lowerBundleID) ||
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
            return ActivityContext(title: "", sourceURL: nil)
        }

        if isTeamsBundleID(lower) {
            if let conversation = teamsConversationTitle(from: windowContext.title) {
                return ActivityContext(title: conversation, sourceURL: nil)
            }
            return ActivityContext(title: "", sourceURL: nil)
        }

        if lower.contains("onenote") {
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
        guard let subject = outlookSelectedSubject(pid: application.processIdentifier) else { return }

        let sender = outlookSelectedSender(pid: application.processIdentifier)
        let appName = application.localizedName ?? "Microsoft Outlook"
        logActivity(
            title: subject,
            sourceURL: nil,
            applicationName: appName,
            bundleID: application.bundleIdentifier ?? "com.microsoft.outlook",
            baseDetail: sender.map { "From: \($0)" }
        )
    }

    private func outlookSelectedSubject(pid: pid_t) -> String? {
        if let subject = outlookSelectedSubjectFromAccessibility(pid: pid) {
            return subject
        }

        // AppleScript is substantially more expensive and synchronous, so use
        // it only when Outlook does not expose the selected message through AX.
        return outlookSelectedSubjectFromAppleScript()
    }

    private func outlookSelectedSubjectFromAppleScript() -> String? {
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

        return sanitizedOutlookSubject(result.stringValue ?? "")
    }

    private func outlookSelectedSender(pid: pid_t) -> String? {
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

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)

        for selected in selectedAccessibilityRows(in: window) {
            if let sender = outlookSenderFromElement(selected) {
                return sender
            }
        }

        if let focused = focusedAccessibilityElement(in: appElement),
           let row = nearestAccessibilityRow(from: focused),
           let sender = outlookSenderFromElement(row) {
            return sender
        }

        // Preserve the proven AppleScript path as a fallback only.
        return outlookSelectedSenderFromAppleScript()
    }

    private func outlookSelectedSenderFromAppleScript() -> String? {
        let source = """
        tell application "Microsoft Outlook"
            try
                set selectedItems to selected objects
                if (count of selectedItems) is greater than 0 then
                    set theItem to item 1 of selectedItems
                    try
                        set senderValue to sender of theItem
                        try
                            return name of senderValue as text
                        end try
                        return senderValue as text
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

        return sanitizedOutlookSender(result.stringValue ?? "")
    }

    private func outlookSenderFromElement(_ root: AXUIElement) -> String? {
        var current: AXUIElement? = root
        var depth = 0

        while let element = current, depth < 10 {
            for attribute in [
                kAXDescriptionAttribute as CFString,
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString
            ] {
                if let raw = attributeString(element, attribute),
                   let sender = parseOutlookSender(from: raw) {
                    return sender
                }
            }

            var queue: [AXUIElement] = [element]
            var index = 0
            var inspected = 0

            while index < queue.count, inspected < 45 {
                let child = queue[index]
                index += 1
                inspected += 1

                for attribute in [
                    kAXDescriptionAttribute as CFString,
                    kAXTitleAttribute as CFString,
                    kAXValueAttribute as CFString
                ] {
                    if let raw = attributeString(child, attribute),
                       let sender = parseOutlookSender(from: raw) {
                        return sender
                    }
                }

                appendChildren(of: child, to: &queue, limit: 18)
            }

            current = parentElement(of: element)
            depth += 1
        }

        return nil
    }

    private func parseOutlookSender(from rawValue: String) -> String? {
        let normalized = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = normalized.lowercased()
        let markers = [", sent by ", "; sent by ", " sent by "]

        guard let marker = markers.first(where: { lower.contains($0) }),
              let range = lower.range(of: marker)
        else {
            return nil
        }

        var sender = String(normalized[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let terminators = [
            " today", " yesterday", " monday", " tuesday", " wednesday",
            " thursday", " friday", " saturday", " sunday",
            "; has ", ", has ", " at ", "; received ", ", received "
        ]

        let lowerSender = sender.lowercased()
        if let end = terminators.compactMap({ lowerSender.range(of: $0)?.lowerBound }).min() {
            sender = String(sender[..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sanitizedOutlookSender(sender)
    }

    private func sanitizedOutlookSender(_ rawValue: String) -> String? {
        let sender = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard sender.count >= 2, sender.count <= 120 else { return nil }
        guard !looksLikeURL(sender), !looksLikeTimestampOrDate(sender) else { return nil }

        let lower = sender.lowercased()
        let generic = Set([
            "microsoft outlook", "outlook", "inbox", "mail",
            "sender", "from", "unknown"
        ])
        guard !generic.contains(lower) else { return nil }

        return sender
    }

    private func outlookSelectedSubjectFromAccessibility(pid: pid_t) -> String? {
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

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)

        if let subject = outlookSelectedMessageSubject(in: window) {
            return subject
        }

        if let focused = focusedAccessibilityElement(in: appElement),
           let row = nearestAccessibilityRow(from: focused),
           let subject = outlookSubjectFromSelectedElement(row, requireStrongSignal: false) {
            return subject
        }

        // When a message is opened in its own window, Outlook commonly exposes
        // the message subject as the focused window title.
        if let windowTitle = attributeString(window, kAXTitleAttribute as CFString),
           let subject = sanitizedOutlookSubject(windowTitle) {
            return subject
        }

        return nil
    }

    private func outlookSubjectFromClickedElement(_ element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current, depth < 12 {
            let role = attributeString(candidate, kAXRoleAttribute as CFString)?.lowercased() ?? ""

            if role.contains("row") ||
                role.contains("cell") ||
                role.contains("outline") ||
                role.contains("list") ||
                role.contains("group") {
                if let subject = outlookSubjectFromSelectedElement(candidate, requireStrongSignal: true) {
                    return subject
                }
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return nil
    }

    private func outlookSelectedMessageSubject(in root: AXUIElement) -> String? {
        for selected in selectedAccessibilityRows(in: root) {
            if let subject = outlookSubjectFromSelectedElement(selected, requireStrongSignal: false) {
                return subject
            }
        }

        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 450 {
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
                for selected in selectedChildren.prefix(8) {
                    if let subject = outlookSubjectFromSelectedElement(selected, requireStrongSignal: false) {
                        return subject
                    }
                }
            }

            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            if attributeBool(element, kAXSelectedAttribute as CFString) == true,
               (role.contains("row") || role.contains("cell") || role.contains("outline") || role.contains("list")) {
                if let subject = outlookSubjectFromSelectedElement(element, requireStrongSignal: false) {
                    return subject
                }
            }

            appendChildren(of: element, to: &queue, limit: 80)
        }

        return nil
    }

    private func outlookSubjectFromSelectedElement(
        _ root: AXUIElement,
        requireStrongSignal: Bool
    ) -> String? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0
        var candidates: [(subject: String, score: Int, strong: Bool)] = []

        while index < queue.count, inspected < 100 {
            let element = queue[index]
            index += 1
            inspected += 1

            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""

            for (attribute, baseScore) in [
                (kAXDescriptionAttribute as CFString, 100),
                (kAXTitleAttribute as CFString, 85),
                (kAXValueAttribute as CFString, 35)
            ] {
                guard let raw = attributeString(element, attribute) else { continue }
                guard let subject = sanitizedOutlookSubject(raw) else { continue }

                let lowerRaw = raw.lowercased()
                let compositeSignal =
                    lowerRaw.contains(", sent by ") ||
                    lowerRaw.contains("; sent by ") ||
                    (lowerRaw.contains("attachment") && lowerRaw.contains("today")) ||
                    (lowerRaw.contains("attachment") && lowerRaw.contains("yesterday"))

                var score = baseScore
                if compositeSignal { score += 220 }
                if role.contains("row") || role.contains("cell") { score += 35 }
                if subject.count >= 5 && subject.count <= 180 { score += 20 }
                if subject.contains(":") || subject.contains("-") { score += 8 }

                // Sender names, dates, and tiny UI labels should not outrank a subject.
                if looksLikePersonName(subject) && !compositeSignal { score -= 80 }
                if looksLikeTimestampOrDate(subject) { score -= 160 }
                if subject.count < 4 { score -= 100 }

                candidates.append((subject, score, compositeSignal))
            }

            appendChildren(of: element, to: &queue, limit: 30)
        }

        let eligible: [(subject: String, score: Int, strong: Bool)]
        if requireStrongSignal {
            eligible = candidates.filter { $0.strong || $0.score >= 145 }
        } else {
            eligible = candidates.filter { candidate in
                candidate.score >= 75 &&
                    !looksLikeURL(candidate.subject) &&
                    !looksLikeTimestampOrDate(candidate.subject)
            }
        }

        return eligible.max(by: { $0.score < $1.score })?.subject
    }

    private func sanitizedOutlookSubject(_ rawValue: String) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let initialLower = value.lowercased()
        if initialLower.hasPrefix("http://") ||
            initialLower.hasPrefix("https://") ||
            initialLower.hasPrefix("mailto:") ||
            initialLower.hasPrefix("outlook://") ||
            initialLower.hasPrefix("ms-outlook://") ||
            initialLower.contains("urldefense.com/") ||
            initialLower.contains("safelinks.protection.outlook.com/") {
            return nil
        }

        if let range = value.range(of: ", sent by ", options: .caseInsensitive) {
            value = String(value[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let range = value.range(of: "; sent by ", options: .caseInsensitive) {
            value = String(value[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard isLikelyOutlookSubject(value) else { return nil }
        return String(value.prefix(250))
    }

    private func isTeamsBundleID(_ lowerBundleID: String) -> Bool {
        lowerBundleID == "com.microsoft.teams2" ||
            lowerBundleID.contains("msteams") ||
            lowerBundleID.contains("teams")
    }

    private func isChatBundleID(_ lowerBundleID: String) -> Bool {
        if isTeamsBundleID(lowerBundleID) {
            return true
        }

        let chatBundleFragments = [
            "slack",
            "discord",
            "zoom",
            "webex",
            "signal",
            "whatsapp",
            "telegram",
            "mattermost",
            "googlechat",
            "google.chat",
            "com.apple.ichat",
            "com.apple.messages"
        ]

        return chatBundleFragments.contains { lowerBundleID.contains($0) }
    }

    private func genericChatConversationTitle(
        pid: pid_t,
        bundleID: String,
        applicationName: String
    ) -> String? {
        guard let windowContext = focusedWindowContext(pid: pid, bundleID: bundleID) else {
            return nil
        }

        let candidates = [
            windowContext.selectedContent?.title,
            windowContext.focusedContent?.title,
            windowContext.title
        ].compactMap { $0 }

        for candidate in candidates {
            if let title = sanitizedGenericChatTitle(
                candidate,
                applicationName: applicationName
            ) {
                return title
            }
        }

        return nil
    }

    private func genericChatConversationFromClickedElement(
        _ element: AXUIElement,
        applicationName: String
    ) -> String? {
        var current: AXUIElement? = element
        var depth = 0
        var candidates: [(title: String, score: Int)] = []

        while let candidate = current, depth < 12 {
            let role = attributeString(candidate, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            let isConversationContainer =
                role.contains("row") ||
                role.contains("cell") ||
                role.contains("group") ||
                role.contains("outline") ||
                role.contains("link")

            if isConversationContainer {
                for (attribute, baseScore) in [
                    (kAXTitleAttribute as CFString, 150),
                    (kAXDescriptionAttribute as CFString, 125),
                    (kAXValueAttribute as CFString, 90)
                ] {
                    if let raw = attributeString(candidate, attribute),
                       let title = sanitizedGenericChatTitle(
                            raw,
                            applicationName: applicationName
                       ) {
                        candidates.append((title, baseScore - depth * 6))
                    }
                }
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return candidates.max(by: { $0.score < $1.score })?.title
    }

    private func sanitizedGenericChatTitle(
        _ rawValue: String,
        applicationName: String
    ) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard value.count >= 2, value.count <= 180 else { return nil }

        let appLower = applicationName.lowercased()
        var lower = value.lowercased()

        let suffixes = [
            " | \(applicationName)",
            " - \(applicationName)",
            " — \(applicationName)"
        ]

        for suffix in suffixes where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            lower = value.lowercased()
        }

        let generic = Set([
            "",
            appLower,
            "chat",
            "chats",
            "messages",
            "message",
            "activity",
            "home",
            "search",
            "settings",
            "preferences",
            "new message",
            "new chat",
            "compose",
            "threads",
            "mentions & reactions",
            "later",
            "canvas",
            "huddles",
            "more",
            "direct messages",
            "channels"
        ])

        guard !generic.contains(lower) else { return nil }
        guard !lower.contains("type a message"),
              !lower.contains("send a message"),
              !lower.contains("message field"),
              !lower.contains("search messages")
        else {
            return nil
        }

        if value.hasPrefix("#") {
            return value
        }

        // Slack commonly exposes "channel | workspace" or "person | workspace".
        // Keep the conversation identity and drop the workspace/app suffix.
        let parts = value
            .components(separatedBy: " | ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if parts.count >= 2,
           let first = parts.first,
           !generic.contains(first.lowercased()) {
            return first
        }

        return String(value.prefix(180))
    }

    private func teamsConversationFromClickedElement(_ element: AXUIElement) -> String? {
        var current: AXUIElement? = element
        var depth = 0
        var strongCandidates: [(name: String, score: Int)] = []
        var contextualCandidates: [(name: String, score: Int)] = []

        while let candidate = current, depth < 16 {
            // First inspect the ancestor itself plus a small number of direct
            // children. This is where New Teams often exposes labels such as
            // "Group chat Ashar" even when the AX role is only AXGroup.
            var elements: [(element: AXUIElement, childDepth: Int)] = [(candidate, 0)]

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                candidate,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                for child in children.prefix(16) {
                    elements.append((child, 1))
                }
            }

            let containerScore = teamsConversationContainerScore(candidate)

            for entry in elements {
                let role = attributeString(
                    entry.element,
                    kAXRoleAttribute as CFString
                )?.lowercased() ?? ""

                for (attribute, baseScore) in [
                    (kAXTitleAttribute as CFString, 150),
                    (kAXDescriptionAttribute as CFString, 135),
                    ("AXHelp" as CFString, 100),
                    (kAXValueAttribute as CFString, 55)
                ] {
                    guard let raw = attributeString(entry.element, attribute) else { continue }
                    guard !isGenericTeamsUIValue(raw) else { continue }
                    guard let parsed = parsedTeamsConversationCandidate(raw) else { continue }

                    var score = baseScore
                    score -= depth * 5
                    score -= entry.childDepth * 8

                    if parsed.directConversationSignal {
                        score += 300
                        strongCandidates.append((parsed.name, score))
                        continue
                    }

                    if parsed.strongSignal {
                        score += 220
                        strongCandidates.append((parsed.name, score))
                        continue
                    }

                    // Bare names are accepted only when the ancestor itself
                    // looks like an actual Teams chat/conversation container.
                    if containerScore > 0 {
                        var contextualScore = score + min(containerScore, 120)
                        if role.contains("row") ||
                            role.contains("cell") ||
                            role.contains("list") ||
                            role.contains("group") {
                            contextualScore += 20
                        }
                        contextualCandidates.append((parsed.name, contextualScore))
                    }
                }
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        if let bestStrong = strongCandidates.max(by: { $0.score < $1.score }) {
            return bestStrong.name
        }

        return contextualCandidates
            .filter { $0.score >= 185 }
            .max(by: { $0.score < $1.score })?
            .name
    }

    private func teamsConversationHeaderTitle(pid: pid_t) -> String? {
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

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var index = 0
        var inspected = 0
        var candidates: [(name: String, score: Int)] = []

        while index < queue.count, inspected < 360 {
            let entry = queue[index]
            index += 1
            inspected += 1

            let element = entry.element
            let depth = entry.depth

            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            let roleDescription = attributeString(element, kAXRoleDescriptionAttribute as CFString)?.lowercased() ?? ""
            let identifier = attributeString(element, kAXIdentifierAttribute as CFString)?.lowercased() ?? ""

            let headerSemantic =
                role.contains("heading") ||
                roleDescription.contains("heading") ||
                identifier.contains("chat-title") ||
                identifier.contains("chat_title") ||
                identifier.contains("conversation-title") ||
                identifier.contains("conversation_title") ||
                identifier.contains("chat-header") ||
                identifier.contains("chat_header") ||
                identifier.contains("conversation-header") ||
                identifier.contains("conversation_header")

            if headerSemantic {
                for (attribute, baseScore) in [
                    (kAXTitleAttribute as CFString, 180),
                    (kAXDescriptionAttribute as CFString, 150),
                    (kAXValueAttribute as CFString, 90)
                ] {
                    guard let raw = attributeString(element, attribute),
                          !isGenericTeamsUIValue(raw),
                          let parsed = parsedTeamsConversationCandidate(raw)
                    else {
                        continue
                    }

                    var score = baseScore
                    if parsed.directConversationSignal { score += 180 }
                    if parsed.strongSignal { score += 120 }
                    if parsed.name.lowercased().hasPrefix("chat with ") ||
                        parsed.name.lowercased().hasPrefix("conversation with ") {
                        score += 50
                    }
                    candidates.append((parsed.name, score))
                }

                var childrenValue: CFTypeRef?
                if AXUIElementCopyAttributeValue(
                    element,
                    kAXChildrenAttribute as CFString,
                    &childrenValue
                ) == .success,
                let children = childrenValue as? [AXUIElement] {
                    for child in children.prefix(12) {
                        for (attribute, baseScore) in [
                            (kAXTitleAttribute as CFString, 150),
                            (kAXDescriptionAttribute as CFString, 125),
                            (kAXValueAttribute as CFString, 75)
                        ] {
                            guard let raw = attributeString(child, attribute),
                                  !isGenericTeamsUIValue(raw),
                                  let parsed = parsedTeamsConversationCandidate(raw)
                            else {
                                continue
                            }

                            var score = baseScore
                            if parsed.directConversationSignal { score += 180 }
                            if parsed.strongSignal { score += 120 }
                            if parsed.name.lowercased().hasPrefix("chat with ") ||
                        parsed.name.lowercased().hasPrefix("conversation with ") {
                        score += 50
                    }
                            candidates.append((parsed.name, score))
                        }
                    }
                }
            }

            guard depth < 6 else { continue }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                for child in children.prefix(70) {
                    queue.append((child, depth + 1))
                }
            }
        }

        return candidates
            .filter { $0.score >= 160 }
            .max(by: { $0.score < $1.score })?
            .name
    }

    private func teamsSelectedConversationTitle(pid: pid_t) -> String? {
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

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var candidates: [(name: String, score: Int)] = []

        // Preferred path: selected rows in the Teams chat list.
        for selected in selectedAccessibilityRows(in: window) {
            let containerScore = teamsConversationContainerScore(selected)
            guard containerScore > 0,
                  let result = teamsNameFromSelectedElement(selected)
            else {
                continue
            }

            candidates.append((
                result.name,
                result.score + containerScore + 90
            ))
        }

        // Some Teams builds expose selected chat containers through
        // AXSelectedChildren instead of AXSelectedRows. Only accept containers
        // that independently look like a chat/conversation row.
        var queue: [AXUIElement] = [window]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 450 {
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
                for selected in selectedChildren.prefix(8) {
                    let containerScore = teamsConversationContainerScore(selected)
                    guard containerScore > 0,
                          let result = teamsNameFromSelectedElement(selected)
                    else {
                        continue
                    }

                    candidates.append((
                        result.name,
                        result.score + containerScore + 55
                    ))
                }
            }

            if attributeBool(element, kAXSelectedAttribute as CFString) == true {
                let containerScore = teamsConversationContainerScore(element)
                if containerScore > 0,
                   let result = teamsNameFromSelectedElement(element) {
                    candidates.append((
                        result.name,
                        result.score + containerScore + 75
                    ))
                }
            }

            appendChildren(of: element, to: &queue, limit: 65)
        }

        guard let best = candidates
            .filter({ $0.score >= 190 })
            .max(by: { $0.score < $1.score })?
            .name
        else {
            return nil
        }

        return expandedTeamsGroupConversationTitle(best, pid: pid)
    }

    private func teamsNameFromSelectedElement(_ root: AXUIElement) -> (name: String, score: Int)? {
        let rootContainerScore = teamsConversationContainerScore(root)
        guard rootContainerScore > 0 else { return nil }

        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var inspected = 0
        var candidates: [(name: String, score: Int)] = []

        while index < queue.count, inspected < 38 {
            let entry = queue[index]
            index += 1
            inspected += 1

            let element = entry.element
            let depth = entry.depth
            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""

            for (attribute, baseScore) in [
                (kAXTitleAttribute as CFString, 120),
                (kAXDescriptionAttribute as CFString, 105),
                ("AXHelp" as CFString, 85),
                (kAXValueAttribute as CFString, 35)
            ] {
                guard let raw = attributeString(element, attribute) else { continue }
                guard !isGenericTeamsUIValue(raw) else { continue }
                guard let parsed = parsedTeamsConversationCandidate(raw) else { continue }

                var score = baseScore - (depth * 12)
                score += min(rootContainerScore, 120)
                if parsed.strongSignal { score += 180 }
                if parsed.directConversationSignal { score += 220 }

                if role.contains("row") ||
                    role.contains("cell") ||
                    role.contains("list") ||
                    role.contains("group") {
                    score += 25
                }

                if parsed.name.lowercased().hasPrefix("chat with ") ||
                    parsed.name.lowercased().hasPrefix("conversation with ") {
                    score += 55
                }

                candidates.append((parsed.name, score))
            }

            guard depth < 2 else { continue }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                for child in children.prefix(depth == 0 ? 18 : 10) {
                    queue.append((child, depth + 1))
                }
            }
        }

        return candidates
            .filter { $0.score >= 145 }
            .max(by: { $0.score < $1.score })
    }

    private func teamsConversationContainerScore(_ element: AXUIElement) -> Int {
        let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""
        let roleDescription = attributeString(element, kAXRoleDescriptionAttribute as CFString)?.lowercased() ?? ""
        let identifier = attributeString(element, kAXIdentifierAttribute as CFString)?.lowercased() ?? ""
        let help = attributeString(element, "AXHelp" as CFString)?.lowercased() ?? ""
        let title = attributeString(element, kAXTitleAttribute as CFString)?.lowercased() ?? ""
        let description = attributeString(element, kAXDescriptionAttribute as CFString)?.lowercased() ?? ""

        let metadata = [role, roleDescription, identifier, help, title, description]
            .joined(separator: " ")

        if isGenericTeamsUIValue(title) ||
            isGenericTeamsUIValue(description) ||
            isGenericTeamsUIValue(help) {
            return -300
        }

        var score = 0
        let isSelected = attributeBool(element, kAXSelectedAttribute as CFString) == true

        if role.contains("row") || role.contains("cell") {
            score += 85
        }

        if isSelected &&
            (role.contains("row") ||
             role.contains("cell") ||
             role.contains("group") ||
             role.contains("listitem")) {
            score += 120
        }
        if role.contains("listitem") || roleDescription.contains("list item") {
            score += 75
        }
        if identifier.contains("chat") ||
            identifier.contains("conversation") ||
            roleDescription.contains("chat") ||
            roleDescription.contains("conversation") {
            score += 125
        }
        if metadata.contains("chat item") ||
            metadata.contains("conversation item") ||
            metadata.contains("recent chat") {
            score += 120
        }
        if identifier.contains("chat-list") ||
            identifier.contains("chat_list") ||
            identifier.contains("conversation-list") ||
            roleDescription.contains("chat list") ||
            roleDescription.contains("conversation list") {
            score += 110
        }

        // A generic AXGroup is only eligible when Teams itself labels it as
        // chat/conversation content. This prevents navigation groups such as
        // Favorites, Copilot, and Message List from becoming fake chats.
        if role.contains("group") && score == 0 {
            return isSelected ? 95 : -50
        }

        if role.contains("button") ||
            role.contains("toolbar") ||
            role.contains("navigation") ||
            role.contains("textfield") ||
            role.contains("textarea") {
            score -= 140
        }

        return score
    }

    private struct TeamsConversationCandidate {
        let name: String
        let strongSignal: Bool
        let directConversationSignal: Bool
    }

    private func parsedTeamsConversationCandidate(_ rawValue: String) -> TeamsConversationCandidate? {
        let raw = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !raw.isEmpty, !isGenericTeamsUIValue(raw) else { return nil }

        let lower = raw.lowercased()

        // New Teams commonly exposes the focused chat window as:
        // "Chat | Person Name | Tenant | account@domain".
        // The second pipe-delimited field is the actual conversation name.
        let pipeParts = raw
            .components(separatedBy: " | ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pipeParts.count >= 2,
           pipeParts[0].lowercased() == "chat",
           let cleaned = sanitizedTeamsPeopleLabel(pipeParts[1]),
           !isGenericTeamsUIValue(cleaned) {
            return TeamsConversationCandidate(
                name: "Chat with \(cleaned)",
                strongSignal: true,
                directConversationSignal: true
            )
        }

        let directPrefixes = [
            "group chat with ",
            "conversation with ",
            "chat with ",
            "group chat "
        ]

        for prefix in directPrefixes where lower.hasPrefix(prefix) {
            let people = String(raw.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let cleaned = sanitizedTeamsPeopleLabel(people),
                  !isGenericTeamsUIValue(cleaned)
            else {
                return nil
            }

            return TeamsConversationCandidate(
                name: "Chat with \(cleaned)",
                strongSignal: true,
                directConversationSignal: true
            )
        }

        // Chat-list rows often expose identity + presence/time/message metadata.
        let separators = [", ", "; "]
        for separator in separators {
            let parts = raw
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2 else { continue }

            let trailing = parts.dropFirst().joined(separator: " ").lowercased()
            let metadataMarkers = [
                "available", "busy", "away", "offline", "online",
                "do not disturb", "last message", "last activity",
                "unread", "muted", "pinned", "external", "guest",
                "today", "yesterday", " am", " pm", "minutes ago",
                "hours ago"
            ]

            guard metadataMarkers.contains(where: { trailing.contains($0) }),
                  let first = parts.first,
                  let cleaned = sanitizedTeamsPeopleLabel(first),
                  !isGenericTeamsUIValue(cleaned)
            else {
                continue
            }

            let name = looksLikeTeamsDisplayName(cleaned)
                ? "Chat with \(cleaned)"
                : cleaned

            return TeamsConversationCandidate(
                name: name,
                strongSignal: true,
                directConversationSignal: false
            )
        }

        // Bare names are accepted only inside a container already identified
        // as an actual Teams chat row; they are never sufficient by themselves.
        guard let cleaned = sanitizedTeamsPeopleLabel(raw),
              !isGenericTeamsUIValue(cleaned)
        else {
            return nil
        }

        return TeamsConversationCandidate(
            name: looksLikeTeamsDisplayName(cleaned)
                ? "Chat with \(cleaned)"
                : cleaned,
            strongSignal: false,
            directConversationSignal: false
        )
    }

    private func teamsConversationTitleFromFocusedWindow(pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID(),
        let raw = attributeString(
            unsafeBitCast(focusedWindowValue, to: AXUIElement.self),
            kAXTitleAttribute as CFString
        )
        else {
            return nil
        }

        let lower = raw.lowercased()
        guard lower.contains("microsoft teams") ||
              lower.hasPrefix("chat | ") ||
              lower.hasPrefix("chat with ") ||
              lower.hasPrefix("conversation with ") ||
              lower.hasPrefix("group chat with ")
        else {
            return nil
        }

        guard !isGenericTeamsUIValue(raw),
              let parsed = parsedTeamsConversationCandidate(raw)?.name
        else {
            return nil
        }

        return expandedTeamsGroupConversationTitle(parsed, pid: pid)
    }

    private struct TeamsGroupExpansionCacheEntry {
        let title: String
        let expiresAt: Date
    }

    private struct CollapsedTeamsGroupChat {
        let firstName: String
        let additionalCount: Int
    }

    private func expandedTeamsGroupConversationTitle(_ title: String, pid: pid_t) -> String {
        guard let collapsed = collapsedTeamsGroupChat(from: title) else {
            return title
        }

        let cacheKey = "\(pid)|\(title.lowercased())"
        let now = Date()

        if let cached = teamsGroupExpansionCache[cacheKey],
           cached.expiresAt > now {
            return cached.title
        }

        let targetCount = collapsed.additionalCount + 1
        guard targetCount > 1 else { return title }

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
            return title
        }

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var names = [collapsed.firstName]
        var seen = Set([collapsed.firstName.lowercased()])

        var queue: [(element: AXUIElement, depth: Int)] = [(window, 0)]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 420, names.count < targetCount {
            let entry = queue[index]
            index += 1
            inspected += 1

            let element = entry.element
            let depth = entry.depth

            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            let roleDescription = attributeString(element, kAXRoleDescriptionAttribute as CFString)?.lowercased() ?? ""
            let identifier = attributeString(element, kAXIdentifierAttribute as CFString)?.lowercased() ?? ""
            let help = attributeString(element, "AXHelp" as CFString)?.lowercased() ?? ""

            let semanticText = [role, roleDescription, identifier, help]
                .joined(separator: " ")

            let participantSemantic =
                semanticText.contains("participant") ||
                semanticText.contains("member") ||
                semanticText.contains("avatar") ||
                semanticText.contains("profile") ||
                semanticText.contains("people") ||
                semanticText.contains("person") ||
                semanticText.contains("chat header") ||
                semanticText.contains("conversation header") ||
                identifier.contains("chat-title") ||
                identifier.contains("chat_title") ||
                identifier.contains("conversation-title") ||
                identifier.contains("conversation_title")

            if participantSemantic {
                for attribute in [
                    kAXTitleAttribute as CFString,
                    kAXDescriptionAttribute as CFString,
                    kAXValueAttribute as CFString,
                    "AXHelp" as CFString
                ] {
                    guard let raw = attributeString(element, attribute) else { continue }

                    for candidate in teamsParticipantNames(from: raw) {
                        let key = candidate.lowercased()
                        guard !seen.contains(key) else { continue }

                        seen.insert(key)
                        names.append(candidate)

                        if names.count >= targetCount {
                            break
                        }
                    }

                    if names.count >= targetCount {
                        break
                    }
                }
            }

            guard depth < 7 else { continue }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                for child in children.prefix(70) {
                    queue.append((child, depth + 1))
                }
            }
        }

        // Only replace +N when Teams actually exposed enough individual names.
        // This prevents Memory Trail from inventing or partially guessing members.
        guard names.count == targetCount else {
            teamsGroupExpansionCache[cacheKey] = TeamsGroupExpansionCacheEntry(
                title: title,
                expiresAt: now.addingTimeInterval(6)
            )
            return title
        }

        let expanded = "Chat with " + naturalTeamsNameList(names)
        teamsGroupExpansionCache[cacheKey] = TeamsGroupExpansionCacheEntry(
            title: expanded,
            expiresAt: now.addingTimeInterval(5 * 60)
        )
        return expanded
    }

    private func collapsedTeamsGroupChat(from rawTitle: String) -> CollapsedTeamsGroupChat? {
        var value = rawTitle
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["Chat with ", "Conversation with "] {
            if value.lowercased().hasPrefix(prefix.lowercased()) {
                value = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let pattern = #"^(.+?)\s+\+(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              match.numberOfRanges == 3,
              let nameRange = Range(match.range(at: 1), in: value),
              let countRange = Range(match.range(at: 2), in: value),
              let count = Int(value[countRange]),
              count > 0
        else {
            return nil
        }

        let firstName = String(value[nameRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard looksLikeTeamsDisplayName(firstName) else { return nil }

        return CollapsedTeamsGroupChat(
            firstName: firstName,
            additionalCount: count
        )
    }

    private func teamsParticipantNames(from rawValue: String) -> [String] {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: ", ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return [] }

        let lower = value.lowercased()
        if lower.contains("type a message") ||
            lower.contains("last message") ||
            lower.contains("message preview") ||
            lower.contains("more chat options") {
            return []
        }

        let prefixes = [
            "participants:",
            "participants",
            "members:",
            "members",
            "people:",
            "people",
            "profile picture of",
            "profile photo of",
            "avatar of",
            "person:"
        ]

        for prefix in prefixes where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
            break
        }

        // Do not treat the same collapsed Teams label as a real participant name.
        if collapsedTeamsGroupChat(from: "Chat with \(value)") != nil {
            return []
        }

        let parts = value
            .components(separatedBy: CharacterSet(charactersIn: ",;•"))
            .map {
                $0.trimmingCharacters(
                    in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":"))
                )
            }
            .filter { !$0.isEmpty }

        var results: [String] = []
        var seen = Set<String>()

        for part in parts {
            var candidate = part

            for suffix in [
                " (guest)", " (external)", " guest", " external",
                ", available", ", busy", ", away", ", offline"
            ] {
                if candidate.lowercased().hasSuffix(suffix) {
                    candidate = String(candidate.dropLast(suffix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard looksLikeTeamsDisplayName(candidate),
                  !isGenericTeamsUIValue(candidate)
            else {
                continue
            }

            let key = candidate.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(candidate)
        }

        return results
    }

    private func naturalTeamsNameList(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return ""
        case 1:
            return names[0]
        case 2:
            return "\(names[0]) and \(names[1])"
        default:
            return names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }

    private func sanitizedTeamsConversationName(_ rawValue: String) -> String? {
        let originalLines = rawValue
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var value = originalLines.first ?? rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return nil }

        let lowerOriginal = value.lowercased()

        let pipeParts = value
            .components(separatedBy: " | ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if pipeParts.count >= 2,
           pipeParts[0].lowercased() == "chat",
           let cleaned = sanitizedTeamsPeopleLabel(pipeParts[1]) {
            return "Chat with \(cleaned)"
        }

        let directChatPrefixes = [
            "Group chat with ",
            "Conversation with ",
            "Chat with ",
            "Group chat "
        ]

        for prefix in directChatPrefixes {
            if lowerOriginal.hasPrefix(prefix.lowercased()) {
                let people = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let cleanedPeople = sanitizedTeamsPeopleLabel(people) else { return nil }
                return "Chat with \(cleanedPeople)"
            }
        }

        // Teams frequently exposes a chat-list row as a composite accessibility
        // label such as "Billy Smith, Available, 10:42 AM, last message...".
        // Only keep the leading identity when the trailing components look like
        // status/time/chat metadata.
        for separator in [", ", "; "] {
            let parts = value
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if parts.count >= 2 {
                let trailing = parts.dropFirst().joined(separator: " ").lowercased()
                let metadataMarkers = [
                    "available", "busy", "away", "offline", "online",
                    "do not disturb", "last message", "last activity",
                    "unread", "muted", "pinned", "external", "guest",
                    "today", "yesterday", "am", "pm"
                ]

                if metadataMarkers.contains(where: { trailing.contains($0) }),
                   let first = parts.first,
                   let cleaned = sanitizedTeamsPeopleLabel(first) {
                    return looksLikeTeamsDisplayName(cleaned)
                        ? "Chat with \(cleaned)"
                        : cleaned
                }
            }
        }

        // Strip known Teams window chrome.
        for separator in [" | ", " — ", " - "] {
            let parts = value.components(separatedBy: separator)
            if parts.count > 1,
               parts.dropFirst().contains(where: {
                   let lower = $0.lowercased()
                   return lower.contains("microsoft teams") ||
                       lower == "teams" ||
                       lower == "chat"
               }) {
                value = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        guard let cleaned = sanitizedTeamsPeopleLabel(value) else { return nil }

        if looksLikeTeamsDisplayName(cleaned) {
            return "Chat with \(cleaned)"
        }

        return cleaned
    }

    private func sanitizedTeamsPeopleLabel(_ rawValue: String) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return nil }

        // Teams often appends row metadata after the actual chat/person name.
        // Example: "Ashar, Unread" or "Billy Smith; Available".
        for separator in [", ", "; "] {
            let parts = value
                .components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if parts.count >= 2 {
                let trailing = parts.dropFirst().joined(separator: " ").lowercased()
                let metadataMarkers = [
                    "unread", "read", "available", "busy", "away",
                    "offline", "online", "do not disturb", "muted",
                    "pinned", "external", "guest", "last message",
                    "last activity", "today", "yesterday", " am", " pm",
                    "minutes ago", "hours ago"
                ]

                if metadataMarkers.contains(where: { trailing.contains($0) }),
                   let first = parts.first {
                    value = first
                    break
                }
            }
        }

        let lower = value.lowercased()
        let generic = Set([
            "microsoft teams", "teams", "chat", "chats", "activity",
            "calendar", "calls", "communities", "apps", "settings",
            "files", "teams and channels", "new chat", "search",
            "type a message", "send a message", "message", "reply",
            "post a message", "compose", "format", "new message",
            "chat list", "conversation", "conversation list",
            "favorites", "copilot", "message list", "recent",
            "recent chats", "pinned", "discover",
            "unread", "read", "available", "busy", "away",
            "offline", "online", "do not disturb", "muted",
            "external", "guest", "more chat options", "chat options",
            "conversation options"
        ])

        guard value.count >= 2, value.count <= 100 else { return nil }
        guard !generic.contains(lower) else { return nil }
        guard !looksLikeURL(value), !looksLikeTimestampOrDate(value) else { return nil }

        let snippetMarkers = [
            "you:", "me:", "sent:", "replied:", "reacted:",
            "typing", "draft", "last message", "message preview",
            "new message", "unread message", "type a message",
            "send a message", "post a message", "press enter to send",
            "press enter to open", "more options", "more chat options"
        ]
        if snippetMarkers.contains(where: { lower.contains($0) }) { return nil }

        let commonMessageOnlyValues = Set([
            "yes", "no", "ok", "okay", "thanks", "thank you",
            "sounds good", "great", "perfect", "sure", "got it",
            "hello", "hi", "hey", "lol"
        ])
        if commonMessageOnlyValues.contains(lower) { return nil }

        if value.count > 80 { return nil }

        let sentencePunctuation = value.filter { ".?!".contains($0) }.count
        if sentencePunctuation > 0 { return nil }

        return value
    }

    private func looksLikeTeamsDisplayName(_ value: String) -> Bool {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["Chat with ", "Conversation with "] {
            if cleaned.lowercased().hasPrefix(prefix.lowercased()) {
                cleaned = String(cleaned.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let words = cleaned
            .replacingOccurrences(of: "&", with: " and ")
            .split(separator: " ")
            .map(String.init)

        guard (1...8).contains(words.count), cleaned.count <= 70 else { return false }

        let allowedConnectors = Set(["and", "of", "the", "de", "van", "von"])
        var meaningfulWords = 0

        for word in words {
            let lower = word.lowercased()
            if allowedConnectors.contains(lower) { continue }

            guard let first = word.unicodeScalars.first,
                  CharacterSet.uppercaseLetters.contains(first)
            else {
                return false
            }

            meaningfulWords += 1
        }

        return meaningfulWords >= 1
    }

    private func isGenericTeamsUIValue(_ rawValue: String) -> Bool {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for prefix in ["chat with ", "conversation with "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let exactGeneric = Set([
            "favorites",
            "copilot",
            "message list",
            "unread",
            "read",
            "available",
            "busy",
            "away",
            "offline",
            "online",
            "do not disturb",
            "muted",
            "external",
            "guest",
            "messages",
            "chat list",
            "conversation list",
            "recent",
            "recent chats",
            "pinned",
            "discover",
            "activity",
            "chat",
            "chats",
            "teams",
            "microsoft teams",
            "calendar",
            "calls",
            "communities",
            "apps",
            "apps and agents",
            "settings",
            "files",
            "teams and channels",
            "new chat",
            "new message",
            "search",
            "search teams",
            "notifications",
            "profile",
            "navigation",
            "navigation pane",
            "toolbar",
            "more",
            "more options",
            "more chat options",
            "chat options",
            "conversation options",
            "unread",
            "read",
            "available",
            "busy",
            "away",
            "offline",
            "online",
            "do not disturb",
            "muted",
            "type a message",
            "send a message",
            "post a message",
            "compose",
            "format",
            "reply"
        ])

        if exactGeneric.contains(value) { return true }
        if value.hasSuffix(" unread") || value.hasSuffix(" read") {
            let prefix = value
                .replacingOccurrences(of: " unread", with: "")
                .replacingOccurrences(of: " read", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if Int(prefix) != nil { return true }
        }

        let genericFragments = [
            "message list",
            "chat list",
            "conversation list",
            "more chat options",
            "chat options",
            "conversation options",
            "navigation pane",
            "type a message",
            "send a message",
            "post a message",
            "press enter to send",
            "press enter to open"
        ]

        if genericFragments.contains(where: { value.contains($0) }) {
            return true
        }

        let genericSuffixes = [
            " button",
            " menu",
            " toolbar",
            " navigation",
            " navigation pane",
            " list",
            " tab"
        ]

        return genericSuffixes.contains(where: { value.hasSuffix($0) })
    }

    private func looksLikeURL(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("http://") ||
            lower.hasPrefix("https://") ||
            lower.hasPrefix("www.") ||
            lower.contains("urldefense.com/") ||
            lower.contains("safelinks.protection.outlook.com/")
    }

    private func looksLikeTimestampOrDate(_ value: String) -> Bool {
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["today", "yesterday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"].contains(lower) {
            return true
        }

        let pattern = #"^\d{1,2}:\d{2}(\s?[ap]m)?$|^\d{1,2}/\d{1,2}(/\d{2,4})?$"#
        return lower.range(of: pattern, options: .regularExpression) != nil
    }

    private func looksLikePersonName(_ value: String) -> Bool {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = cleaned.split(separator: " ")
        guard (1...5).contains(words.count), cleaned.count <= 60 else { return false }

        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= max(2, cleaned.count / 2) else { return false }

        return !cleaned.contains(":") &&
            !cleaned.contains("/") &&
            !cleaned.contains("\\") &&
            !cleaned.contains("@")
    }

    private func teamsConversationTitle(from rawTitle: String) -> String? {
        sanitizedTeamsConversationName(rawTitle)
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
            "drafts",
            "sent",
            "sent items",
            "deleted items",
            "junk email",
            "archive",
            "follow-ups",
            "microsoft outlook",
            "outlook"
        ])

        if exactGeneric.contains(lower) { return false }
        if lower.contains("unread message") { return false }
        if lower.hasPrefix("from ") && lower.contains(" to ") && lower.contains(" events") { return false }
        if lower.contains("copyright ©") || lower.contains("all rights reserved") { return false }
        if lower.contains("one apple park way") { return false }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return false }
        if lower.contains("urldefense.com/") || lower.contains("safelinks.protection.outlook.com/") { return false }
        if lower.contains("outlook.office.com/") { return false }
        if lower.contains("click here") || lower == "view in browser" || lower == "unsubscribe" { return false }

        // Accessibility rows often append Outlook UI metadata to a real subject.
        // The AppleScript path above returns only the subject, so reject those
        // composite strings instead of displaying a fake summarized title.
        if lower.contains("; has ") && lower.contains("attachment") { return false }
        if lower.contains("; sent by ") { return false }

        return true
    }

    private enum OneNoteHierarchyKind {
        case notebook
        case section
        case page
    }

    private struct OneNoteCandidate {
        let value: String
        let score: Int
    }

    private struct OneNoteHierarchy {
        let notebook: String?
        let section: String?
        let page: String?

        var displayTitle: String {
            var seen = Set<String>()
            var parts: [String] = []

            for value in [notebook, section, page] {
                guard let value else { continue }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                let key = trimmed.lowercased()
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                parts.append(trimmed)
            }

            return parts.joined(separator: " > ")
        }
    }

    private func oneNoteSelectedHierarchy(pid: pid_t) -> OneNoteHierarchy? {
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

        let window = unsafeBitCast(focusedWindowValue, to: AXUIElement.self)
        var notebookCandidates: [OneNoteCandidate] = []
        var sectionCandidates: [OneNoteCandidate] = []
        var pageCandidates: [OneNoteCandidate] = []

        func collect(_ element: AXUIElement, bonus: Int) {
            guard let semantic = oneNoteSemanticKind(for: element),
                  let label = bestOneNoteLabel(in: element)
            else {
                return
            }

            let candidate = OneNoteCandidate(
                value: label,
                score: semantic.score + bonus + min(label.count, 80)
            )

            switch semantic.kind {
            case .notebook:
                notebookCandidates.append(candidate)
            case .section:
                sectionCandidates.append(candidate)
            case .page:
                pageCandidates.append(candidate)
            }
        }

        var queue: [AXUIElement] = [window]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 650 {
            let element = queue[index]
            index += 1
            inspected += 1

            var selectedRowsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedRowsAttribute as CFString,
                &selectedRowsValue
            ) == .success,
            let selectedRows = selectedRowsValue as? [AXUIElement] {
                for selected in selectedRows.prefix(10) {
                    collect(selected, bonus: 190)
                }
            }

            var selectedChildrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedChildrenAttribute as CFString,
                &selectedChildrenValue
            ) == .success,
            let selectedChildren = selectedChildrenValue as? [AXUIElement] {
                for selected in selectedChildren.prefix(10) {
                    collect(selected, bonus: 170)
                }
            }

            var tabsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXTabsAttribute as CFString,
                &tabsValue
            ) == .success,
            let tabs = tabsValue as? [AXUIElement] {
                for tab in tabs where attributeBool(tab, kAXSelectedAttribute as CFString) == true {
                    collect(tab, bonus: 180)
                }
            }

            if attributeBool(element, kAXSelectedAttribute as CFString) == true {
                collect(element, bonus: 150)
            }

            appendChildren(of: element, to: &queue, limit: 75)
        }

        if let focused = focusedAccessibilityElement(in: appElement) {
            collect(focused, bonus: 210)

            var current: AXUIElement? = focused
            var depth = 0
            while let element = current, depth < 8 {
                collect(element, bonus: max(80, 180 - depth * 15))
                current = parentElement(of: element)
                depth += 1
            }
        }

        let notebook = notebookCandidates.max(by: { $0.score < $1.score })?.value
        let section = sectionCandidates.max(by: { $0.score < $1.score })?.value
        var page = pageCandidates.max(by: { $0.score < $1.score })?.value

        // Some OneNote builds do not label the page list semantically. When
        // that happens, the focused/selected row is still a useful page title.
        if page == nil,
           let focused = focusedAccessibilityElement(in: appElement),
           let fallback = nearestRowOrSelectionContext(from: focused)?.title,
           let cleaned = sanitizedOneNoteLabel(fallback),
           cleaned.caseInsensitiveCompare(notebook ?? "") != .orderedSame,
           cleaned.caseInsensitiveCompare(section ?? "") != .orderedSame {
            page = cleaned
        }

        let hierarchy = OneNoteHierarchy(
            notebook: notebook,
            section: section,
            page: page
        )

        return hierarchy.displayTitle.isEmpty ? nil : hierarchy
    }

    private func oneNoteHierarchyFromClickedElement(
        _ element: AXUIElement,
        pid: pid_t
    ) -> OneNoteHierarchy? {
        let selected = oneNoteSelectedHierarchy(pid: pid)

        var clickedNotebook: String?
        var clickedSection: String?
        var clickedPage: String?

        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current, depth < 12 {
            if let semantic = oneNoteSemanticKind(for: candidate),
               let label = bestOneNoteLabel(in: candidate) {
                switch semantic.kind {
                case .notebook:
                    if clickedNotebook == nil { clickedNotebook = label }
                case .section:
                    if clickedSection == nil { clickedSection = label }
                case .page:
                    if clickedPage == nil { clickedPage = label }
                }
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        if clickedPage == nil,
           let fallback = nearestRowOrSelectionContext(from: element)?.title,
           let cleaned = sanitizedOneNoteLabel(fallback),
           cleaned.caseInsensitiveCompare(clickedNotebook ?? selected?.notebook ?? "") != .orderedSame,
           cleaned.caseInsensitiveCompare(clickedSection ?? selected?.section ?? "") != .orderedSame {
            clickedPage = cleaned
        }

        let hierarchy = OneNoteHierarchy(
            notebook: clickedNotebook ?? selected?.notebook,
            section: clickedSection ?? selected?.section,
            page: clickedPage ?? selected?.page
        )

        return hierarchy.displayTitle.isEmpty ? nil : hierarchy
    }

    private func oneNoteSemanticKind(
        for element: AXUIElement
    ) -> (kind: OneNoteHierarchyKind, score: Int)? {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current, depth < 7 {
            let role = attributeString(candidate, kAXRoleAttribute as CFString)?.lowercased() ?? ""
            let roleDescription = attributeString(
                candidate,
                kAXRoleDescriptionAttribute as CFString
            )?.lowercased() ?? ""
            let identifier = attributeString(
                candidate,
                kAXIdentifierAttribute as CFString
            )?.lowercased() ?? ""
            let help = attributeString(candidate, "AXHelp" as CFString)?.lowercased() ?? ""
            let title = attributeString(
                candidate,
                kAXTitleAttribute as CFString
            )?.lowercased() ?? ""
            let description = attributeString(
                candidate,
                kAXDescriptionAttribute as CFString
            )?.lowercased() ?? ""

            let metadata = [role, roleDescription, identifier, help, title, description]
                .joined(separator: " ")

            let score = max(60, 210 - depth * 24)

            if identifier.contains("page") ||
                roleDescription.contains("page") ||
                metadata.contains("page list") ||
                title == "pages" ||
                description == "pages" {
                return (.page, score + 35)
            }

            if identifier.contains("section") ||
                roleDescription.contains("section") ||
                metadata.contains("section tab") ||
                metadata.contains("section list") ||
                title == "sections" ||
                description == "sections" {
                return (.section, score + 30)
            }

            if identifier.contains("notebook") ||
                roleDescription.contains("notebook") ||
                metadata.contains("notebook list") ||
                title == "notebooks" ||
                description == "notebooks" {
                return (.notebook, score + 25)
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return nil
    }

    private func bestOneNoteLabel(in root: AXUIElement) -> String? {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var inspected = 0
        var candidates: [(value: String, score: Int)] = []

        while index < queue.count, inspected < 42 {
            let entry = queue[index]
            index += 1
            inspected += 1

            for (attribute, baseScore) in [
                (kAXTitleAttribute as CFString, 130),
                (kAXValueAttribute as CFString, 105),
                (kAXDescriptionAttribute as CFString, 85),
                ("AXHelp" as CFString, 60)
            ] {
                guard let raw = attributeString(entry.element, attribute),
                      let value = sanitizedOneNoteLabel(raw)
                else {
                    continue
                }

                candidates.append((
                    value: value,
                    score: baseScore - entry.depth * 18 + min(value.count, 60)
                ))
            }

            guard entry.depth < 2 else { continue }

            var childrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                entry.element,
                kAXChildrenAttribute as CFString,
                &childrenValue
            ) == .success,
            let children = childrenValue as? [AXUIElement] {
                for child in children.prefix(entry.depth == 0 ? 18 : 10) {
                    queue.append((child, entry.depth + 1))
                }
            }
        }

        return candidates.max(by: { $0.score < $1.score })?.value
    }

    private func sanitizedOneNoteLabel(_ rawValue: String) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return nil }

        for prefix in [
            "Selected, ",
            "Page, ",
            "Section, ",
            "Notebook, "
        ] where value.lowercased().hasPrefix(prefix.lowercased()) {
            value = String(value.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        if value.lowercased().hasSuffix(", selected") {
            value = String(value.dropLast(", selected".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard value.count >= 1, value.count <= 180 else { return nil }
        guard !looksLikeURL(value), !looksLikeTimestampOrDate(value) else { return nil }

        let generic = Set([
            "onenote", "microsoft onenote",
            "pages", "page", "page list", "add page", "new page",
            "sections", "section", "section list", "add section", "new section",
            "notebooks", "notebook", "notebook list",
            "navigation", "navigation pane", "search", "search notebooks",
            "home", "insert", "draw", "view", "help", "sync", "share"
        ])

        let lower = value.lowercased()
        guard !generic.contains(lower) else { return nil }

        let genericSuffixes = [
            " button", " toolbar", " menu", " navigation", " list"
        ]
        guard !genericSuffixes.contains(where: { lower.hasSuffix($0) }) else {
            return nil
        }

        return String(value.prefix(180))
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

    private func selectedAccessibilityRows(in root: AXUIElement) -> [AXUIElement] {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0
        var rows: [AXUIElement] = []

        while index < queue.count, inspected < 500 {
            let element = queue[index]
            index += 1
            inspected += 1

            var selectedRowsValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedRowsAttribute as CFString,
                &selectedRowsValue
            ) == .success,
            let selectedRows = selectedRowsValue as? [AXUIElement] {
                rows.append(contentsOf: selectedRows.prefix(12))
            }

            appendChildren(of: element, to: &queue, limit: 80)
        }

        return rows
    }

    private func focusedAccessibilityElement(in appElement: AXUIElement) -> AXUIElement? {
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

        return unsafeBitCast(focusedValue, to: AXUIElement.self)
    }

    private func nearestAccessibilityRow(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current, depth < 14 {
            let role = attributeString(candidate, kAXRoleAttribute as CFString)?.lowercased() ?? ""

            if role.contains("row") ||
                role.contains("cell") ||
                role.contains("outline") ||
                role.contains("list") ||
                role.contains("group") {
                return candidate
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return nil
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
            " | Slack", " - Slack", " — Slack",
            " | Discord", " - Discord", " — Discord",
            " | Zoom", " - Zoom", " — Zoom",
            " | Webex", " - Webex", " — Webex",
            " | Signal", " - Signal", " — Signal",
            " | WhatsApp", " - WhatsApp", " — WhatsApp",
            " | Telegram", " - Telegram", " — Telegram",
            " | Messages", " - Messages", " — Messages",
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
            "microsoft outlook", "microsoft teams", "teams", "slack", "discord",
            "zoom", "webex", "signal", "whatsapp", "telegram", "messages",
            "safari", "window", "tab group", "web area", "main", "finder", "preview"
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

        let timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollClipboard() }
        }
        timer.tolerance = 0.60
        clipboardTimer = timer
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
