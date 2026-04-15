import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryStore: LibraryViewModel
    @Binding var selection: SidebarItem?
    @Binding var selectedPlaylist: Playlist?
    @Environment(\.themeColor) private var themeColor
    @AppStorage("enableFavorites") private var enableFavorites = false
    @AppStorage("enablePlaylists") private var enablePlaylists = false

    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Main navigation items
            SidebarRow(item: .discover, isSelected: selection == .discover && selectedPlaylist == nil, themeColor: themeColor) {
                selection = .discover
                selectedPlaylist = nil
                appState.navigationPath = NavigationPath()
            }
            SidebarRow(item: .albums, isSelected: selection == .albums && selectedPlaylist == nil, themeColor: themeColor) {
                selection = .albums
                selectedPlaylist = nil
                appState.navigationPath = NavigationPath()
            }
            SidebarRow(item: .artists, isSelected: selection == .artists && selectedPlaylist == nil, themeColor: themeColor) {
                selection = .artists
                selectedPlaylist = nil
                appState.navigationPath = NavigationPath()
            }
            if enableFavorites {
                SidebarRow(item: .favorites, isSelected: selection == .favorites && selectedPlaylist == nil, themeColor: themeColor) {
                    selection = .favorites
                    selectedPlaylist = nil
                    appState.navigationPath = NavigationPath()
                }
            }
            SidebarRow(item: .search, isSelected: selection == .search && selectedPlaylist == nil, themeColor: themeColor) {
                selection = .search
                selectedPlaylist = nil
                appState.navigationPath = NavigationPath()
            }

            // Playlists section
            if enablePlaylists {
                Divider()
                    .padding(.vertical, 8)

                HStack {
                    Text(tr("Playlists", "Wiedergabelisten"))
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        newPlaylistName = ""
                        showCreatePlaylist = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.callout.bold())
                            .foregroundStyle(themeColor)
                    }
                    .buttonStyle(.plain)
                    .help(tr("New Playlist", "Neue Wiedergabeliste"))
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

                if libraryStore.isLoadingPlaylists && libraryStore.playlists.isEmpty {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.horizontal, 10)
                } else if libraryStore.playlists.isEmpty {
                    Text(tr("No Playlists", "Keine Wiedergabelisten"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                } else {
                    ForEach(libraryStore.playlists) { playlist in
                        PlaylistSidebarRow(
                            playlist: playlist,
                            isSelected: selectedPlaylist?.id == playlist.id,
                            themeColor: themeColor
                        ) {
                            selectedPlaylist = playlist
                            selection = nil
                            appState.navigationPath = NavigationPath()
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 290)
        .task {
            if enableFavorites && libraryStore.starredAlbums.isEmpty {
                await libraryStore.loadStarred()
            }
            if enablePlaylists && libraryStore.playlists.isEmpty {
                await libraryStore.loadPlaylists()
            }
        }
        .onChange(of: enableFavorites) { _, new in
            if new { Task { await libraryStore.loadStarred() } }
        }
        .onChange(of: enablePlaylists) { _, new in
            if new { Task { await libraryStore.loadPlaylists() } }
        }
        .alert(tr("New Playlist", "Neue Wiedergabeliste"), isPresented: $showCreatePlaylist) {
            TextField(tr("Name", "Name"), text: $newPlaylistName)
            Button(tr("Create", "Erstellen")) {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await libraryStore.createPlaylist(name: name) }
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) { }
        } message: {
            Text(tr("Enter a name for the new playlist.", "Namen für die neue Wiedergabeliste eingeben."))
        }
    }
}

// MARK: - Sidebar Row

struct SidebarRow: View {
    let item: SidebarItem
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(LocalizedStringKey(item.rawValue), systemImage: item.icon)
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? themeColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected
                                ? themeColor.opacity(0.15)
                                : isHovered
                                    ? Color.primary.opacity(0.06)
                                    : Color.clear
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Playlist Sidebar Row

struct PlaylistSidebarRow: View {
    let playlist: Playlist
    let isSelected: Bool
    let themeColor: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(playlist.name, systemImage: "music.note.list")
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? themeColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isSelected
                                ? themeColor.opacity(0.15)
                                : isHovered
                                    ? Color.primary.opacity(0.06)
                                    : Color.clear
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    SidebarView(
        selection: .constant(.discover),
        selectedPlaylist: .constant(nil)
    )
    .environmentObject(AppState.shared)
    .environmentObject(LibraryViewModel())
    .frame(width: 200, height: 400)
}
