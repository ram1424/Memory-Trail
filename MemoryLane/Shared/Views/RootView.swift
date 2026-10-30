import AppKit
import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var selection: SidebarItem?
    @State private var showingAddMemory = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let forceMainInterface: Bool

    init(
        initialSelection: SidebarItem? = .timeline,
        forceMainInterface: Bool = false
    ) {
        _selection = State(initialValue: initialSelection)
        self.forceMainInterface = forceMainInterface
    }

    var body: some View {
        Group {
            if forceMainInterface || hasCompletedOnboarding {
                mainInterface
            } else {
                OnboardingView()
            }
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            MemoryLaneSidebar(selection: $selection)
                .environment(preferences)
                .frame(minWidth: 220, idealWidth: 235, maxWidth: 255)
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Group {
                    switch selection ?? .timeline {
                    case .timeline:
                        TimelineView()
                    case .search:
                        SearchView()
                    case .favorites:
                        FavoritesView()
                    case .settings:
                        SettingsView()
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add Memory")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
        }
    }
}

private struct MemoryLaneSidebar: View {
    @Environment(RecallPreferences.self) private var preferences
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 18)

            VStack(spacing: 6) {
                sidebarButton(.timeline, title: "Timeline", symbol: "clock")
                sidebarButton(.search, title: "Ask Memory Lane", symbol: "sparkles")
                sidebarButton(.favorites, title: "Favorites", symbol: "star")
            }
            .padding(.horizontal, 10)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 18)

            Text("Settings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            VStack(spacing: 6) {
                Button {
                    preferences.capturePaused.toggle()
                } label: {
                    sidebarRow(
                        title: preferences.capturePaused ? "Resume Capture" : "Capture",
                        symbol: preferences.capturePaused ? "play.circle" : "record.circle",
                        selected: false
                    )
                }
                .buttonStyle(.plain)

                sidebarButton(.settings, title: "Privacy & General", symbol: "lock.shield")
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 16)

            captureStatus
                .padding(12)
        }
        .background(.ultraThinMaterial)
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("Memory Lane")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Your day, recalled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func sidebarButton(_ item: SidebarItem, title: String, symbol: String) -> some View {
        Button {
            selection = item
        } label: {
            sidebarRow(
                title: title,
                symbol: symbol,
                selected: selection == item
            )
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow(title: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14.5, weight: selected ? .semibold : .medium))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            selected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var captureStatus: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(preferences.capturePaused ? Color.orange : Color.green)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(preferences.capturePaused ? "Capture paused" : "Capturing")
                    .font(.caption.weight(.semibold))
                Text(preferences.capturePaused ? "Activity is not being recorded" : "Recording your activity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }
}

enum SidebarItem: Hashable {
    case timeline, search, favorites, settings
}
