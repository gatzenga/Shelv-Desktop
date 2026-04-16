import SwiftUI
import Combine

@MainActor
class DiscoverViewModel: ObservableObject {
    @Published var recentlyAdded: [Album] = []
    @Published var recentlyPlayed: [Album] = []
    @Published var frequentlyPlayed: [Album] = []
    @Published var randomAlbums: [Album] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared
    private let player = AudioPlayerService.shared
    private static let shelfSize = 20

    func load(force: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        async let newest   = api.getAlbumList(type: .newest,         size: Self.shelfSize)
        async let recent   = api.getAlbumList(type: .recentlyPlayed, size: Self.shelfSize)
        async let frequent = api.getAlbumList(type: .frequent,       size: Self.shelfSize)
        async let random   = api.getAlbumList(type: .random,         size: Self.shelfSize)
        do {
            recentlyAdded    = try await newest
            recentlyPlayed   = try await recent
            frequentlyPlayed = try await frequent
            randomAlbums     = try await random
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func reset() {
        recentlyAdded = []
        recentlyPlayed = []
        frequentlyPlayed = []
        randomAlbums = []
        errorMessage = nil
        isLoading = false
    }

    func refreshRandom() async {
        do {
            randomAlbums = try await api.getAlbumList(type: .random, size: Self.shelfSize)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playMixNewest() async {
        do {
            let songs = try await api.getNewestSongs()
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playMixFrequent() async {
        do {
            let songs = try await api.getFrequentSongs(limit: 100)
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func playMixRecent() async {
        do {
            let songs = try await api.getRecentSongs(limit: 100)
            player.play(songs: songs.shuffled())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
