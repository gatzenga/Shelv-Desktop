import SwiftUI
import AppKit

// MARK: - Async Cover Art Image View

struct CoverArtView: View {
    let url: URL?
    var size: CGFloat = 180
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.6)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url?.absoluteString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else { return }
        if let cached = ImageCacheService.shared.get(url: url) {
            image = cached
            return
        }
        isLoading = true
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = NSImage(data: data) {
                ImageCacheService.shared.set(img, for: url)
                image = img
            }
        } catch {
            // silently ignore
        }
        isLoading = false
    }
}

// MARK: - Cache Service

final class ImageCacheService {
    static let shared = ImageCacheService()
    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func get(url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: NSImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    func clear() {
        cache.removeAllObjects()
    }

    var approximateSize: Int {
        // NSCache doesn't expose size easily, just return count * estimated avg
        cache.totalCostLimit
    }
}
