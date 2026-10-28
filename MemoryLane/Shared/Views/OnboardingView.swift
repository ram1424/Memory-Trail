import AppKit
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var captureCoordinator = MacCaptureCoordinator.shared

    private let pageCount = 6

    private let primaryText = Color.white
    private let secondaryText = Color.white.opacity(0.72)
    private let tertiaryText = Color.white.opacity(0.52)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.09, blue: 0.22),
                    Color(red: 0.13, green: 0.25, blue: 0.55),
                    Color(red: 0.48, green: 0.30, blue: 0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("\(page + 1) of \(pageCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(secondaryText)

                    Spacer()

                    if page > 0 && page < pageCount - 1 {
                        Text(pageTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tertiaryText)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)

                Group {
                    switch page {
                    case 0:
                        welcomePage
                    case 1:
                        timelinePage
                    case 2:
                        askPage
                    case 3:
                        capturePage
                    case 4:
                        privacyAndControlPage
                    default:
                        accessibilityPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
            .frame(width: 790, height: 610)
            .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(radius: 40, y: 20)
            .padding(28)
        }
        .onAppear {
            captureCoordinator.refreshAccessibilityStatus()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            if page == pageCount - 1 {
                captureCoordinator.refreshAccessibilityStatus()
            }
        }
    }

    private var pageTitle: String {
        switch page {
        case 1: "Timeline"
        case 2: "Ask Memory Lane"
        case 3: "Capture & Files"
        case 4: "Privacy & Controls"
        case 5: "Accessibility"
        default: "Welcome"
        }
    }

    private var welcomePage: some View {
        HStack(spacing: 48) {
            VStack(spacing: 17) {
                Image("OnboardingIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

                Text("Welcome to\nMemory Lane")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)

                Text("A private, searchable history of the work you do on your Mac.")
                    .font(.title3)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            VStack(alignment: .leading, spacing: 20) {
                benefitRow(
                    icon: "clock.arrow.circlepath",
                    title: "Retrace your work",
                    text: "See your day as a chronological timeline of apps, pages, messages, files, and copied text.",
                    tint: .blue
                )
                benefitRow(
                    icon: "sparkles",
                    title: "Ask Memory Lane",
                    text: "Search your local history by time, app, filename, subject, page, or what happened before or after.",
                    tint: .purple
                )
                benefitRow(
                    icon: "lock.shield.fill",
                    title: "Local-first privacy",
                    text: "Your timeline stays on your Mac, with pause controls and exclusions for sensitive apps.",
                    tint: .green
                )
            }
            .frame(maxWidth: 360)
        }
        .padding(40)
    }

    private var timelinePage: some View {
        VStack(spacing: 16) {
            pageHeading(
                title: "Your Workday, in Order",
                subtitle: "Timeline turns captured activity into a clean chronological history without summarizing or rewriting what you viewed."
            )

            HStack(spacing: 10) {
                featurePill("All", icon: "line.3.horizontal.decrease.circle", selected: true)
                featurePill("Web", icon: "safari")
                featurePill("Email", icon: "envelope")
                featurePill("Chat", icon: "bubble.left.and.bubble.right")
                featurePill("Files", icon: "folder")
                featurePill("Clipboard", icon: "doc.on.clipboard")
                featurePill("Favorites", icon: "star")
            }

            VStack(spacing: 0) {
                sampleTimelineRow(
                    time: "10:42 AM",
                    app: "Safari",
                    detail: "Memory Lane · Releases",
                    icon: "safari"
                )
                Divider()
                sampleTimelineRow(
                    time: "10:18 AM",
                    app: "Microsoft Outlook",
                    detail: "RE: Project Update",
                    icon: "envelope.fill"
                )
                Divider()
                sampleTimelineRow(
                    time: "9:54 AM",
                    app: "Finder",
                    detail: "Project Phoenix.xlsx",
                    icon: "folder.fill"
                )
            }
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .frame(maxWidth: 660)

            HStack(spacing: 14) {
                compactFeature(icon: "waveform.path.ecg", title: "Activity Overview", text: "See busy and quiet periods across the day.")
                compactFeature(icon: "rectangle.righthalf.inset.filled", title: "Details Panel", text: "Show or hide details for the selected activity.")
                compactFeature(icon: "rectangle.compress.vertical", title: "View Density", text: "Switch between Compact and Comfortable views.")
            }
            .frame(maxWidth: 690)
        }
        .padding(34)
    }

    private var askPage: some View {
        VStack(spacing: 18) {
            pageHeading(
                title: "Ask Memory Lane",
                subtitle: "Use natural-language local search to find captured activity without scrolling through your entire day."
            )

            VStack(spacing: 12) {
                askExample("What was I doing around 10:30 AM?", answer: "Find activity captured near that time.")
                askExample("What did I view before opening Teams?", answer: "Look backward from a Teams event.")
                askExample("Find the Outlook email I viewed today", answer: "Match captured Outlook subject lines.")
                askExample("Find the budget spreadsheet from yesterday", answer: "Search filenames, file paths, apps, and dates.")
            }
            .frame(maxWidth: 650)

            HStack(spacing: 16) {
                compactFeature(icon: "clock", title: "Time-aware", text: "Today, yesterday, and specific times.")
                compactFeature(icon: "app.badge", title: "App-aware", text: "Safari, Outlook, Teams, Finder, Office, and more.")
                compactFeature(icon: "arrow.left.arrow.right", title: "Before & After", text: "Trace what happened around another activity.")
                compactFeature(icon: "lock.fill", title: "Local", text: "Queries use your local Memory Lane history.")
            }
            .frame(maxWidth: 700)
        }
        .padding(36)
    }

    private var capturePage: some View {
        VStack(spacing: 16) {
            pageHeading(
                title: "Remember the Useful Details",
                subtitle: "With Accessibility permission, Memory Lane captures the meaningful thing you were viewing—not just the app name."
            )

            HStack(alignment: .top, spacing: 16) {
                featureCard(
                    icon: "safari",
                    title: "Web",
                    lines: [
                        "Safari page and tab titles",
                        "Supported browser context",
                        "Page URLs when available"
                    ],
                    tint: .blue
                )

                featureCard(
                    icon: "envelope.fill",
                    title: "Email & Chat",
                    lines: [
                        "Outlook email subject lines",
                        "Mail item subjects",
                        "Teams conversations and windows"
                    ],
                    tint: .purple
                )

                featureCard(
                    icon: "doc.fill",
                    title: "Files & Notes",
                    lines: [
                        "Finder locations and filenames",
                        "Word, Excel, PowerPoint, Preview",
                        "OneNote pages and local paths when macOS exposes them"
                    ],
                    tint: .orange
                )
            }
            .frame(maxWidth: 710)

            HStack(spacing: 14) {
                infoStrip(
                    icon: "doc.on.clipboard.fill",
                    title: "Clipboard History",
                    text: "Copied text is remembered by default and can be disabled in Settings."
                )
                infoStrip(
                    icon: "plus.circle.fill",
                    title: "Add Memory",
                    text: "Create a manual memory anytime from the toolbar."
                )
                infoStrip(
                    icon: "star.fill",
                    title: "Favorites",
                    text: "Mark important timeline items so they are easy to find again."
                )
            }
            .frame(maxWidth: 710)
        }
        .padding(34)
    }

    private var privacyAndControlPage: some View {
        HStack(spacing: 42) {
            VStack(spacing: 17) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.35), .purple.opacity(0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 275, height: 220)

                    Image("OnboardingIcon")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 108, height: 108)
                        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white, .blue)
                        .offset(x: 72, y: 68)
                }

                Text("Your history stays on this Mac.")
                    .font(.headline)
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 15) {
                Text("You’re in Control")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(primaryText)

                privacyRow(icon: "pause.circle.fill", title: "Pause Capture", text: "Pause or resume activity capture whenever you need privacy.", tint: .green)
                privacyRow(icon: "hand.raised.slash.fill", title: "Exclude Apps", text: "Choose apps and services Memory Lane should ignore.", tint: .orange)
                privacyRow(icon: "lock.fill", title: "Passwords & Wallet", text: "Passwords and Wallet are always excluded.", tint: .blue)
                privacyRow(icon: "externaldrive.fill", title: "Local Storage", text: "Timeline history is stored locally using SwiftData.", tint: .purple)
                privacyRow(icon: "trash.slash.fill", title: "Clear App Cache", text: "Reset cached capture state and preferences without deleting Timeline history.", tint: .pink)

                Text("You can replay this tutorial anytime from Settings → Help.")
                    .font(.footnote)
                    .foregroundStyle(tertiaryText)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 390)
        }
        .padding(38)
    }

    private var accessibilityPage: some View {
        VStack(spacing: 18) {
            Text("Allow Window Context")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)

            Text("Accessibility access lets Memory Lane capture useful context such as Safari page titles, Outlook subjects, Mail subjects, Teams conversations, OneNote pages, and supported file information.")
                .font(.title3)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 670)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image("OnboardingIcon")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 56, height: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Lane")
                            .font(.headline)
                            .foregroundStyle(primaryText)
                        Text(captureCoordinator.hasAccessibilityPermission
                             ? "Accessibility access is enabled."
                             : "Accessibility access is required for detailed window context.")
                            .foregroundStyle(secondaryText)
                    }

                    Spacer()

                    Image(systemName: captureCoordinator.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(captureCoordinator.hasAccessibilityPermission ? .green : .orange)
                }
                .padding(18)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                if captureCoordinator.hasAccessibilityPermission {
                    Label("Accessibility Access Enabled", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Button {
                            captureCoordinator.requestAccessibilityPermission()
                        } label: {
                            Label("Enable Accessibility Access", systemImage: "hand.raised.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Open System Settings") {
                            captureCoordinator.openAccessibilitySettings()
                        }
                    }
                }

                Text("You can change this permission anytime in System Settings → Privacy & Security → Accessibility.")
                    .font(.footnote)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 620)

            HStack(spacing: 12) {
                statusBadge(icon: "clock.arrow.circlepath", text: "Timeline")
                statusBadge(icon: "sparkles", text: "Ask Memory Lane")
                statusBadge(icon: "folder.fill", text: "Files")
                statusBadge(icon: "doc.on.clipboard.fill", text: "Clipboard")
                statusBadge(icon: "star.fill", text: "Favorites")
            }
        }
        .padding(38)
    }

    private var footer: some View {
        HStack {
            if page > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page -= 1
                    }
                } label: {
                    Label("Back", systemImage: "arrow.left")
                }
            } else {
                Color.clear
                    .frame(width: 84, height: 1)
            }

            Spacer()

            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            Button {
                if page == pageCount - 1 {
                    hasCompletedOnboarding = true
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        page += 1
                    }
                }
            } label: {
                HStack {
                    Text(page == pageCount - 1 ? "Start Using Memory Lane" : "Continue")
                    Image(systemName: page == pageCount - 1 ? "checkmark" : "arrow.right")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func pageHeading(title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(primaryText)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)
        }
    }

    private func benefitRow(icon: String, title: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private func compactFeature(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)

            Text(text)
                .font(.caption)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 13))
    }

    private func featurePill(_ title: String, icon: String, selected: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? Color.white : primaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                selected ? Color.accentColor : Color.white.opacity(0.08),
                in: Capsule()
            )
    }

    private func askExample(_ question: String, answer: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(question)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                Text(answer)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.black.opacity(0.19), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func featureCard(icon: String, title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11))

            Text(title)
                .font(.headline)
                .foregroundStyle(primaryText)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .padding(15)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func infoStrip(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
        .padding(11)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }

    private func privacyRow(icon: String, title: String, text: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(tint.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
            }
        }
    }

    private func sampleTimelineRow(time: String, app: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Text(time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tertiaryText)
                .frame(width: 70, alignment: .trailing)

            Image(systemName: icon)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(detail)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                Text(app)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(tertiaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func statusBadge(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(primaryText)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}
