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
    @ObservationIgnored private var outlookClickCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var lastOutlookMessageKey: String?
    @ObservationIgnored private var lastOutlookSelectionHint: String?
    @ObservationIgnored private var confirmedNewOutlookPIDs: Set<pid_t> = []
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

        outlookClickCaptureTask?.cancel()
        outlookClickCaptureTask = nil
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
        outlookClickCaptureTask?.cancel()
        outlookClickCaptureTask = nil
        lastOutlookMessageKey = nil
        lastOutlookSelectionHint = nil
        confirmedNewOutlookPIDs.removeAll(
            keepingCapacity: true
        )
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
                try? await Task.sleep(nanoseconds: 180_000_000)
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

        let timer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollFocusedWindow()
            }
        }
        timer.tolerance = 0.15
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

                if bundleID.lowercased() == "com.microsoft.outlook" {
                    try? await Task.sleep(
                        nanoseconds: 90_000_000
                    )
                    self.captureClickedContext(at: point)
                    return
                }

                try? await Task.sleep(nanoseconds: 160_000_000)
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
            let clickedSubject: String?
            let clickedSender: String?
            let clickedIdentity: String?

            if result == .success,
               let hitElement {
                clickedSubject =
                    outlookSubjectFromClickedElement(
                        hitElement
                    )
                clickedSender =
                    outlookSenderFromElement(hitElement) ??
                    outlookSelectedSender(
                        pid: app.processIdentifier
                    )
                clickedIdentity =
                    outlookClickedSelectionIdentity(
                        from: hitElement,
                        pid: app.processIdentifier
                    )
            } else {
                clickedSubject = nil
                clickedSender = nil
                clickedIdentity = nil
            }

            if outlookUsesNewOutlookLayout(
                pid: app.processIdentifier
            ) {
                scheduleOutlookMessageCapture(
                    application: app,
                    bundleID: bundleID,
                    expectedSubject: clickedSubject,
                    selectionSenderHint: clickedSender,
                    selectionIdentityHint: clickedIdentity
                )
                return
            }

            if let clickedSubject {
                logActivity(
                    title: clickedSubject,
                    sourceURL: nil,
                    applicationName:
                        app.localizedName ??
                        "Microsoft Outlook",
                    bundleID: bundleID,
                    baseDetail: clickedSender.map {
                        "From: \($0)"
                    },
                    activityIdentity:
                        clickedIdentity
                )
                return
            }

            scheduleOutlookMessageCapture(
                application: app,
                bundleID: bundleID,
                expectedSubject: clickedSubject,
                selectionSenderHint: clickedSender,
                selectionIdentityHint: clickedIdentity
            )
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
                    ?? teamsConversationHeaderTitle(pid: app.processIdentifier)
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


    private func outlookSubjectFromClickedElement(
        _ element: AXUIElement
    ) -> String? {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current,
              depth < 12 {
            let role = attributeString(
                candidate,
                kAXRoleAttribute as CFString
            )?.lowercased() ?? ""

            if role.contains("row") ||
                role.contains("cell") ||
                role.contains("outline") ||
                role.contains("list") ||
                role.contains("group") {
                if let subject =
                    outlookSubjectFromSelectedElement(
                        candidate,
                        requireStrongSignal: true
                    ) {
                    return subject
                }
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return nil
    }

    private func outlookUsesNewOutlookLayout(
        pid: pid_t
    ) -> Bool {
        if confirmedNewOutlookPIDs.contains(pid) {
            return true
        }

        let appElement =
            AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) ==
            AXUIElementGetTypeID()
        else {
            return false
        }

        let window = unsafeBitCast(
            focusedWindowValue,
            to: AXUIElement.self
        )

        var queue: [AXUIElement] = [window]
        var index = 0
        var inspected = 0
        var sawReadingPaneIdentifier = false
        var sawNewInboxSelectionState = false
        var sawWebContent = false
        var sawMessageHeaderStructure = false

        while index < queue.count,
              inspected < 900 {
            let element = queue[index]
            index += 1
            inspected += 1

            let role =
                attributeString(
                    element,
                    kAXRoleAttribute as CFString
                )?.lowercased() ?? ""

            if role.contains("webarea") ||
                role.contains("webcontent") ||
                role.contains("browser") {
                sawWebContent = true
            }

            let identifier =
                attributeString(
                    element,
                    kAXIdentifierAttribute as CFString
                )?.lowercased() ?? ""

            if identifier.contains("readingpane") ||
                identifier.contains("reading-pane") ||
                identifier.contains("messagepane") ||
                identifier.contains("message-pane") {
                sawReadingPaneIdentifier = true
            }

            if identifier.contains("messageheader") ||
                identifier.contains("message-header") ||
                identifier.contains("mail-header") {
                sawMessageHeaderStructure = true
            }

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDescriptionAttribute as CFString
            ] {
                guard let raw =
                    attributeString(
                        element,
                        attribute
                    )
                else {
                    continue
                }

                let lower = raw.lowercased()

                if lower.contains(
                    "summary by copilot"
                ) ||
                    lower.contains(
                        "copilot summary"
                    ) {
                    confirmedNewOutlookPIDs.insert(pid)
                    return true
                }

                if lower.contains(
                    "focused inbox selected"
                ) ||
                    lower.contains(
                        "other inbox unselected"
                    ) ||
                    lower.contains(
                        "other inbox selected"
                    ) {
                    sawNewInboxSelectionState = true
                }

                if isNewOutlookStructuralHeaderLabel(
                    raw
                ) {
                    sawMessageHeaderStructure = true
                }
            }

            appendChildren(
                of: element,
                to: &queue,
                limit: 90
            )
        }

        let confirmed =
            (
                sawReadingPaneIdentifier &&
                (
                    sawNewInboxSelectionState ||
                    sawWebContent ||
                    sawMessageHeaderStructure
                )
            ) ||
            (
                sawWebContent &&
                sawMessageHeaderStructure
            )

        if confirmed {
            confirmedNewOutlookPIDs.insert(pid)
        }

        return confirmed
    }


    private func outlookClickTargetsMessageSelection(
        at point: CGPoint,
        pid: pid_t
    ) -> Bool {
        var hitElement: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()

        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(point.x),
            Float(point.y),
            &hitElement
        ) == .success,
        let hitElement,
        let row = nearestAccessibilityRow(from: hitElement)
        else {
            return false
        }

        let role = attributeString(
            row,
            kAXRoleAttribute as CFString
        )?.lowercased() ?? ""

        // Only an actual message-list row/cell can trigger immediate capture.
        // Recipient chips, To/CC fields, reading-pane text, Copilot controls,
        // and toolbar buttons are intentionally excluded here.
        guard role.contains("row") ||
                role.contains("cell") ||
                role.contains("outline") ||
                role.contains("list")
        else {
            return false
        }

        guard isOutlookMessageSelectionCandidate(row) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) == AXUIElementGetTypeID(),
        let rowFrame = accessibilityFrame(of: row) {
            let window = unsafeBitCast(
                focusedWindowValue,
                to: AXUIElement.self
            )

            if let windowFrame = accessibilityFrame(of: window) {
                let messageListCutoff =
                    windowFrame.minX + (windowFrame.width * 0.69)

                if rowFrame.midX > messageListCutoff {
                    return false
                }
            }
        }

        return true
    }
    private func outlookClickedSelectionIdentity(
        from hitElement: AXUIElement,
        pid: pid_t
    ) -> String? {
        let appElement =
            AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) ==
            AXUIElementGetTypeID() {
            let window = unsafeBitCast(
                focusedWindowValue,
                to: AXUIElement.self
            )

            for selected in
                selectedAccessibilityRows(in: window) {
                guard isOutlookMessageSelectionCandidate(
                    selected
                ) else {
                    continue
                }

                let selectedIdentity =
                    outlookSelectedRowIdentity(
                        selected
                    ) ?? ""

                let frameIdentity: String
                if let frame =
                    accessibilityFrame(of: selected) {
                    frameIdentity = [
                        Int(frame.minX.rounded()),
                        Int(frame.minY.rounded()),
                        Int(frame.width.rounded()),
                        Int(frame.height.rounded())
                    ]
                    .map(String.init)
                    .joined(separator: ",")
                } else {
                    frameIdentity = ""
                }

                let identity = [
                    "selected-row",
                    selectedIdentity,
                    frameIdentity
                ]
                .filter { !$0.isEmpty }
                .joined(separator: "|")

                if !identity.isEmpty {
                    return identity
                }
            }
        }

        // Fallback for Outlook builds that do not expose AXSelectedRows.
        // Do not apply a left-side cutoff: in non-column layout the message
        // list can span the full width above the reading pane.
        guard let row =
            nearestAccessibilityRow(
                from: hitElement
            ),
              isOutlookMessageSelectionCandidate(row)
        else {
            return nil
        }

        let rowIdentity =
            outlookSelectedRowIdentity(row) ?? ""

        let frameIdentity: String
        if let frame =
            accessibilityFrame(of: row) {
            frameIdentity = [
                Int(frame.minX.rounded()),
                Int(frame.minY.rounded()),
                Int(frame.width.rounded()),
                Int(frame.height.rounded())
            ]
            .map(String.init)
            .joined(separator: ",")
        } else {
            frameIdentity = ""
        }

        let identity = [
            "clicked-row",
            rowIdentity,
            frameIdentity
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "|")

        return identity.isEmpty ? nil : identity
    }


    private func scheduleOutlookMessageCapture(
        application: NSRunningApplication,
        bundleID: String,
        expectedSubject: String? = nil,
        selectionSenderHint: String? = nil,
        selectionIdentityHint: String? = nil
    ) {
        outlookClickCaptureTask?.cancel()

        let pid = application.processIdentifier
        let appName =
            application.localizedName ??
            "Microsoft Outlook"
        let previousMessageKey =
            lastOutlookMessageKey
        let previousSelectionHint =
            lastOutlookSelectionHint

        outlookClickCaptureTask = Task {
            @MainActor [weak self] in
            guard let self else { return }

            let retryDelays: [UInt64] = [
                90_000_000,
                120_000_000,
                160_000_000,
                220_000_000,
                300_000_000,
                450_000_000,
                650_000_000
            ]

            for (attempt, delay) in
                retryDelays.enumerated() {
                try? await Task.sleep(
                    nanoseconds: delay
                )

                guard !Task.isCancelled,
                      NSWorkspace.shared
                        .frontmostApplication?
                        .processIdentifier == pid
                else {
                    return
                }

                guard let message =
                    self.outlookSelectedMessageContext(
                        pid: pid,
                        expectedNewOutlookSubject:
                            expectedSubject,
                        selectionSenderHint:
                            selectionSenderHint,
                        selectionIdentityHint:
                            selectionIdentityHint
                    )
                else {
                    continue
                }

                let messageKey =
                    self.outlookMessageKey(message)

                let hasNewSelectionHint =
                    selectionIdentityHint != nil &&
                    selectionIdentityHint !=
                        previousSelectionHint

                if let previousMessageKey,
                   messageKey == previousMessageKey,
                   !hasNewSelectionHint,
                   attempt <
                    retryDelays.count - 1 {
                    continue
                }

                if let previousMessageKey,
                   messageKey ==
                    previousMessageKey,
                   !hasNewSelectionHint {
                    return
                }

                self.lastExpensiveWindowPollAt =
                    Date()

                self.logActivity(
                    title: message.subject,
                    sourceURL: nil,
                    applicationName: appName,
                    bundleID: bundleID,
                    baseDetail:
                        message.sender.map {
                            "From: \($0)"
                        },
                    activityIdentity:
                        message.identity,
                    selectionDiscriminator:
                        selectionIdentityHint
                )
                return
            }
        }
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

        let isChatAccessibilityApp = isChatBundleID(lowerBundleID)
        let isExpensiveAccessibilityApp =
            lowerBundleID == "com.microsoft.outlook" ||
            isChatAccessibilityApp ||
            lowerBundleID.contains("onenote")

        if isExpensiveAccessibilityApp && !forceExpensiveApps {
            let now = Date()
            let minimumPollInterval: TimeInterval
            if lowerBundleID == "com.microsoft.outlook" {
                // Outlook selections should feel nearly live even when a click
                // event is missed by the global monitor.
                minimumPollInterval = 1.25
            } else if isChatAccessibilityApp {
                minimumPollInterval = 3.0
            } else {
                minimumPollInterval = 9.0
            }

            guard now.timeIntervalSince(lastExpensiveWindowPollAt) >= minimumPollInterval else {
                return
            }
            lastExpensiveWindowPollAt = now
        } else if isExpensiveAccessibilityApp {
            lastExpensiveWindowPollAt = Date()
        }

        if lowerBundleID == "com.microsoft.outlook" {
            guard let message = outlookSelectedMessageContext(
                pid: app.processIdentifier
            ) else {
                return
            }

            logActivity(
                title: message.subject,
                sourceURL: nil,
                applicationName: appName,
                bundleID: bundleID,
                baseDetail: message.sender.map { "From: \($0)" },
                activityIdentity: message.identity
            )
            return
        }

        if isTeamsBundleID(lowerBundleID) {
            guard let conversation = teamsSelectedConversationTitle(pid: app.processIdentifier)
                ?? teamsConversationHeaderTitle(pid: app.processIdentifier)
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
        baseDetail: String? = nil,
        activityIdentity: String? = nil,
        selectionDiscriminator: String? = nil
    ) {
        let lowerBundleID = bundleID.lowercased()
        let normalizedTitleSignature =
            lowerBundleID == "com.microsoft.outlook"
            ? normalizedOutlookIdentity(title)
            : title.lowercased()

        let normalizedDetailSignature =
            lowerBundleID == "com.microsoft.outlook"
            ? normalizedOutlookIdentity(baseDetail ?? "")
            : ""

        let signature = [
            lowerBundleID,
            activityIdentity ?? "",
            normalizedTitleSignature,
            normalizedDetailSignature,
            sourceURL?.lowercased() ?? ""
        ].joined(separator: "|")

        let now = Date()

        if lowerBundleID ==
            "com.microsoft.outlook" {
            if signature == lastWindowSignature {
                guard let selectionDiscriminator,
                      selectionDiscriminator !=
                        lastOutlookSelectionHint
                else {
                    return
                }
            }
        } else {
            guard signature !=
                    lastWindowSignature
            else {
                return
            }

            guard now.timeIntervalSince(
                lastWindowLoggedAt
            ) >= 0.6
            else {
                return
            }
        }

        lastWindowSignature = signature
        lastWindowLoggedAt = now

        guard let context else { return }

        let storedBody: String

        if lowerBundleID == "com.microsoft.outlook" {
            storedBody = baseDetail ?? ""

            let sender = baseDetail?
                .replacingOccurrences(
                    of: "From:",
                    with: "",
                    options: [.caseInsensitive, .anchored]
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            lastOutlookMessageKey = [
                activityIdentity ?? "",
                normalizedOutlookIdentity(title),
                normalizedOutlookIdentity(sender ?? "")
            ].joined(separator: "|")
            lastOutlookSelectionHint =
                selectionDiscriminator
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

    private struct OutlookMessageContext {
        let subject: String
        let sender: String?
        let identity: String?
        let isNewOutlookReadingPane: Bool

        init(
            subject: String,
            sender: String?,
            identity: String? = nil,
            isNewOutlookReadingPane: Bool = false
        ) {
            self.subject = subject
            self.sender = sender
            self.identity = identity
            self.isNewOutlookReadingPane =
                isNewOutlookReadingPane
        }
    }

    private func outlookMessageKey(
        _ message: OutlookMessageContext
    ) -> String {
        [
            message.identity ?? "",
            normalizedOutlookIdentity(message.subject),
            normalizedOutlookIdentity(message.sender ?? "")
        ].joined(separator: "|")
    }

    private func normalizedOutlookIdentity(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(
                of: #"[\s\u{00A0}]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    private func mergedOutlookIdentity(
        _ identities: [String?]
    ) -> String? {
        var result: [String] = []

        for identity in identities {
            guard let identity else {
                continue
            }

            let value = identity.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !value.isEmpty,
                  !result.contains(value)
            else {
                continue
            }

            result.append(value)
        }

        guard !result.isEmpty else {
            return nil
        }

        return result.joined(
            separator: "||"
        )
    }

    private func outlookSubjectsLikelySame(
        _ first: String,
        _ second: String
    ) -> Bool {
        let left =
            normalizedOutlookIdentity(first)
        let right =
            normalizedOutlookIdentity(second)

        if left == right {
            return true
        }

        let shortest =
            min(left.count, right.count)

        guard shortest >= 8 else {
            return false
        }

        return left.hasPrefix(right) ||
            right.hasPrefix(left)
    }


    private func captureOutlookSelectedSubject(application: NSRunningApplication) {
        guard let message = outlookSelectedMessageContext(
            pid: application.processIdentifier
        ) else {
            return
        }

        let appName = application.localizedName ?? "Microsoft Outlook"
        logActivity(
            title: message.subject,
            sourceURL: nil,
            applicationName: appName,
            bundleID: application.bundleIdentifier ?? "com.microsoft.outlook",
            baseDetail: message.sender.map { "From: \($0)" },
            activityIdentity: message.identity
        )
    }

    private func isOutlookCommandBarDescendant(
        _ element: AXUIElement
    ) -> Bool {
        var current: AXUIElement? = element
        var depth = 0

        while let candidate = current,
              depth < 6 {
            let role = attributeString(
                candidate,
                kAXRoleAttribute as CFString
            )?.lowercased() ?? ""
            let identifier = attributeString(
                candidate,
                kAXIdentifierAttribute as CFString
            )?.lowercased() ?? ""

            let controlRole =
                role.contains("button") ||
                role.contains("toolbar") ||
                role.contains("menuitem") ||
                role == "axmenu" ||
                role.contains("popup") ||
                role.contains("combobox") ||
                role.contains("segmented") ||
                role.contains("tab")

            let commandIdentifier =
                identifier.contains("commandbar") ||
                identifier.contains("command-bar") ||
                identifier.contains("toolbar") ||
                identifier.contains("ribbon") ||
                identifier.contains("actionbar") ||
                identifier.contains("action-bar")

            if controlRole || commandIdentifier {
                return true
            }

            current = parentElement(of: candidate)
            depth += 1
        }

        return false
    }

    private func outlookReadingPaneMessage(in root: AXUIElement) -> OutlookMessageContext? {
        guard let windowFrame = accessibilityFrame(of: root),
              windowFrame.width > 0,
              windowFrame.height > 0
        else {
            return nil
        }

        typealias ReadingPaneElement = (
            element: AXUIElement,
            depth: Int,
            frame: CGRect?,
            role: String,
            identifier: String
        )

        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var inspected = 0
        var elements: [ReadingPaneElement] = []

        while index < queue.count, inspected < 1_500 {
            let current = queue[index]
            index += 1
            inspected += 1

            let element = current.element
            let frame = accessibilityFrame(of: element)

            let role = attributeString(
                element,
                kAXRoleAttribute as CFString
            )?.lowercased() ?? ""
            let identifier = attributeString(
                element,
                kAXIdentifierAttribute as CFString
            )?.lowercased() ?? ""

            elements.append((
                element,
                current.depth,
                frame,
                role,
                identifier
            ))

            if current.depth < 13 {
                appendAccessibilityChildren(
                    of: element,
                    depth: current.depth,
                    to: &queue,
                    limit: 90
                )
            }
        }

        let semanticPaneFrames = elements.compactMap { item -> CGRect? in
            guard let frame = item.frame else { return nil }

            let semantic =
                item.identifier.contains("readingpane") ||
                item.identifier.contains("reading-pane") ||
                item.identifier.contains("messagepane") ||
                item.identifier.contains("message-pane") ||
                item.identifier.contains("mail-reading")

            guard semantic,
                  frame.width >= 260,
                  frame.height >= 180
            else {
                return nil
            }

            return frame
        }

        let semanticPaneFrame = semanticPaneFrames.max(by: {
            ($0.width * $0.height) < ($1.width * $1.height)
        })

        var structuralHeaderFrames: [CGRect] = []

        for item in elements {
            guard let frame = item.frame else {
                continue
            }

            let identifierSignal =
                item.identifier.contains("messageheader") ||
                item.identifier.contains("message-header") ||
                item.identifier.contains("mail-header")

            var labelSignal = identifierSignal

            if !labelSignal {
                for attribute in [
                    kAXTitleAttribute as CFString,
                    kAXValueAttribute as CFString,
                    kAXDescriptionAttribute as CFString
                ] {
                    if let raw = attributeString(
                        item.element,
                        attribute
                    ),
                    isNewOutlookStructuralHeaderLabel(raw) {
                        labelSignal = true
                        break
                    }
                }
            }

            guard labelSignal else {
                continue
            }

            if frame.width >= 80,
               frame.height >= 20 {
                structuralHeaderFrames.append(frame)
            }

            if let parent = parentElement(
                of: item.element
            ),
            let parentFrame = accessibilityFrame(
                of: parent
            ),
            parentFrame.width >= 260,
            parentFrame.height >= 80 {
                structuralHeaderFrames.append(
                    parentFrame
                )
            }
        }

        let structuralHeaderFrame =
            structuralHeaderFrames.max(by: {
                ($0.width * $0.height) <
                    ($1.width * $1.height)
            })

        let paneFrame: CGRect

        if let semanticPaneFrame {
            // Works for right, bottom, fill-screen, and pop-out layouts when
            // Outlook exposes an explicit reading/message pane.
            paneFrame = semanticPaneFrame
        } else if let structuralHeaderFrame {
            // In non-column layout the message header is commonly below the
            // message list. Anchor the capture region to the actual header
            // location instead of the top of the Outlook window.
            let startsLowInWindow =
                structuralHeaderFrame.minY >
                windowFrame.minY +
                    (windowFrame.height * 0.24)

            let isWideHeader =
                structuralHeaderFrame.width >=
                    (windowFrame.width * 0.52)

            let useFullWidth =
                startsLowInWindow ||
                isWideHeader

            let expandedX =
                useFullWidth
                ? windowFrame.minX
                : max(
                    windowFrame.minX,
                    structuralHeaderFrame.minX - 36
                )

            let expandedY = max(
                windowFrame.minY,
                structuralHeaderFrame.minY - 72
            )

            paneFrame = CGRect(
                x: expandedX,
                y: expandedY,
                width:
                    useFullWidth
                    ? windowFrame.width
                    : max(
                        260,
                        windowFrame.maxX - expandedX
                    ),
                height: max(
                    180,
                    windowFrame.maxY - expandedY
                )
            )
        } else {
            // Last-resort fallback must be layout-neutral. The subject/sender
            // geometry and UI-noise filters below decide which header wins.
            paneFrame = windowFrame
        }

        let headerBottom =
            min(
                paneFrame.maxY,
                paneFrame.minY +
                    max(
                        360,
                        paneFrame.height * 0.62
                    )
            )

        // In New Outlook the command bar (Delete / Archive / Move / Flag)
        // sits above the actual message header. When the Summary by Copilot
        // card is present, use its bottom edge as an authoritative start for
        // message-header content so command-bar labels can never outrank the
        // real subject.
        var copilotBottomY: CGFloat?

        for item in elements {
            guard let frame = item.frame,
                  frame.midX >= paneFrame.minX,
                  frame.midX <= paneFrame.maxX,
                  frame.midY >= paneFrame.minY,
                  frame.midY <= headerBottom
            else {
                continue
            }

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXDescriptionAttribute as CFString
            ] {
                guard let raw = attributeString(
                    item.element,
                    attribute
                ) else {
                    continue
                }

                let lower = raw.lowercased()
                if lower.contains("summary by copilot") ||
                    lower.contains("copilot summary") {
                    copilotBottomY = max(
                        copilotBottomY ?? frame.maxY,
                        frame.maxY
                    )
                }
            }
        }

        let messageHeaderTop =
            copilotBottomY.map { $0 + 4 } ??
            paneFrame.minY

        var subjectCandidates: [
            (
                subject: String,
                score: Int,
                frame: CGRect
            )
        ] = []

        var senderCandidates: [
            (
                sender: String,
                score: Int,
                frame: CGRect
            )
        ] = []

        var timestampCandidates: [
            (
                value: String,
                score: Int,
                frame: CGRect
            )
        ] = []

        var sawNewOutlookSignal = false

        for item in elements {
            guard let frame = item.frame,
                  frame.midX >= paneFrame.minX,
                  frame.midX <= paneFrame.maxX,
                  frame.midY >= messageHeaderTop,
                  frame.midY <= paneFrame.maxY,
                  frame.midY <= headerBottom,
                  !isOutlookCommandBarDescendant(
                    item.element
                  )
            else {
                continue
            }

            let semanticSubject =
                item.identifier.contains("subject") ||
                item.identifier.contains("message-subject") ||
                item.identifier.contains("message_subject") ||
                item.identifier.contains("readingpane-subject") ||
                item.identifier.contains("reading-pane-subject")

            let semanticSender =
                item.identifier.contains("sender") ||
                item.identifier.contains("message-from") ||
                item.identifier.contains("message_from") ||
                item.identifier.contains("organizer") ||
                item.identifier.contains("organiser") ||
                item.identifier.contains("invited-by") ||
                item.identifier.contains("invited_by") ||
                item.identifier == "from" ||
                item.identifier.hasSuffix("-from")

            for (attribute, baseScore) in [
                (kAXTitleAttribute as CFString, 150),
                (kAXValueAttribute as CFString, 135),
                (kAXDescriptionAttribute as CFString, 120)
            ] {
                guard let raw = attributeString(item.element, attribute)
                else {
                    continue
                }

                let lowerRaw = raw.lowercased()
                if lowerRaw.contains("summary by copilot") ||
                    lowerRaw.contains("copilot summary") {
                    sawNewOutlookSignal = true
                }

                guard !isOutlookMessageListComposite(raw),
                      !isOutlookCopilotOrSummaryText(raw)
                else {
                    continue
                }

                if let timestamp =
                    outlookReadingPaneTimestamp(from: raw) {
                    timestampCandidates.append((
                        timestamp,
                        baseScore + 300 - item.depth * 3,
                        frame
                    ))
                }

                if semanticSubject,
                   !isNewOutlookStructuralHeaderLabel(raw),
                   !isOutlookNavigationChrome(raw),
                   !isOutlookMessageGroupHeader(raw),
                   let subject = sanitizedOutlookSubject(
                        raw,
                        allowSenderLikeSubject: true
                   ) {
                    var score = baseScore + 1_000 - item.depth * 4
                    if let structuralHeaderFrame,
                       frame.intersects(
                            structuralHeaderFrame.insetBy(
                                dx: -80,
                                dy: -120
                            )
                       ) {
                        score += 260
                    }
                    score += max(
                        0,
                        180 - Int(abs(frame.minY - paneFrame.minY) / 2)
                    )
                    subjectCandidates.append((subject, score, frame))
                }

                if let metadataSubject = outlookSubjectFromMetadataText(raw),
                   !isOutlookCopilotOrSummaryText(metadataSubject),
                   !isNewOutlookStructuralHeaderLabel(metadataSubject) {
                    subjectCandidates.append((
                        metadataSubject,
                        baseScore + 760 - item.depth * 4,
                        frame
                    ))
                }

                // New Outlook frequently exposes the visible subject under the
                // Copilot card as ordinary static text with no subject-specific
                // identifier. Accept a plausible, top-of-pane header line while
                // still rejecting sender/recipient/action/body text.
                let genericHeaderLimit =
                    min(
                        headerBottom,
                        max(
                            messageHeaderTop + 420,
                            paneFrame.minY +
                                (paneFrame.height * 0.44)
                        )
                    )

                if !semanticSubject,
                   frame.midY <= genericHeaderLimit,
                   frame.width >= 70,
                   let subject = outlookReadingPaneVisibleSubject(from: raw) {
                    var score = baseScore + 560 - item.depth * 4
                    score += max(
                        0,
                        220 - Int(abs(frame.minY - paneFrame.minY) / 2)
                    )
                    subjectCandidates.append((subject, score, frame))
                }

                if let sender = outlookReadingPaneSender(
                    from: raw,
                    allowPlainValue: semanticSender
                ) {
                    var score = baseScore - item.depth * 4
                    if semanticSender {
                        score += 820
                    } else {
                        score += 420
                    }
                    if let structuralHeaderFrame,
                       frame.intersects(
                            structuralHeaderFrame.insetBy(
                                dx: -80,
                                dy: -120
                            )
                       ) {
                        score += 220
                    }
                    senderCandidates.append((sender, score, frame))
                } else if frame.midY <= genericHeaderLimit,
                          let sender = outlookReadingPaneVisibleSender(from: raw) {
                    // The sender line immediately below the subject is often
                    // plain AXStaticText, e.g. "Choua Vang <choua...>".
                    senderCandidates.append((
                        sender,
                        baseScore + 430 - item.depth * 4,
                        frame
                    ))
                }
            }
        }

        let newOutlookCommandLabels = Set([
            "delete",
            "archive",
            "move",
            "move to",
            "flag",
            "mark read",
            "mark unread",
            "new mail",
            "junk",
            "report",
            "categorize",
            "snooze",
            "pin",
            "print",
            "accept",
            "accepted",
            "tentative",
            "decline",
            "declined",
            "propose new time",
            "response options",
            "respond",
            "send response",
            "do not send a response",
            "no response required"
        ])

        let bestSenderCandidate = senderCandidates
            .filter {
                let key = normalizedOutlookIdentity(
                    $0.sender
                )
                return !newOutlookCommandLabels.contains(
                    key
                )
            }
            .max(by: {
                let leftScore =
                    $0.score +
                    max(
                        0,
                        260 - Int(
                            abs(
                                $0.frame.midY -
                                messageHeaderTop
                            )
                        )
                    )
                let rightScore =
                    $1.score +
                    max(
                        0,
                        260 - Int(
                            abs(
                                $1.frame.midY -
                                messageHeaderTop
                            )
                        )
                    )
                return leftScore < rightScore
            })

        let eligibleSubjects = subjectCandidates.filter {
            candidate in
            let key = normalizedOutlookIdentity(
                candidate.subject
            )

            guard !newOutlookCommandLabels.contains(key),
                  !isOutlookHeaderMetadataText(
                    candidate.subject
                  ),
                  !isNewOutlookStructuralHeaderLabel(
                    candidate.subject
                  )
            else {
                return false
            }

            if let sender = bestSenderCandidate {
                let verticalOffset =
                    sender.frame.midY -
                    candidate.frame.midY

                guard verticalOffset >= 4,
                      verticalOffset <= 320
                else {
                    return false
                }

                let horizontalDistance = abs(
                    sender.frame.midX -
                    candidate.frame.midX
                )

                guard horizontalDistance <= max(
                    520,
                    paneFrame.width * 0.88
                ) else {
                    return false
                }
            }

            return true
        }

        guard let bestSubject =
            eligibleSubjects.max(by: {
                left,
                right in

                func anchoredScore(
                    _ candidate: (
                        subject: String,
                        score: Int,
                        frame: CGRect
                    )
                ) -> Int {
                    var score = candidate.score

                    if let sender =
                        bestSenderCandidate {
                        let verticalOffset =
                            sender.frame.midY -
                            candidate.frame.midY
                        score += max(
                            0,
                            600 -
                            Int(
                                abs(
                                    verticalOffset - 48
                                ) * 4
                            )
                        )
                    }

                    return score
                }

                return anchoredScore(left) <
                    anchoredScore(right)
            })
        else {
            return nil
        }

        let subjectKey =
            normalizedOutlookIdentity(
                bestSubject.subject
            )

        let bestSender = bestSenderCandidate
            .flatMap { candidate -> String? in
                let senderKey =
                    normalizedOutlookIdentity(
                        candidate.sender
                    )

                guard senderKey != subjectKey
                else {
                    return nil
                }

                return candidate.sender
            }

        let bestTimestamp = timestampCandidates
            .compactMap {
                candidate -> (value: String, score: Int)? in
                let offset =
                    candidate.frame.midY -
                    bestSubject.frame.midY

                guard offset >= -20,
                      offset <= 260
                else {
                    return nil
                }

                let distance = abs(offset)

                return (
                    candidate.value,
                    candidate.score +
                        max(0, 260 - Int(distance))
                )
            }
            .max(by: { $0.score < $1.score })?
            .value

        let identityParts = [
            subjectKey,
            normalizedOutlookIdentity(bestSender ?? ""),
            bestTimestamp ?? ""
        ]

        let identity = identityParts[2].isEmpty
            ? nil
            : "reading-pane|" +
                identityParts.joined(separator: "|")

        return OutlookMessageContext(
            subject: bestSubject.subject,
            sender: bestSender,
            identity: identity,
            isNewOutlookReadingPane: sawNewOutlookSignal
        )
    }


    private func appendAccessibilityChildren(
        of element: AXUIElement,
        depth: Int,
        to queue: inout [(element: AXUIElement, depth: Int)],
        limit: Int
    ) {
        var childrenValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        ) == .success,
        let children = childrenValue as? [AXUIElement] {
            for child in children.prefix(limit) {
                queue.append((child, depth + 1))
            }
        }
    }


    private func accessibilityFrame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
        AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success,
        let positionValue,
        let sizeValue,
        CFGetTypeID(positionValue) == AXValueGetTypeID(),
        CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = unsafeBitCast(
            positionValue,
            to: AXValue.self
        )
        let sizeAXValue = unsafeBitCast(
            sizeValue,
            to: AXValue.self
        )

        var point = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(
            positionAXValue,
            .cgPoint,
            &point
        ),
        AXValueGetValue(
            sizeAXValue,
            .cgSize,
            &size
        ) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }


    private func outlookReadingPaneTimestamp(
        from rawValue: String
    ) -> String? {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        guard !value.isEmpty,
              value.count <= 120,
              !lower.hasPrefix("to:"),
              !lower.hasPrefix("cc:"),
              !lower.hasPrefix("bcc:")
        else {
            return nil
        }

        let patterns = [
            #"\b(today|yesterday)\s+at\s+\d{1,2}:\d{2}\s*(am|pm)\b"#,
            #"\b\d{1,2}/\d{1,2}/\d{2,4}(?:\s+at)?\s+\d{1,2}:\d{2}\s*(am|pm)\b"#,
            #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},?\s+\d{4}(?:\s+at)?\s+\d{1,2}:\d{2}\s*(am|pm)\b"#,
            #"\b(mon|tue|wed|thu|fri|sat|sun)[a-z]*,?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:,?\s+\d{4})?(?:\s+at)?\s+\d{1,2}:\d{2}\s*(am|pm)\b"#
        ]

        for pattern in patterns {
            if let range = value.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) {
                return normalizedOutlookIdentity(
                    String(value[range])
                )
            }
        }

        return nil
    }


    private func isNewOutlookStructuralHeaderLabel(
        _ rawValue: String
    ) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()

        let exact = Set([
            "message header",
            "message header expanded",
            "message header collapsed",
            "message body",
            "message actions",
            "header",
            "email header",
            "mail header"
        ])

        if exact.contains(value) {
            return true
        }

        return value.hasPrefix("message header,") ||
            value.hasPrefix("message header ")
    }

    private func outlookReadingPaneVisibleSubject(
        from rawValue: String
    ) -> String? {
        let value = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty,
              !isOutlookHeaderMetadataText(value),
              !isOutlookCopilotOrSummaryText(value),
              !isNewOutlookStructuralHeaderLabel(value)
        else {
            return nil
        }

        let lower = value.lowercased()
        let rejectedExact = Set([
            "summarize",
            "reply",
            "reply all",
            "forward",
            "more",
            "more actions",
            "mark read",
            "mark unread",
            "learn more",
            "general",
            "focused",
            "other"
        ])

        if rejectedExact.contains(lower) ||
            lower.hasPrefix("recipients:") ||
            lower.contains("recipients: to:") ||
            lower.hasPrefix("to:") ||
            lower.hasPrefix("cc:") ||
            lower.hasPrefix("bcc:") ||
            lower.hasPrefix("from:") ||
            lower.hasPrefix("sent:") ||
            lower.contains("show details") ||
            lower.hasPrefix("today at ") ||
            lower.hasPrefix("yesterday at ") ||
            lower.contains("sensitivity label") {
            return nil
        }

        return sanitizedOutlookSubject(
            value,
            allowSenderLikeSubject: true
        )
    }


    private func isExplicitOutlookSenderText(
        _ rawValue: String
    ) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        if lower.hasPrefix("from:") ||
            lower.contains(" via ") {
            return true
        }

        let emailPattern =
            #"[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"#
        if value.range(
            of: emailPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }

        return value.contains("<") &&
            value.contains(">")
    }


    private func isLikelyOutlookSenderDisplay(
        _ rawValue: String
    ) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        guard !value.isEmpty,
              value.count <= 200,
              !isOutlookHeaderMetadataText(value),
              !looksLikeURL(value),
              !looksLikeTimestampOrDate(value),
              !isOutlookNavigationChrome(value),
              !isOutlookMessageGroupHeader(value)
        else {
            return false
        }

        if lower.hasPrefix("recipients:") ||
            lower.hasPrefix("to:") ||
            lower.hasPrefix("cc:") ||
            lower.hasPrefix("bcc:") ||
            lower.hasPrefix("sent:") ||
            lower.hasPrefix("subject:") ||
            lower.contains("show details") ||
            lower.contains("message preview:") ||
            lower.contains("sensitivity label") {
            return false
        }

        if lower.hasPrefix("re:") ||
            lower.hasPrefix("fw:") ||
            lower.hasPrefix("fwd:") {
            return false
        }

        if isExplicitOutlookSenderText(value) {
            return true
        }

        let words = value.split(whereSeparator: {
            $0.isWhitespace
        })
        guard (1...24).contains(words.count) else {
            return false
        }

        // Display names and distribution lists frequently contain letters,
        // digits, ampersands, apostrophes, dashes, dots, and parentheses.
        // Sentence-like/body text is intentionally rejected.
        if value.hasSuffix(".") ||
            value.hasSuffix("!") ||
            value.hasSuffix("?") {
            return false
        }

        let allowed = CharacterSet
            .letters
            .union(.decimalDigits)
            .union(.whitespaces)
            .union(CharacterSet(
                charactersIn: "@&'’.-_()+,/<>…"
            ))

        return value.unicodeScalars.allSatisfy {
            allowed.contains($0)
        }
    }


    private func outlookReadingPaneVisibleSender(
        from rawValue: String
    ) -> String? {
        let value = rawValue
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let sender = sanitizedOutlookSender(value),
              isLikelyReadingPaneHeaderSender(sender, rawValue: value)
        else {
            return nil
        }

        let lower = value.lowercased()
        if lower == "summarize" ||
            lower == "reply" ||
            lower == "reply all" ||
            lower == "forward" ||
            lower == "learn more" ||
            lower == "general" ||
            lower.hasPrefix("today at ") ||
            lower.hasPrefix("yesterday at ") {
            return nil
        }

        if isLikelyOutlookSenderDisplay(sender) {
            return sender
        }

        return nil
    }


    private func outlookSenderFromLabeledHeader(
        _ rawValue: String
    ) -> String? {
        let normalized = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        let prefixes = [
            "from:",
            "organizer:",
            "meeting organizer:",
            "organized by:",
            "organised by:",
            "invited by:"
        ]

        for line in normalized.components(
            separatedBy: "\n"
        ) {
            let trimmed = line.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let lower = trimmed.lowercased()

            guard let prefix = prefixes.first(
                where: { lower.hasPrefix($0) }
            ) else {
                continue
            }

            var value = String(
                trimmed.dropFirst(prefix.count)
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let terminators = [
                " sent:",
                " sent on:",
                " sent at:",
                " to:",
                " cc:",
                " bcc:",
                " date:",
                " time:",
                " subject:",
                " response:"
            ]

            let lowerValue = value.lowercased()
            if let end = terminators
                .compactMap({
                    lowerValue.range(
                        of: $0
                    )?.lowerBound
                })
                .min() {
                value = String(
                    value[..<end]
                ).trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }

            if let sender =
                sanitizedOutlookSender(value) {
                return sender
            }
        }

        return nil
    }

    private func outlookReadingPaneSender(
        from rawValue: String,
        allowPlainValue: Bool = false
    ) -> String? {
        let normalized = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        if let labeledSender =
            outlookSenderFromLabeledHeader(
                normalized
            ) {
            return labeledSender
        }

        guard allowPlainValue,
              !isOutlookHeaderMetadataText(normalized)
        else {
            return nil
        }

        let cleaned = normalized
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitizedOutlookSender(cleaned)
    }


    private func isLikelyReadingPaneHeaderSender(
        _ sender: String,
        rawValue: String
    ) -> Bool {
        let lower = rawValue.lowercased()

        if isOutlookHeaderMetadataText(rawValue) ||
            lower.contains("message preview:") ||
            lower.hasPrefix("recipients:") ||
            lower.contains("recipients: to:") ||
            lower.hasPrefix("to:") ||
            lower.hasPrefix("cc:") ||
            lower.hasPrefix("bcc:") ||
            lower.hasPrefix("sent:") ||
            lower.hasPrefix("subject:") ||
            lower.contains("show details") ||
            lower.contains("sensitivity label") {
            return false
        }

        if looksLikeTimestampOrDate(sender) ||
            isOutlookMessageGroupHeader(sender) ||
            isOutlookNavigationChrome(sender) {
            return false
        }

        let words = sender.split(whereSeparator: { $0.isWhitespace })
        return (1...24).contains(words.count) &&
            sender.count <= 200 &&
            isLikelyOutlookSenderDisplay(sender)
    }


    private func isOutlookMessageListComposite(_ rawValue: String) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()

        if lower.contains("message preview:") {
            return true
        }

        let timePattern = #"\b\d{1,2}:\d{2}\s?(am|pm)\b"#
        let hasMessageListTime = lower.range(
            of: timePattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        // Message-list AX descriptions often concatenate subject, time,
        // preview, flags, and sender into one long value.
        return hasMessageListTime &&
            (value.contains(",") || lower.contains("preview"))
    }


    private func isOutlookCopilotOrSummaryText(_ rawValue: String) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if value == "copilot" ||
            value == "summary" ||
            value == "summary by copilot" ||
            value.hasPrefix("summary by copilot ") ||
            value.hasPrefix("copilot summary") {
            return true
        }

        return value.contains("generated by copilot") ||
            value.contains("summarized by copilot")
    }


    private func isOutlookHeaderMetadataText(
        _ rawValue: String
    ) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        let lower = value.lowercased()

        guard !lower.isEmpty else {
            return true
        }

        let prefixes = [
            "sent:",
            "sent on:",
            "sent at:",
            "sent date:",
            "received:",
            "received on:",
            "received at:",
            "received date:",
            "date:",
            "time:",
            "to:",
            "cc:",
            "bcc:",
            "from:",
            "recipients:",
            "reply-to:",
            "organizer:",
            "meeting organizer:",
            "organized by:",
            "organised by:",
            "invited by:",
            "sensitivity label:",
            "importance:",
            "priority:"
        ]

        if prefixes.contains(
            where: { lower.hasPrefix($0) }
        ) {
            return true
        }

        if lower.hasPrefix("today at ") ||
            lower.hasPrefix("yesterday at ") {
            return true
        }

        let exact = Set([
            "available",
            "busy",
            "away",
            "offline",
            "do not disturb",
            "in a meeting",
            "be right back",
            "appear away",
            "show details",
            "external",
            "external sender",
            "guest",
            "internal",
            "outside your organization",
            "unverified sender",
            "organizer",
            "meeting organizer",
            "organized by",
            "organised by",
            "invited by",
            "accept",
            "accepted",
            "tentative",
            "decline",
            "declined",
            "propose new time",
            "response options",
            "respond",
            "send response",
            "do not send a response",
            "no response required"
        ])

        if exact.contains(lower) {
            return true
        }

        let sentPatterns = [
            #"^sent\s+(on|at)\b"#,
            #"^received\s+(on|at)\b"#,
            #"^(today|yesterday)\s+at\s+\d{1,2}:\d{2}\s*(am|pm)\b"#,
            #"^\w{3,9}\s+\d{1,2},?\s+\d{4}\s+at\s+\d{1,2}:\d{2}\s*(am|pm)\b"#
        ]

        return sentPatterns.contains {
            lower.range(
                of: $0,
                options: .regularExpression
            ) != nil
        }
    }

    private func outlookSubjectFromMetadataText(_ rawValue: String) -> String? {
        let normalized = rawValue
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return nil }

        // Preserve line boundaries first; this avoids accidentally swallowing
        // From/Sent/To metadata that follows the subject.
        for line in normalized.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            guard lower.hasPrefix("subject:") else { continue }

            let value = String(trimmed.dropFirst("subject:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let subject = sanitizedOutlookSubject(
                    value,
                    allowSenderLikeSubject: true
                ) {
                return subject
            }
        }

        // Some Accessibility values flatten message metadata onto one line.
        // Capture Subject: text until the next known mail-header marker.
        let lower = normalized.lowercased()
        guard let subjectRange = lower.range(of: "subject:") else {
            return nil
        }

        var subjectText = String(normalized[subjectRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let terminators = [
            " from:",
            " sent:",
            " to:",
            " cc:",
            " bcc:",
            " sensitivity label:"
        ]

        let lowerSubject = subjectText.lowercased()
        if let end = terminators
            .compactMap({ lowerSubject.range(of: $0)?.lowerBound })
            .min() {
            subjectText = String(subjectText[..<end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return sanitizedOutlookSubject(
            subjectText,
            allowSenderLikeSubject: true
        )
    }


    private func outlookSelectedRowIdentityFromSelection(
        in root: AXUIElement
    ) -> String? {
        for selected in selectedAccessibilityRows(in: root) {
            guard isOutlookMessageSelectionCandidate(
                selected
            ) else {
                continue
            }

            if let identity =
                outlookSelectedRowIdentity(selected) {
                return identity
            }
        }

        return nil
    }

    private func outlookSelectedRowMessage(
        in root: AXUIElement
    ) -> OutlookMessageContext? {
        for selected in selectedAccessibilityRows(in: root) {
            guard isOutlookMessageSelectionCandidate(selected),
                  let subject = outlookSubjectFromSelectedElement(
                      selected,
                      requireStrongSignal: false
                  )
            else {
                continue
            }

            let sender =
                outlookSenderFromElement(selected) ??
                outlookSenderCandidate(
                    in: selected,
                    excludingSubject: subject
                )

            return OutlookMessageContext(
                subject: subject,
                sender: sender,
                identity: outlookSelectedRowIdentity(selected)
            )
        }

        return nil
    }


    private func outlookSelectedRowIdentity(
        _ root: AXUIElement
    ) -> String? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0
        var values: [String] = []

        while index < queue.count, inspected < 45 {
            let element = queue[index]
            index += 1
            inspected += 1

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXDescriptionAttribute as CFString,
                kAXValueAttribute as CFString,
                kAXIdentifierAttribute as CFString
            ] {
                if let raw = attributeString(element, attribute) {
                    let normalized =
                        normalizedOutlookIdentity(raw)
                    if !normalized.isEmpty,
                       !values.contains(normalized) {
                        values.append(
                            String(normalized.prefix(240))
                        )
                    }
                }
            }

            appendChildren(
                of: element,
                to: &queue,
                limit: 18
            )
        }

        guard !values.isEmpty else { return nil }
        return "ax-row|" +
            values.prefix(12).joined(separator: "|")
    }


    private func outlookSenderCandidate(
        in root: AXUIElement,
        excludingSubject subject: String
    ) -> String? {
        var queue: [AXUIElement] = [root]
        var index = 0
        var inspected = 0
        var candidates: [(value: String, score: Int)] = []
        let subjectKey = normalizedOutlookIdentity(subject)

        while index < queue.count, inspected < 75 {
            let element = queue[index]
            index += 1
            inspected += 1

            let role = attributeString(
                element,
                kAXRoleAttribute as CFString
            )?.lowercased() ?? ""

            for attribute in [
                kAXTitleAttribute as CFString,
                kAXDescriptionAttribute as CFString,
                kAXValueAttribute as CFString
            ] {
                guard let raw = attributeString(element, attribute),
                      let sender = sanitizedOutlookSender(raw)
                else {
                    continue
                }

                let key = normalizedOutlookIdentity(sender)
                guard key != subjectKey,
                      isLikelyOutlookSenderDisplay(sender)
                else {
                    continue
                }

                var score = 20
                if sender.contains("@") { score += 90 }
                if sender.contains("<") &&
                    sender.contains(">") {
                    score += 75
                }
                if sender.lowercased().contains(" via ") {
                    score += 55
                }
                if role.contains("statictext") ||
                    role.contains("text") {
                    score += 20
                }
                if looksLikePersonName(sender) {
                    score += 25
                }

                candidates.append((sender, score))
            }

            appendChildren(
                of: element,
                to: &queue,
                limit: 24
            )
        }

        return candidates.max(by: {
            $0.score < $1.score
        })?.value
    }



    private func outlookSelectedMessageContext(
        pid: pid_t,
        expectedNewOutlookSubject: String? = nil,
        selectionSenderHint: String? = nil,
        selectionIdentityHint: String? = nil
    ) -> OutlookMessageContext? {
        let appElement =
            AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) ==
            AXUIElementGetTypeID()
        else {
            return nil
        }

        let window = unsafeBitCast(
            focusedWindowValue,
            to: AXUIElement.self
        )

        let selectedObjectMessage =
            outlookSelectedMessageFromAppleScript()
        let selectedRowMessage =
            outlookSelectedRowMessage(in: window)
        let selectedRowIdentity =
            outlookSelectedRowIdentityFromSelection(
                in: window
            )

        func resolvedReadingPaneMessage()
            -> OutlookMessageContext? {
            guard let readingPaneMessage =
                outlookReadingPaneMessage(
                    in: window
                )
            else {
                return nil
            }

            let hasNewSelectionHint =
                selectionIdentityHint != nil &&
                selectionIdentityHint !=
                    lastOutlookSelectionHint

            if let expectedNewOutlookSubject {
                let subjectsMatch =
                    outlookSubjectsLikelySame(
                        expectedNewOutlookSubject,
                        readingPaneMessage.subject
                    )

                if !subjectsMatch,
                   let previousMessageKey =
                    lastOutlookMessageKey,
                   outlookMessageKey(
                        readingPaneMessage
                   ) == previousMessageKey,
                   !hasNewSelectionHint {
                    return nil
                }
            }

            let subjectKey =
                normalizedOutlookIdentity(
                    readingPaneMessage.subject
                )

            let matchingObject =
                selectedObjectMessage.flatMap {
                    message in
                    normalizedOutlookIdentity(
                        message.subject
                    ) == subjectKey
                    ? message
                    : nil
                }

            let matchingRow =
                selectedRowMessage.flatMap {
                    message in
                    outlookSubjectsLikelySame(
                        message.subject,
                        readingPaneMessage.subject
                    )
                    ? message
                    : nil
                }

            let hintMatchesSubject =
                expectedNewOutlookSubject.map {
                    outlookSubjectsLikelySame(
                        $0,
                        readingPaneMessage.subject
                    )
                } ?? false

            let sender =
                readingPaneMessage.sender ??
                matchingObject?.sender ??
                matchingRow?.sender ??
                (
                    hintMatchesSubject
                    ? selectionSenderHint
                    : nil
                )

            guard let sender,
                  !sender.isEmpty
            else {
                return nil
            }

            return OutlookMessageContext(
                subject:
                    readingPaneMessage.subject,
                sender: sender,
                identity:
                    mergedOutlookIdentity([
                        matchingObject?.identity,
                        matchingRow?.identity,
                        readingPaneMessage.identity,
                        selectedRowIdentity
                    ]),
                isNewOutlookReadingPane: true
            )
        }

        if outlookUsesNewOutlookLayout(pid: pid) {
            if let readingPane =
                resolvedReadingPaneMessage() {
                return readingPane
            }

            if let selectedObjectMessage,
               let sender =
                selectedObjectMessage.sender,
               !sender.isEmpty,
               !isOutlookHeaderMetadataText(
                    selectedObjectMessage.subject
               ) {
                return OutlookMessageContext(
                    subject:
                        selectedObjectMessage.subject,
                    sender: sender,
                    identity:
                        mergedOutlookIdentity([
                            selectedObjectMessage.identity,
                            selectedRowIdentity
                        ])
                )
            }

            if let selectedRowMessage,
               let sender =
                selectedRowMessage.sender,
               !sender.isEmpty,
               !isOutlookHeaderMetadataText(
                    selectedRowMessage.subject
               ) {
                return OutlookMessageContext(
                    subject:
                        selectedRowMessage.subject,
                    sender: sender,
                    identity:
                        mergedOutlookIdentity([
                            selectedRowMessage.identity,
                            selectedRowIdentity
                        ])
                )
            }

            if let expectedNewOutlookSubject,
               let selectionSenderHint,
               !selectionSenderHint.isEmpty,
               !isOutlookHeaderMetadataText(
                    expectedNewOutlookSubject
               ) {
                return OutlookMessageContext(
                    subject:
                        expectedNewOutlookSubject,
                    sender:
                        selectionSenderHint,
                    identity: nil,
                    isNewOutlookReadingPane: true
                )
            }

            return nil
        }

        if let subject =
            outlookSelectedSubject(pid: pid) {
            let sender =
                outlookSelectedSender(pid: pid) ??
                selectedObjectMessage?.sender ??
                selectedRowMessage?.sender

            if let sender,
               !sender.isEmpty {
                return OutlookMessageContext(
                    subject: subject,
                    sender: sender,
                    identity:
                        mergedOutlookIdentity([
                            selectedObjectMessage?.identity,
                            selectedRowIdentity,
                            selectedRowMessage?.identity
                        ])
                )
            }
        }

        if let readingPane =
            resolvedReadingPaneMessage() {
            return readingPane
        }

        if let expectedNewOutlookSubject,
           let selectionSenderHint,
           !selectionSenderHint.isEmpty {
            return OutlookMessageContext(
                subject:
                    expectedNewOutlookSubject,
                sender:
                    selectionSenderHint,
                identity: nil
            )
        }

        return nil
    }


    private func outlookSelectedSubject(pid: pid_t) -> String? {
        if let subject = outlookSelectedSubjectFromAccessibility(pid: pid) {
            return subject
        }

        // AppleScript is substantially more expensive and synchronous, so use
        // it only when Outlook does not expose the selected message through AX.
        return outlookSelectedSubjectFromAppleScript()
    }

    private func outlookSelectedMessageFromAppleScript()
        -> OutlookMessageContext? {
        let senderDelimiter = "<<<MEMORY_TRAIL_SENDER>>>"
        let idDelimiter = "<<<MEMORY_TRAIL_ID>>>"
        let source = """
        tell application "Microsoft Outlook"
            try
                set selectedItems to selected objects
                if (count of selectedItems) is greater than 0 then
                    set theItem to item 1 of selectedItems
                    set subjectValue to ""
                    set senderValue to ""
                    set messageIDValue to ""

                    try
                        set subjectValue to subject of theItem as text
                    end try

                    if subjectValue is "" then
                        set subjectValue to "(No Subject)"
                    end if

                    try
                        set senderObject to sender of theItem
                        try
                            set senderValue to name of senderObject as text
                        on error
                            set senderValue to senderObject as text
                        end try
                    end try

                    try
                        set messageIDValue to id of theItem as text
                    end try

                    return subjectValue & "<<<MEMORY_TRAIL_SENDER>>>" & senderValue & "<<<MEMORY_TRAIL_ID>>>" & messageIDValue
                end if
            end try
        end tell
        return ""
        """

        guard let script = NSAppleScript(source: source) else {
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil,
              let raw = result.stringValue,
              !raw.isEmpty
        else {
            return nil
        }

        let idParts = raw.components(separatedBy: idDelimiter)
        let messageID = idParts.count > 1
            ? normalizedOutlookIdentity(
                idParts.dropFirst().joined(separator: idDelimiter)
            )
            : ""

        let messageParts = (idParts.first ?? "")
            .components(separatedBy: senderDelimiter)

        guard let subjectPart = messageParts.first,
              let subject = sanitizedOutlookSubject(
                subjectPart,
                allowSenderLikeSubject: true
              )
        else {
            return nil
        }

        let sender: String?
        if messageParts.count > 1 {
            sender = sanitizedOutlookSender(
                messageParts.dropFirst().joined(separator: senderDelimiter)
            )
        } else {
            sender = nil
        }

        let identity = messageID.isEmpty
            ? nil
            : "outlook-id|\(messageID)"

        return OutlookMessageContext(
            subject: subject,
            sender: sender,
            identity: identity
        )
    }


    private func outlookSelectedSubjectFromAppleScript() -> String? {
        outlookSelectedMessageFromAppleScript()?.subject
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
        outlookSelectedMessageFromAppleScript()?.sender
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

        if let labeledSender =
            outlookSenderFromLabeledHeader(
                normalized
            ) {
            return labeledSender
        }

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

    private func sanitizedOutlookSender(
        _ rawValue: String
    ) -> String? {
        var sender = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let senderPrefixes = [
            "from:",
            "organizer:",
            "meeting organizer:",
            "organized by:",
            "organised by:",
            "invited by:"
        ]

        if let prefix = senderPrefixes.first(
            where: {
                sender.lowercased().hasPrefix($0)
            }
        ) {
            sender = String(
                sender.dropFirst(prefix.count)
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        let presenceSuffixes = [
            ", available",
            ", busy",
            ", away",
            ", offline",
            ", do not disturb",
            ", in a meeting",
            ", be right back",
            ", appear away"
        ]

        let senderLower = sender.lowercased()
        if let suffix = presenceSuffixes.first(
            where: {
                senderLower.hasSuffix($0)
            }
        ) {
            sender = String(
                sender.dropLast(suffix.count)
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        guard sender.count >= 1,
              sender.count <= 200
        else {
            return nil
        }

        guard !looksLikeURL(sender),
              !looksLikeTimestampOrDate(sender)
        else {
            return nil
        }

        let lower = sender.lowercased()
        let generic = Set([
            "microsoft outlook",
            "outlook",
            "inbox",
            "mail",
            "sender",
            "from",
            "unknown"
        ])

        guard !generic.contains(lower),
              !lower.hasPrefix("recipients:"),
              !lower.hasPrefix("to:"),
              !lower.hasPrefix("cc:"),
              !lower.hasPrefix("bcc:"),
              !lower.hasPrefix("sent:")
        else {
            return nil
        }

        return sender
    }

    private func outlookSelectedSubjectFromAccessibility(
        pid: pid_t
    ) -> String? {
        let appElement =
            AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue,
        CFGetTypeID(focusedWindowValue) ==
            AXUIElementGetTypeID()
        else {
            return nil
        }

        let window = unsafeBitCast(
            focusedWindowValue,
            to: AXUIElement.self
        )

        if let subject =
            outlookSelectedMessageSubject(
                in: window
            ) {
            return subject
        }

        if let focused =
            focusedAccessibilityElement(
                in: appElement
            ),
           let row =
            nearestAccessibilityRow(
                from: focused
            ),
           let subject =
            outlookSubjectFromSelectedElement(
                row,
                requireStrongSignal: false
            ) {
            return subject
        }

        if let windowTitle =
            attributeString(
                window,
                kAXTitleAttribute as CFString
            ),
           let subject =
            sanitizedOutlookSubject(
                windowTitle
            ) {
            return subject
        }

        return nil
    }


    private func outlookSelectedMessageSubject(in root: AXUIElement) -> String? {
        outlookSelectedRowMessage(in: root)?.subject
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
                guard !isOutlookHeaderMetadataText(raw) else { continue }
                guard !isOutlookNavigationChrome(raw) else { continue }
                guard !isOutlookSenderOnlyValue(raw) else { continue }
                guard !isOutlookMessageGroupHeader(raw) else { continue }
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

    private func sanitizedOutlookSubject(
        _ rawValue: String,
        allowSenderLikeSubject: Bool = false
    ) -> String? {
        var value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let initialLower = value.lowercased()
        if isOutlookHeaderMetadataText(value) ||
            isOutlookNavigationChrome(value) ||
            (!allowSenderLikeSubject &&
                isOutlookSenderOnlyValue(value)) ||
            isOutlookMessageGroupHeader(value) ||
            isOutlookMessageListComposite(value) {
            return nil
        }

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

    private func isOutlookSenderOnlyValue(_ rawValue: String) -> Bool {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !value.isEmpty else { return false }

        let emailPattern = #"^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$"#
        return value.range(
            of: emailPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isOutlookMessageGroupHeader(_ rawValue: String) -> Bool {
        let value = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !value.isEmpty else { return false }

        let normalized = value
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        let relativeGroups = [
            "today",
            "yesterday",
            "this week",
            "last week",
            "older",
            "earlier this month",
            "last month"
        ]

        let weekdays = [
            "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "sunday"
        ]

        let hasExpansionState =
            normalized.hasSuffix(" expanded") ||
            normalized.hasSuffix(" collapsed")

        if hasExpansionState {
            let base = normalized
                .replacingOccurrences(of: " expanded", with: "")
                .replacingOccurrences(of: " collapsed", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if relativeGroups.contains(base) || weekdays.contains(base) {
                return true
            }

            let dateHeaderPattern = #"^[a-z]+\s+\d{1,2}(\s+\d{4})?$"#
            if base.range(
                of: dateHeaderPattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil {
                return true
            }
        }

        return relativeGroups.contains(normalized) || weekdays.contains(normalized)
    }

    private func isOutlookNavigationChrome(_ rawValue: String) -> Bool {
        let normalized = rawValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ";", with: " ")
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard !normalized.isEmpty else { return true }

        let exactChrome = Set([
            "search",
            "search field",
            "search box",
            "title bar",
            "toolbar",
            "message header",
            "message header expanded",
            "message header collapsed",
            "message body",
            "message actions",
            "focused inbox",
            "other inbox",
            "focused inbox selected",
            "focused inbox unselected",
            "other inbox selected",
            "other inbox unselected",
            "focused selected",
            "focused unselected",
            "other selected",
            "other unselected"
        ])

        if exactChrome.contains(normalized) {
            return true
        }

        // New Outlook exposes its Focused/Other inbox segmented control through
        // Accessibility. Combined labels can look like:
        // "Focused inbox selected, Other inbox unselected".
        let mentionsFocusedInbox = normalized.contains("focused inbox")
        let mentionsOtherInbox = normalized.contains("other inbox")
        let exposesSelectionState =
            normalized.contains(" selected") ||
            normalized.contains(" unselected")

        if exposesSelectionState && (mentionsFocusedInbox || mentionsOtherInbox) {
            return true
        }

        let chromePhrases = [
            "search this mailbox",
            "search current mailbox",
            "title bar",
            "sort messages",
            "filter messages",
            "filter by",
            "arrange by",
            "message list options",
            "select all messages",
            "toggle focused inbox"
        ]

        return chromePhrases.contains { normalized.contains($0) }
    }

    private func isOutlookMessageSelectionCandidate(_ element: AXUIElement) -> Bool {
        let role = attributeString(
            element,
            kAXRoleAttribute as CFString
        )?.lowercased() ?? ""

        // New Outlook marks segmented controls and navigation chrome as
        // selected children. Never treat those controls as selected email rows.
        let rejectedRoleFragments = [
            "button",
            "radiobutton",
            "checkbox",
            "tab",
            "toolbar",
            "menu",
            "popup",
            "combobox",
            "slider",
            "switch"
        ]

        if rejectedRoleFragments.contains(where: { role.contains($0) }) {
            return false
        }

        for attribute in [
            kAXTitleAttribute as CFString,
            kAXDescriptionAttribute as CFString,
            kAXValueAttribute as CFString
        ] {
            if let raw = attributeString(element, attribute),
               isOutlookNavigationChrome(raw) {
                return false
            }
        }

        // Message selections are normally exposed as a row/cell/list item.
        // Keep groups as a compatibility fallback for Classic Outlook and
        // New Outlook builds that wrap a message row in AXGroup.
        return role.isEmpty ||
            role.contains("row") ||
            role.contains("cell") ||
            role.contains("outline") ||
            role.contains("list") ||
            role.contains("group") ||
            role.contains("statictext")
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
            "ciscospark",
            "signal",
            "whatsapp",
            "telegram",
            "mattermost",
            "googlechat",
            "google.chat",
            "mobilesms",
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
            windowContext.title,
            windowContext.selectedContent?.title,
            windowContext.focusedContent?.title
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

        guard subject.count >= 1, subject.count <= 250 else { return false }
        guard !isOutlookHeaderMetadataText(subject) else { return false }

        let exactGeneric = Set([
            "search",
            "search field",
            "search box",
            "title bar",
            "toolbar",
            "message header",
            "message header expanded",
            "message header collapsed",
            "message body",
            "message actions",
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

        let mailboxPrefixes = [
            "inbox •",
            "inbox -",
            "inbox —",
            "mail •",
            "microsoft outlook •"
        ]
        if mailboxPrefixes.contains(where: { lower.hasPrefix($0) }) {
            return false
        }

        if lower.hasPrefix("recipients:") ||
            lower.contains("recipients: to:") ||
            lower.hasPrefix("to:") ||
            lower.hasPrefix("cc:") ||
            lower.hasPrefix("bcc:") ||
            lower.hasPrefix("from:") ||
            lower.hasPrefix("sent:") ||
            lower.contains("show details") {
            return false
        }

        if isOutlookNavigationChrome(subject) { return false }
        if isOutlookSenderOnlyValue(subject) { return false }
        if isOutlookMessageGroupHeader(subject) { return false }
        if isOutlookMessageListComposite(subject) { return false }
        if lower.contains("unread message") { return false }
        if lower.hasPrefix("from ") && lower.contains(" to ") && lower.contains(" events") { return false }
        if lower.contains("copyright ©") || lower.contains("all rights reserved") { return false }
        if lower.contains("one apple park way") { return false }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.") { return false }
        if lower.contains("urldefense.com/") || lower.contains("safelinks.protection.outlook.com/") { return false }
        if lower.contains("outlook.office.com/") { return false }
        if isOutlookCopilotOrSummaryText(subject) { return false }
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

        while index < queue.count, inspected < 1_500 {
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
