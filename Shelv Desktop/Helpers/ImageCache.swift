import SwiftUI
import AppKit

// MARK: - Async Cover Art Image View

struct CoverArtView: View {
    let url: URL?
    var size: CGFloat = 180
    var cornerRadius: CGFloat = 8

    @State private var image: NSImage?

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
            guard let url else { return }
            image = await ImageCacheService.shared.image(url: url)
        }
    }
}

// MARK: - Cache Service

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let memory = NSCache<NSString, NSImage>()
    private let cacheDir: URL
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cacheDir = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shelv_covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memory.countLimit = 300
        memory.totalCostLimit = 100 * 1024 * 1024
    }

    func image(url: URL) async -> NSImage? {
        let key = cacheKey(for: url)

        if let hit = memory.object(forKey: key as NSString) { return hit }

        if let existing = inflight[key] { return await existing.value }

        let diskURL = cacheDir.appendingPathComponent(key)

        let task = Task.detached(priority: .utility) { () -> NSImage? in
            if Task.isCancelled { return nil }
            if let data = try? Data(contentsOf: diskURL),
               let img = NSImage(data: data) { return img }
            if Task.isCancelled { return nil }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data) else { return nil }
            if Task.isCancelled { return nil }
            try? data.write(to: diskURL, options: .atomic)
            return img
        }

        inflight[key] = task
        let img = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        inflight.removeValue(forKey: key)

        if let img {
            let cost = Int(img.size.width * img.size.height * 4)
            memory.setObject(img, forKey: key as NSString, cost: cost)
        }
        return img
    }

    func clearAll() {
        memory.removeAllObjects()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func diskUsageBytes() -> Int {
        FileManager.default.directorySize(at: cacheDir)
    }

    private func cacheKey(for url: URL) -> String {
        String(abs(url.absoluteString.hashValue))
    }
}
