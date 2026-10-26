#if os(iOS)
import AppIntents

struct LogAppOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Log App Open"
    static var description = IntentDescription(
        "Adds an app-open event to your Recall timeline. Use this action from a Shortcuts personal automation triggered when an app is opened."
    )

    static var openAppWhenRun = false

    @Parameter(title: "App Name", description: "The app name to record, for example Safari, Teams, or Outlook.")
    var appName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(.$appName) opened")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .result(dialog: "Enter an app name to log.")
        }

        try RecallSharedStore.enqueue(
            RecallPendingItem(
                title: "\(cleaned) opened",
                body: "Opened on iPhone.",
                sourceApp: cleaned,
                sourceKind: .appActivity
            )
        )

        return .result(dialog: "Logged \(cleaned) in Recall.")
    }
}
#endif
