#if os(macOS)
import AppKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MacCaptureCoordinator {
    static let shared = MacCaptureCoordinator()

    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored private var clipboardTimer: Timer?
    @ObservationIgnored private weak var context: ModelContext?
    @ObservationIgnored private var lastClipboardChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private var lastApplicationBundleID = ""
    @ObservationIgnored private var lastApplicationLoggedAt = Date.distantPast

    private(set) var accessibilityTrusted = false

    var hasAccessibilityPermission: Bool { false }

    func start(context: ModelContext) {
        self.context = context
        startAppActivityCapture()
        startClipboardCapture()

        if let application = NSWorkspace.shared.frontmostApplication {
            capture(application: application)
        }
    }

    func stop() {
        if let appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appObserver)
            self.appObserver = nil
        }

        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    func requestAccessibilityPermission() {}
    func openAccessibilitySettings() {}

    func refreshAccessibilityStatus() {
        accessibilityTrusted = false
    }

    func clearRuntimeCache() {
        lastApplicationBundleID = ""
        lastApplicationLoggedAt = .distantPast
        lastClipboardChangeCount = NSPasteboard.general.changeCount
    }

    private func startAppActivityCapture() {
        guard appObserver == nil else { return }

        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication else {
                return
            }

            Task { @MainActor in
                self?.capture(application: application)
            }
        }
    }

    private func capture(application: NSRunningApplication) {
        let preferences = RecallPreferences.shared
        guard !preferences.capturePaused,
              preferences.captureAppActivity
        else { return }

        let bundleID = application.bundleIdentifier ?? ""
        guard !bundleID.isEmpty,
              bundleID != Bundle.main.bundleIdentifier,
              !preferences.isExcluded(bundleID: bundleID)
        else { return }

        let now = Date()
        if bundleID == lastApplicationBundleID,
           now.timeIntervalSince(lastApplicationLoggedAt) < 1.0 {
            return
        }

        lastApplicationBundleID = bundleID
        lastApplicationLoggedAt = now

        let name = application.localizedName ?? "Application"

        context?.insert(
            MemoryItem(
                title: "Opened \(name)",
                sourceApp: name,
                sourceBundleID: bundleID,
                sourceKind: .appActivity
            )
        )
        try? context?.save()
    }

    private func startClipboardCapture() {
        clipboardTimer?.invalidate()

        let timer = Timer.scheduledTimer(
            withTimeInterval: 2.5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pollClipboard()
            }
        }
        timer.tolerance = 0.60
        clipboardTimer = timer
    }

    private func pollClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = pasteboard.changeCount

        let preferences = RecallPreferences.shared
        guard !preferences.capturePaused,
              preferences.captureClipboard
        else { return }

        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.count <= 20_000
        else { return }

        let active = NSWorkspace.shared.frontmostApplication
        let bundleID = active?.bundleIdentifier ?? ""
        guard bundleID != Bundle.main.bundleIdentifier,
              !preferences.isExcluded(bundleID: bundleID)
        else { return }

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
        try? context?.save()
    }
}
#endif
