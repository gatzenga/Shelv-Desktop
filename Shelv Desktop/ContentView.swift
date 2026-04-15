import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
    @AppStorage("themeColor") private var themeColorName: String = "violet"

    var body: some View {
        Group {
            if appState.isLoggedIn {
                MainWindowView()
            } else {
                LoginView()
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .tint(AppTheme.color(for: themeColorName))
        .environment(\.themeColor, AppTheme.color(for: themeColorName))
        .onAppear { NSApp.appearance = storedColorScheme.nsAppearance }
        .onChange(of: storedColorScheme) { _, new in NSApp.appearance = new.nsAppearance }
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $appState.selectedSidebar)
            } detail: {
                NavigationStack(path: $appState.navigationPath) {
                    sectionRoot
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(albumId: album.id, albumName: album.name)
                        }
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artistId: artist.id, artistName: artist.name)
                        }
                }
            }
            .onChange(of: appState.selectedSidebar) { _, _ in
                appState.navigationPath = NavigationPath()
            }
            .background(Color(NSColor.windowBackgroundColor))

            PlayerBarView()
        }
    }

    @ViewBuilder
    private var sectionRoot: some View {
        switch appState.selectedSidebar {
        case .discover, .none: DiscoverView()
        case .albums:          AlbumsView()
        case .artists:         ArtistsView()
        case .search:          SearchView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 1200, height: 760)
}
