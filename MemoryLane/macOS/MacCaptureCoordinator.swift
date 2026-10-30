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
        let lowerBundleID = bundleID.lowercased()

        if lowerBundleID == "com.microsoft.outlook" || isTeamsBundleID(lowerBundleID) {
            lastWindowSignature = ""
            lastWindowLoggedAt = .distantPast

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.pollFocusedWindow()
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

            captureOutlookSelectedSubject(application: app)
            return
        }

        if isTeamsBundleID(lowerBundleID) {
            var conversation: String?

            if result == .success,
               let hitElement,
               let row = nearestAccessibilityRow(from: hitElement),
               let parsed = teamsNameFromSelectedElement(row) {
                conversation = parsed.name
            }

            if conversation == nil {
                conversation = teamsSelectedConversationTitle(pid: app.processIdentifier)
                    ?? teamsConversationTitleFromFocusedWindow(pid: app.processIdentifier)
            }

            if let conversation {
                logActivity(
                    title: conversation,
                    sourceURL: nil,
                    applicationName: app.localizedName ?? "Microsoft Teams",
                    bundleID: bundleID
                )
            }
            return
        }

        if lowerBundleID == "com.apple.safari" ||
            fileAwareBundleIDs.contains(lowerBundleID) {
            pollFocusedWindow()
            return
        }

        guard result == .success, let hitElement else { return }

        let activity: ActivityContext?
        if lowerBundleID.contains("onenote") {
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
        if let subject = outlookSelectedSubjectFromAppleScript() {
            return subject
        }

        return outlookSelectedSubjectFromAccessibility(pid: pid)
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
        if let sender = outlookSelectedSenderFromAppleScript() {
            return sender
        }

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

        return nil
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

        for selected in selectedAccessibilityRows(in: window) {
            if let result = teamsNameFromSelectedElement(selected) {
                candidates.append(result)
            }
        }

        if let focused = focusedAccessibilityElement(in: appElement),
           let row = nearestAccessibilityRow(from: focused),
           let result = teamsNameFromSelectedElement(row) {
            candidates.append((result.name, result.score + 25))
        }

        var queue: [AXUIElement] = [window]
        var index = 0
        var inspected = 0

        while index < queue.count, inspected < 500 {
            let element = queue[index]
            index += 1
            inspected += 1

            var selectedElements: [AXUIElement] = []

            var selectedChildrenValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element,
                kAXSelectedChildrenAttribute as CFString,
                &selectedChildrenValue
            ) == .success,
            let selectedChildren = selectedChildrenValue as? [AXUIElement] {
                selectedElements.append(contentsOf: selectedChildren.prefix(8))
            }

            if attributeBool(element, kAXSelectedAttribute as CFString) == true {
                selectedElements.append(element)
            }

            for selected in selectedElements {
                if let result = teamsNameFromSelectedElement(selected) {
                    candidates.append(result)
                }
            }

            appendChildren(of: element, to: &queue, limit: 70)
        }

        return candidates.max(by: { $0.score < $1.score })?.name
    }

    private func teamsNameFromSelectedElement(_ root: AXUIElement) -> (name: String, score: Int)? {
        var elements: [AXUIElement] = [root]

        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            root,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] {
            elements.append(contentsOf: children.prefix(16))
        }

        var candidates: [(name: String, score: Int)] = []

        for element in elements {
            let role = attributeString(element, kAXRoleAttribute as CFString)?.lowercased() ?? ""

            for (attribute, baseScore) in [
                (kAXTitleAttribute as CFString, 110),
                (kAXDescriptionAttribute as CFString, 85),
                (kAXValueAttribute as CFString, 25)
            ] {
                guard let raw = attributeString(element, attribute) else { continue }
                guard let name = sanitizedTeamsConversationName(raw) else { continue }

                var score = baseScore
                let lowerRaw = raw.lowercased()

                if lowerRaw.hasPrefix("chat with ") ||
                    lowerRaw.hasPrefix("conversation with ") ||
                    lowerRaw.hasPrefix("group chat with ") {
                    score += 220
                }

                if role.contains("row") || role.contains("list") || role.contains("cell") {
                    score += 30
                }

                if name.lowercased().hasPrefix("conversation with ") { score += 60 }
                if name.count <= 80 { score += 20 }

                candidates.append((name, score))
            }
        }

        return candidates
            .filter { $0.score >= 115 }
            .max(by: { $0.score < $1.score })
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

        return teamsConversationTitle(from: raw)
    }

    private func sanitizedTeamsConversationName(_ rawValue: String) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let directChatPrefixes = [
            "Chat with ",
            "Conversation with ",
            "Group chat with "
        ]
        for prefix in directChatPrefixes {
            if value.lowercased().hasPrefix(prefix.lowercased()) {
                let people = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !people.isEmpty else { return nil }
                value = "Conversation with \(people)"
                break
            }
        }

        // Strip only known Teams chrome suffixes; never derive a title from body text.
        for separator in [" | ", " — ", " - "] {
            let parts = value.components(separatedBy: separator)
            if parts.count > 1,
               parts.dropFirst().contains(where: {
                   let lower = $0.lowercased()
                   return lower.contains("microsoft teams") || lower == "teams" || lower == "chat"
               }) {
                value = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let lower = value.lowercased()
        let generic = Set([
            "microsoft teams", "teams", "chat", "chats", "activity",
            "calendar", "calls", "communities", "apps", "settings",
            "files", "teams and channels", "new chat", "search"
        ])

        guard value.count >= 2, value.count <= 100 else { return nil }
        guard !generic.contains(lower) else { return nil }
        guard !looksLikeURL(value), !looksLikeTimestampOrDate(value) else { return nil }

        // Reject obvious message/snippet patterns. If uncertain, do not log it.
        let snippetMarkers = [
            "you:", "me:", "sent:", "replied:", "reacted:",
            "typing", "draft", "last message", "message preview",
            "new message", "unread message"
        ]
        if snippetMarkers.contains(where: { lower.contains($0) }) { return nil }
        if value.contains("\n") { return nil }
        if value.count > 80 { return nil }
        if value.contains("\n") { return nil }

        let sentencePunctuation = value.filter { ".?!".contains($0) }.count
        if sentencePunctuation > 0 && !lower.hasPrefix("conversation with ") {
            return nil
        }

        return value
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
            "microsoft outlook",
            "outlook"
        ])

        if exactGeneric.contains(lower) { return false }
        if lower.contains("unread message") && lower.hasPrefix("inbox") { return false }
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
