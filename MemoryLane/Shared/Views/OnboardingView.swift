import AppKit
import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0
    @State private var captureCoordinator = MacCaptureCoordinator.shared

    private let pageCount = 4


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
                MemoryLaneBrandMark()
                    .frame(width: 150, height: 150)
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

                    MemoryLaneBrandMark()
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
                    MemoryLaneBrandMark()
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


private struct MemoryLaneBrandMark: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let scale = size / 160

            ZStack {
                RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.015, green: 0.055, blue: 0.16),
                                Color(red: 0.03, green: 0.12, blue: 0.34),
                                Color(red: 0.12, green: 0.06, blue: 0.28)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 34 * scale, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.34), .cyan.opacity(0.18), .purple.opacity(0.22)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: max(1, 1.8 * scale)
                            )
                    }

                Circle()
                    .fill(.cyan.opacity(0.18))
                    .frame(width: 116 * scale, height: 116 * scale)
                    .blur(radius: 24 * scale)
                    .offset(x: -22 * scale, y: -24 * scale)

                Circle()
                    .fill(.purple.opacity(0.20))
                    .frame(width: 104 * scale, height: 104 * scale)
                    .blur(radius: 26 * scale)
                    .offset(x: 28 * scale, y: 22 * scale)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 80 * scale, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        .white.opacity(0.16)
                    )
                    .offset(y: -10 * scale)

                Path { path in
                    path.move(to: CGPoint(x: 80 * scale, y: 76 * scale))
                    path.addCurve(
                        to: CGPoint(x: 60 * scale, y: 154 * scale),
                        control1: CGPoint(x: 102 * scale, y: 96 * scale),
                        control2: CGPoint(x: 88 * scale, y: 126 * scale)
                    )
                }
                .stroke(
                    LinearGradient(
                        colors: [.white, .cyan, .blue, .purple],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 12 * scale, lineCap: .round)
                )
                .shadow(color: .cyan.opacity(0.7), radius: 5 * scale)

                Path { path in
                    path.move(to: CGPoint(x: 79 * scale, y: 79 * scale))
                    path.addCurve(
                        to: CGPoint(x: 61 * scale, y: 151 * scale),
                        control1: CGPoint(x: 97 * scale, y: 99 * scale),
                        control2: CGPoint(x: 85 * scale, y: 124 * scale)
                    )
                }
                .stroke(
                    .white.opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: 2.2 * scale,
                        lineCap: .round,
                        dash: [6 * scale, 7 * scale]
                    )
                )
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
