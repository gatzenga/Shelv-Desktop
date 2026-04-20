import SwiftUI

struct AddToPlaylistPanel: View {
    let songIds: [String]
    @EnvironmentObject var libraryStore: LibraryViewModel
    @StateObject private var recapStore = RecapStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColor) private var themeColor

    @State private var newPlaylistName = ""

    private var nonRecapPlaylists: [Playlist] {
        libraryStore.playlists.filter {
            !recapStore.recapPlaylistIds.contains($0.id) && $0.comment != "Shelv Recap"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(tr("Add to Playlist", "Zu Wiedergabeliste hinzufügen"))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            List {
                // Existing playlists
                if !nonRecapPlaylists.isEmpty {
                    Section(tr("Existing Playlists", "Bestehende Wiedergabelisten")) {
                        ForEach(nonRecapPlaylists) { playlist in
                            Button {
                                Task {
                                    await libraryStore.addSongsToPlaylist(playlist, songIds: songIds)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    CoverArtView(
                                        url: playlist.coverArt.flatMap {
                                            SubsonicAPIService.shared.coverArtURL(id: $0, size: 60)
                                        },
                                        size: 36,
                                        cornerRadius: 4
                                    )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(playlist.name)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        if let count = playlist.songCount {
                                            Text(tr("\(count) Tracks", "\(count) Titel"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Create new
                Section(tr("Create New", "Neu erstellen")) {
                    HStack {
                        TextField(tr("Playlist name", "Name der Wiedergabeliste"), text: $newPlaylistName)
                            .textFieldStyle(.plain)
                        Button(tr("Create", "Erstellen")) {
                            let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            Task {
                                await libraryStore.createPlaylist(name: name)
                                // Find and add to new playlist
                                if let created = libraryStore.playlists.first(where: { $0.name == name }) {
                                    await libraryStore.addSongsToPlaylist(created, songIds: songIds)
                                }
                                dismiss()
                            }
                        }
                        .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(themeColor)
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 380, height: 440)
        .task {
            if libraryStore.playlists.isEmpty {
                await libraryStore.loadPlaylists()
            }
        }
    }
}
