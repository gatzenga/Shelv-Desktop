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

// MARK: - Toast View

struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark")
            .font(.callout.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.8), in: Capsule())
            .allowsHitTesting(false)
    }
}

// MARK: - Main Window

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var libraryStore = LibraryViewModel()

    @State private var showAddToPlaylist = false
    @State private var playlistSongIds: [String] = []
    @State private var toastMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(
                    selection: $appState.selectedSidebar,
                    selectedPlaylist: $appState.selectedPlaylist
                )
                .environmentObject(libraryStore)
            } detail: {
                NavigationStack(path: $appState.navigationPath) {
                    sectionRoot
                        .navigationDestination(for: Album.self) { album in
                            AlbumDetailView(albumId: album.id, albumName: album.name)
                                .environmentObject(libraryStore)
                        }
                        .navigationDestination(for: Artist.self) { artist in
                            ArtistDetailView(artistId: artist.id, artistName: artist.name)
                                .environmentObject(libraryStore)
                        }
                }
                .environmentObject(libraryStore)
            }
            .onChange(of: appState.selectedSidebar) { _, _ in
                appState.navigationPath = NavigationPath()
                appState.selectedPlaylist = nil
            }
            .background(Color(NSColor.windowBackgroundColor))

            PlayerBarView()
                .environmentObject(libraryStore)
        }
        .overlay(alignment: .top) {
            if let msg = toastMessage {
                ToastView(message: msg)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 12)
            }
        }
        .animation(.spring(duration: 0.35), value: toastMessage)
        .onReceive(NotificationCenter.default.publisher(for: .addSongsToPlaylist)) { notification in
            if let ids = notification.object as? [String] {
                playlistSongIds = ids
                showAddToPlaylist = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showToast)) { notification in
            if let msg = notification.object as? String {
                toastMessage = msg
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    toastMessage = nil
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistPanel(songIds: playlistSongIds)
                .environmentObject(libraryStore)
        }
    }

    @ViewBuilder
    private var sectionRoot: some View {
        if let playlist = appState.selectedPlaylist {
            PlaylistDetailView(playlist: playlist)
                .environmentObject(libraryStore)
        } else {
            switch appState.selectedSidebar {
            case .discover, .none: DiscoverView()
            case .albums:          AlbumsView().environmentObject(libraryStore)
            case .artists:         ArtistsView().environmentObject(libraryStore)
            case .favorites:       FavoritesView().environmentObject(libraryStore)
            case .search:          SearchView().environmentObject(libraryStore)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .frame(width: 1200, height: 760)
}
