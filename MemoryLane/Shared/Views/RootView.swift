import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var selection: SidebarItem? = .timeline
    @State private var showingAddMemory = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainInterface
            } else {
                OnboardingView()
            }
        }
    }

    private var mainInterface: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Memory Lane") {
                    Label("Timeline", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarItem.timeline)
                    Label("Search", systemImage: "magnifyingglass")
                        .tag(SidebarItem.search)
                    Label("Favorites", systemImage: "star")
                        .tag(SidebarItem.favorites)
                }

                Section("Control") {
                    Button {
                        preferences.capturePaused.toggle()
                    } label: {
                        Label(
                            preferences.capturePaused ? "Resume Capture" : "Pause Capture",
                            systemImage: preferences.capturePaused ? "play.circle.fill" : "pause.circle.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Memory Lane")
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(preferences.capturePaused ? .orange : .green)
                        .frame(width: 8, height: 8)
                    Text(preferences.capturePaused ? "Capture paused" : "Capture active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        } detail: {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Label("Add Memory", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $showingAddMemory) {
            AddMemoryView()
        }
    }
}

enum SidebarItem: Hashable {
    case timeline, search, favorites, settings
}
