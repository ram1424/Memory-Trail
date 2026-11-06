import SwiftUI

struct OnboardingView: View {
    @Environment(RecallPreferences.self) private var preferences
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    var body: some View {
        @Bindable var preferences = preferences

        VStack(spacing: 0) {
            HStack {
                Label("Memory Trails", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("Mac App Store Edition")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider()

            Group {
                switch page {
                case 0:
                    welcomePage
                case 1:
                    capturePage(preferences: preferences)
                case 2:
                    featuresPage
                default:
                    privacyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Back") {
                    page = max(0, page - 1)
                }
                .disabled(page == 0)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(
                                index == page
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.25)
                            )
                            .frame(width: 7, height: 7)
                    }
                }

                Spacer()

                Button(page == 3 ? "Get Started" : "Continue") {
                    if page == 3 {
                        hasCompletedOnboarding = true
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(
            LinearGradient(
                colors: [
                    MemoryTrailPalette.canvasTop,
                    MemoryTrailPalette.canvasBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var welcomePage: some View {
        pageView(
            icon: "clock.arrow.circlepath",
            title: "Remember your workday",
            subtitle:
                "Build a private, searchable history from activity available inside Apple’s App Sandbox."
        ) {
            row(
                "macwindow",
                "Application switches",
                "See when you moved between Outlook, Teams, browsers, Office apps, and other applications."
            )
            row(
                "magnifyingglass",
                "Ask Memory Trails",
                "Search locally stored activity by time, application, copied text, notes, and projects."
            )
            row(
                "chart.bar.fill",
                "Insights",
                "Review app usage patterns and activity trends from your local history."
            )
        }
    }

    private func capturePage(
        preferences: RecallPreferences
    ) -> some View {
        @Bindable var preferences = preferences

        return pageView(
            icon: "record.circle",
            title: "Choose what to remember",
            subtitle:
                "The App Store edition uses sandbox-compatible capture only."
        ) {
            Toggle(
                "Remember application switches",
                isOn: $preferences.captureAppActivity
            )

            Toggle(
                "Remember copied text",
                isOn: $preferences.captureClipboard
            )

            Text(
                "Clipboard Capture is OFF by default. If you enable it, copied text is stored only in your local Memory Trails history."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            row(
                "accessibility",
                "No cross-app Accessibility inspection",
                "This edition does not read Outlook subjects, Teams conversation titles, browser tabs, or other apps’ focused-window content."
            )
        }
    }

    private var featuresPage: some View {
        pageView(
            icon: "sparkles.rectangle.stack",
            title: "Your Memory Trails tools",
            subtitle:
                "The core organization and recall experience remains available."
        ) {
            row("clock.fill", "Today", "Review captured activity chronologically.")
            row("chart.xyaxis.line", "Insights", "See top apps and local activity patterns.")
            row("sparkles", "Ask Memory Trails", "Search local history without sending it to a cloud search service.")
            row("star.fill", "Favorites & manual memories", "Save important moments and add notes.")
        }
    }

    private var privacyPage: some View {
        pageView(
            icon: "lock.shield.fill",
            title: "Private by design",
            subtitle:
                "The Mac App Store edition is built around Apple’s App Sandbox."
        ) {
            row(
                "shippingbox.fill",
                "Sandboxed",
                "Memory Trails can access its own container and files you explicitly choose through standard macOS dialogs."
            )
            row(
                "internaldrive.fill",
                "Stored locally",
                "Your captured timeline stays on this Mac. There is no Memory Trails cloud timeline."
            )
            row(
                "arrow.triangle.2.circlepath",
                "App Store updates",
                "Updates for this edition are delivered by the Mac App Store."
            )
        }
    }

    private func pageView<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(20)
            .background(
                MemoryTrailPalette.elevated,
                in: RoundedRectangle(
                    cornerRadius: 18,
                    style: .continuous
                )
            )

            Spacer()
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 36)
        .frame(maxWidth: 900)
    }

    private func row(
        _ icon: String,
        _ title: String,
        _ text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}
