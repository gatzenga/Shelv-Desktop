import SwiftUI
import Combine

struct AlbumDetailView: View {
    let albumId: String
    let albumName: String
    @StateObject private var vm = AlbumDetailViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject private var player = AudioPlayerService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Header
                HStack(alignment: .top, spacing: 24) {
                    CoverArtView(url: coverURL, size: 160, cornerRadius: 12)
                        .shadow(color: .black.opacity(0.25), radius: 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(vm.album?.name ?? albumName)
                            .font(.title.bold())
                            .lineLimit(2)

                        if let artist = vm.album?.artist {
                            Text(artist)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            if let year  = vm.album?.year     { Text(String(year)) }
                            if let genre = vm.album?.genre    { Text("·"); Text(genre) }
                            if let count = vm.album?.songCount { Text("·"); Text(String(format: NSLocalizedString("%lld Titel", comment: ""), count)) }
                            if let dur   = vm.album?.duration  { Text("·"); Text(formatDuration(dur)) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                        Spacer(minLength: 12)

                        HStack(spacing: 10) {
                            Button {
                                if let songs = vm.album?.song { appState.player.play(songs: songs) }
                            } label: {
                                Label("Abspielen", systemImage: "play.fill")
                                    .frame(minWidth: 110)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(vm.isLoading)

                            Button {
                                if let songs = vm.album?.song {
                                    appState.player.play(songs: songs.shuffled())
                                }
                            } label: {
                                Label("Zufall", systemImage: "shuffle")
                                    .frame(minWidth: 100)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(vm.isLoading)
                        }
                    }

                    Spacer()
                }
                .padding(28)

                Divider()
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)

                // MARK: Track List
                if vm.isLoading {
                    ProgressView("Titel laden…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(vm.songs.enumerated()), id: \.element.id) { index, song in
                            TrackRow(
                                song: song,
                                isPlaying: player.currentSong?.id == song.id
                            ) {
                                appState.player.play(songs: vm.songs, startIndex: index)
                            } onPlayNext: {
                                appState.player.addPlayNext(song)
                            } onAddToQueue: {
                                appState.player.addToUserQueue(song)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding(28)
                }
            }
        }
        .navigationTitle(vm.album?.name ?? albumName)
        .task { await vm.load(albumId: albumId) }
    }

    private var coverURL: URL? {
        guard let id = vm.album?.coverArt ?? albumId as String? else { return nil }
        return SubsonicAPIService.shared.coverArtURL(id: id, size: 320)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return "\(m):\(String(format: "%02d", s)) min"
    }
}

// MARK: - Track Row

struct TrackRow: View {
    let song: Song
    let isPlaying: Bool
    let onPlay: () -> Void
    let onPlayNext: () -> Void
    let onAddToQueue: () -> Void

    @Environment(\.themeColor) private var themeColor
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Track number / waveform
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(themeColor)
                        .symbolEffect(.variableColor.iterative)
                } else {
                    Text(song.displayTrack)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .frame(width: 36, alignment: .trailing)
            .padding(.leading, 20)

            // Title + Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isPlaying ? themeColor : .primary)
                    .fontWeight(isPlaying ? .semibold : .regular)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 14)

            Spacer()

            // Duration
            Text(song.durationString)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.trailing, 24)
        }
        .frame(height: 52)
        .background {
            Color(NSColor.windowBackgroundColor)
            if isHovered {
                Color.primary.opacity(0.07)
            } else if isPlaying {
                themeColor.opacity(0.08)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { onPlay() })
        .contextMenu {
            Button("Als nächstes abspielen") { onPlayNext() }
            Button("Zur Warteschlange hinzufügen") { onAddToQueue() }
        }
    }
}

// MARK: - ViewModel

@MainActor
class AlbumDetailViewModel: ObservableObject {
    @Published var album: AlbumDetail?
    @Published var songs: [Song] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = SubsonicAPIService.shared

    func load(albumId: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await api.getAlbum(id: albumId)
            album = detail
            songs = detail.song
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(albumId: "1", albumName: "Vorschau Album")
    }
    .frame(width: 700, height: 600)
    .environmentObject(AppState.shared)
}
