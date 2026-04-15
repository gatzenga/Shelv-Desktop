import SwiftUI

// MARK: - Album Context Menu Modifier

struct AlbumContextMenuModifier: ViewModifier {
    let album: Album

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(tr("Play Next", "Als nächstes abspielen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.addPlayNext(detail.song) }
                }
            }
            Button(tr("Add to Queue", "Zur Warteschlange hinzufügen")) {
                Task {
                    guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return }
                    await MainActor.run { AudioPlayerService.shared.addToUserQueue(detail.song) }
                }
            }
        }
    }
}

extension View {
    func albumContextMenu(_ album: Album) -> some View {
        modifier(AlbumContextMenuModifier(album: album))
    }
}
