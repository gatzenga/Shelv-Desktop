import SwiftUI

struct ArtistContextMenuModifier: ViewModifier {
    let artist: Artist
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject var downloadStore = DownloadStore.shared
    @EnvironmentObject var appState: AppState
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(tr("Play", "Abspielen")) {
                Task {
                    do {
                        let songs = try await fetchSongs()
                        guard !songs.isEmpty else { return }
                        await MainActor.run { AudioPlayerService.shared.play(songs: songs) }
                    } catch {
                        NotificationCenter.default.post(name: .showToast, object: tr("Playback failed", "Wiedergabe fehlgeschlagen"))
                    }
                }
            }
            Button(tr("Shuffle", "Zufällig abspielen")) {
                Task {
                    do {
                        let songs = try await fetchSongs()
                        guard !songs.isEmpty else { return }
                        await MainActor.run { AudioPlayerService.shared.playShuffled(songs: songs) }
                    } catch {
                        NotificationCenter.default.post(name: .showToast, object: tr("Playback failed", "Wiedergabe fehlgeschlagen"))
                    }
                }
            }
            Divider()
            Button(tr("Play Next", "Als nächstes abspielen")) {
                Task {
                    do {
                        let songs = try await fetchSongs()
                        guard !songs.isEmpty else { return }
                        await MainActor.run {
                            AudioPlayerService.shared.addPlayNext(songs)
                            NotificationCenter.default.post(name: .showToast, object: tr("Added to Play Next", "Als nächstes hinzugefügt"))
                        }
                    } catch {
                        NotificationCenter.default.post(name: .showToast, object: tr("Action failed", "Aktion fehlgeschlagen"))
                    }
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                Task {
                    do {
                        let songs = try await fetchSongs()
                        guard !songs.isEmpty else { return }
                        await MainActor.run {
                            AudioPlayerService.shared.addToUserQueue(songs)
                            NotificationCenter.default.post(name: .showToast, object: tr("Added to Queue", "Zur Warteschlange hinzugefügt"))
                        }
                    } catch {
                        NotificationCenter.default.post(name: .showToast, object: tr("Action failed", "Aktion fehlgeschlagen"))
                    }
                }
            }
            if enableFavorites || enablePlaylists {
                Divider()
                if enableFavorites {
                    Button(libraryStore.isArtistStarred(artist)
                           ? tr("Remove from Favorites", "Aus Favoriten entfernen")
                           : tr("Add to Favorites", "Zu Favoriten hinzufügen")) {
                        Task { await libraryStore.toggleStarArtist(artist) }
                    }
                }
                if enablePlaylists {
                    Button(tr("Add to Playlist…", "Zur Wiedergabeliste hinzufügen…")) {
                        Task {
                            do {
                                let songs = try await fetchSongs()
                                guard !songs.isEmpty else { return }
                                let ids = songs.map(\.id)
                                await MainActor.run {
                                    NotificationCenter.default.post(name: .addSongsToPlaylist, object: ids)
                                }
                            } catch {
                                NotificationCenter.default.post(name: .showToast, object: tr("Action failed", "Aktion fehlgeschlagen"))
                            }
                        }
                    }
                }
            }
            if enableDownloads {
                Divider()
                if !offlineMode.isOffline {
                    Button(tr("Download Artist", "Künstler herunterladen")) {
                        let stable = appState.serverStore.activeServer?.stableId ?? ""
                        Task { await DownloadService.shared.enqueueArtist(artist: artist, serverId: stable) }
                        NotificationCenter.default.post(name: .showToast, object: tr("Download started", "Download gestartet"))
                    }
                }
                if downloadStore.artists.contains(where: { $0.name == artist.name }) {
                    Button(role: .destructive) {
                        if let match = downloadStore.artists.first(where: { $0.name == artist.name }) {
                            downloadStore.deleteArtist(match.artistId)
                        }
                    } label: {
                        Label { Text(tr("Delete Downloads", "Downloads löschen")) } icon: { DeleteDownloadIcon(tint: .red) }
                    }
                }
            }
        }
    }

    private func fetchSongs() async throws -> [Song] {
        let detail = try await SubsonicAPIService.shared.getArtist(id: artist.id)
        return try await withThrowingTaskGroup(of: [Song].self) { group -> [Song] in
            for album in detail.album {
                group.addTask { try await SubsonicAPIService.shared.getAlbum(id: album.id).song }
            }
            var result: [Song] = []
            for try await albumSongs in group { result.append(contentsOf: albumSongs) }
            return result
        }
    }
}

extension View {
    func artistContextMenu(_ artist: Artist) -> some View {
        modifier(ArtistContextMenuModifier(artist: artist))
    }
}
