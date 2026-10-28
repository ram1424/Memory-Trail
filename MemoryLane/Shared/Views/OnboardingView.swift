import AppKit
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var captureCoordinator = MacCaptureCoordinator.shared

    private let pageCount = 4

    private static let onboardingIcon: NSImage = {
        guard let data = Data(base64Encoded: "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[... ELLIPSIZATION ...]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"),
              let image = NSImage(data: data) else {
            return NSImage()
        }
        image.size = NSSize(width: 512, height: 512)
        return image
    }()

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
                }
                .padding(.horizontal, 28)
                .padding(.top, 22)

                Group {
                    switch page {
                    case 0:
                        welcomePage
                    case 1:
                        howItWorksPage
                    case 2:
                        privacyPage
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
            .frame(width: 760, height: 580)
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
            if page == 3 {
                captureCoordinator.refreshAccessibilityStatus()
            }
        }
    }

    private var welcomePage: some View {
        HStack(spacing: 54) {
            VStack(spacing: 18) {
                Image(nsImage: Self.onboardingIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 150, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

                Text("Welcome to\nMemory Lane")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)

                Text("Memory Lane quietly builds a private timeline of your work so you can see where you’ve been and quickly pick up where you left off.")
                    .font(.title3)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)
            }

            VStack(alignment: .leading, spacing: 24) {
                benefitRow(
                    icon: "list.bullet.rectangle",
                    title: "Remember your work",
                    text: "See apps and supported window activity in chronological order.",
                    tint: .purple
                )
                benefitRow(
                    icon: "magnifyingglass",
                    title: "Find your way back",
                    text: "Search your timeline when you can’t remember where you saw something.",
                    tint: .blue
                )
                benefitRow(
                    icon: "shield.lefthalf.filled",
                    title: "Local-first privacy",
                    text: "Your activity history stays on your Mac.",
                    tint: .green
                )
            }
            .frame(maxWidth: 340)
        }
        .padding(42)
    }

    private var howItWorksPage: some View {
        VStack(spacing: 18) {
            Text("How Memory Lane Works")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(primaryText)

            Text("As you move between apps, Memory Lane adds useful context to your timeline. With Accessibility permission, it can also remember supported window titles so you can retrace your work more easily.")
                .font(.title3)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 660)

            VStack(spacing: 0) {
                sampleTimelineRow(
                    time: "9:42 AM",
                    app: "Safari",
                    detail: "Cisco Room Bar Configuration Guide",
                    icon: "safari"
                )
                Divider()
                sampleTimelineRow(
                    time: "9:18 AM",
                    app: "Microsoft Outlook",
                    detail: "RE: Data Center Staffing Plan",
                    icon: "envelope.fill"
                )
                Divider()
                sampleTimelineRow(
                    time: "8:54 AM",
                    app: "Microsoft Teams",
                    detail: "John Smith | Project Phoenix",
                    icon: "person.2.fill"
                )
                Divider()
                sampleTimelineRow(
                    time: "8:31 AM",
                    app: "Notes",
                    detail: "Project ideas and next steps",
                    icon: "note.text"
                )
            }
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .frame(maxWidth: 620)
        }
        .padding(40)
    }

    private var privacyPage: some View {
        HStack(spacing: 48) {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.35), .purple.opacity(0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 285, height: 230)

                    Image(nsImage: Self.onboardingIcon)
                    .resizable()
                    .interpolation(.high)
                        .frame(width: 112, height: 112)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.white, .blue)
                        .offset(x: 74, y: 72)
                }

                Text("Your timeline stays on this Mac.")
                    .font(.headline)
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 290)
            }

            VStack(alignment: .leading, spacing: 20) {
                Text("You’re in Control")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(primaryText)

                privacyRow(icon: "externaldrive.fill", title: "Stored Locally", text: "Your Memory Lane timeline is kept on your Mac.", tint: .blue)
                privacyRow(icon: "hand.raised.slash.fill", title: "Sensitive Apps Stay Private", text: "Passwords and Wallet are excluded from capture automatically.", tint: .orange)
                privacyRow(icon: "pause.circle.fill", title: "Pause Whenever You Want", text: "Pause or resume activity capture at any time from the menu bar.", tint: .green)
                privacyRow(icon: "doc.on.clipboard.fill", title: "Clipboard Is Optional", text: "Clipboard capture is off by default and only turns on if you choose it.", tint: .purple)
            }
            .frame(maxWidth: 350)
        }
        .padding(42)
    }

    private var accessibilityPage: some View {
        VStack(spacing: 18) {
            Text("Allow Memory Lane to See Window Context")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)

            Text("Accessibility access lets Memory Lane add helpful window context—such as Safari page titles, Outlook items, Mail subjects, and Teams windows—to your timeline.")
                .font(.title3)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)

            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(nsImage: Self.onboardingIcon)
                    .resizable()
                    .interpolation(.high)
                        .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Memory Lane")
                            .font(.headline)
                        Text(captureCoordinator.hasAccessibilityPermission
                             ? "Accessibility access is enabled."
                             : "Accessibility access is required for window context.")
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
            .frame(maxWidth: 600)
        }
        .padding(40)
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
                Text(app)
                    .font(.headline)
                    .foregroundStyle(primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(tertiaryText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}

