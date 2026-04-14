import SwiftUI
import Combine

@MainActor
class DiscoverViewModel: ObservableObject {
    @Published var recentlyAdded: [Album] = []
    @Published var recentlyPlayed: [Album] = []
    @Published var frequentlyPlayed: [Album] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared
    private let player = AudioPlayerService.shared

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        async let newest  = api.getAlbumList(type: .newest,         size: 20)
        async let recent  = api.getAlbumList(type: .recentlyPlayed, size: 20)
        async let frequent = api.getAlbumList(type: .frequent,      size: 20)
        do {
            recentlyAdded   = try await newest
            recentlyPlayed  = try await recent
            frequentlyPlayed = try await frequent
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Smart Mixes (identisch zur iOS App)

    /// Newest albums → songs shuffled (wie iOS "Mix: Newest Tracks")
    func playMixNewest() async {
        do {
            let songs = try await api.getNewestSongs(albumCount: 10)
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Frequently played albums → songs sortiert nach playCount (wie iOS "Mix: Frequently Played")
    func playMixFrequent() async {
        do {
            let songs = try await api.getFrequentSongs(albumCount: 30, limit: 100)
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Recently played albums → songs in Album-Reihenfolge (wie iOS "Mix: Recently Played")
    func playMixRecent() async {
        do {
            let songs = try await api.getRecentSongs(albumCount: 30, limit: 100)
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
