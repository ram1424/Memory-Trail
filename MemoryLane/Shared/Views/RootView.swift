import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(RecallPreferences.self) private var preferences
    @State private var selection: SidebarItem? = .timeline
    @State private var showingAddMemory = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Recall") {
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
                            systemImage: preferences.capturePaused ? "play.circle" : "pause.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Recall")
        } detail: {
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddMemory = true
                    } label: {
                        Label("Add Memory", systemImage: "plus")
                    }
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
