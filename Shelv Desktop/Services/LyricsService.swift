import Foundation

// MARK: - Models

struct LyricsRecord: Codable {
    var songId: String
    var serverId: String
    var source: String
    var plainText: String?
    var syncedLrc: String?
    var isSynced: Bool
    var isInstrumental: Bool
    var language: String?
    var fetchedAt: Double
    var songTitle: String? = nil
    var artistName: String? = nil
    var coverArt: String? = nil
}

struct LyricsSearchResult: Identifiable {
    var id: String { songId }
    let songId: String
    let songTitle: String?
    let artistName: String?
    let coverArt: String?
    let snippet: String
}

// MARK: - LRCLIB Response

private struct LrcLibResponse: Sendable {
    let instrumental: Bool?
    let plainLyrics: String?
    let syncedLyrics: String?
}

extension LrcLibResponse: Decodable {
    private enum CodingKeys: String, CodingKey {
        case instrumental, plainLyrics, syncedLyrics
    }

    nonisolated init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instrumental = try c.decodeIfPresent(Bool.self,   forKey: .instrumental)
        plainLyrics  = try c.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try c.decodeIfPresent(String.self, forKey: .syncedLyrics)
    }
}

// MARK: - LyricsService

actor LyricsService {
    static let shared = LyricsService()

    private var records: [String: LyricsRecord] = [:]
    private var isSetup = false

    private init() {}

    // MARK: - Setup

    func setup() {
        guard !isSetup else { return }
        isSetup = true
        load()
    }

    static var storeURL: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shelv_lyrics/lyrics.json")
    }

    nonisolated static func diskSizeBytes() -> Int {
        (try? storeURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    // MARK: - Persistence

    private func key(_ songId: String, _ serverId: String) -> String { "\(songId):\(serverId)" }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode([String: LyricsRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func persist() {
        let url = Self.storeURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Read / Write

    func lyrics(songId: String, serverId: String) -> LyricsRecord? {
        records[key(songId, serverId)]
    }

    func save(_ record: LyricsRecord) {
        records[key(record.songId, record.serverId)] = record
        persist()
    }

    // MARK: - Stats

    func fetchedCount(serverId: String) -> Int {
        records.values.filter { $0.serverId == serverId && $0.source != "none" }.count
    }

    // MARK: - Metadata Backfill

    func updateMetadata(songId: String, serverId: String, title: String, artist: String?, coverArt: String?) {
        let k = key(songId, serverId)
        guard var r = records[k] else { return }
        r.songTitle = title
        r.artistName = artist
        r.coverArt = coverArt
        records[k] = r
        persist()
    }

    // MARK: - Reset

    func reset(serverId: String) {
        records = records.filter { $0.value.serverId != serverId }
        persist()
    }

    // MARK: - Search

    func searchLyrics(text: String, serverId: String, limit: Int = 40) -> [LyricsSearchResult] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let lower = text.lowercased()
        return Array(
            records.values
                .filter { $0.serverId == serverId && $0.source != "none" && !$0.isInstrumental }
                .filter { $0.plainText?.lowercased().contains(lower) == true }
                .prefix(limit)
                .compactMap { r -> LyricsSearchResult? in
                    let snippet = r.plainText
                        .flatMap { t in t.components(separatedBy: "\n").first { $0.lowercased().contains(lower) } }?
                        .trimmingCharacters(in: .whitespaces) ?? ""
                    return LyricsSearchResult(
                        songId: r.songId, songTitle: r.songTitle,
                        artistName: r.artistName, coverArt: r.coverArt,
                        snippet: snippet
                    )
                }
        )
    }

    // MARK: - Fetch & Cache

    func fetchAndSave(song: Song, serverId: String) async -> LyricsRecord {
        let sixMonths: Double = 60 * 60 * 24 * 180
        if var cached = lyrics(songId: song.id, serverId: serverId),
           Date().timeIntervalSince1970 - cached.fetchedAt < sixMonths {
            if cached.songTitle == nil || cached.artistName == nil || cached.coverArt == nil {
                cached.songTitle = cached.songTitle ?? song.title
                cached.artistName = cached.artistName ?? song.artist
                cached.coverArt = cached.coverArt ?? song.coverArt
                save(cached)
            }
            return cached
        }

        if let lrc = await fetchFromNavidrome(song: song, serverId: serverId) {
            save(lrc); return lrc
        }

        if let lrc = await fetchFromLrcLib(song: song, serverId: serverId) {
            save(lrc); return lrc
        }

        let none = LyricsRecord(
            songId: song.id, serverId: serverId, source: "none",
            plainText: nil, syncedLrc: nil, isSynced: false,
            isInstrumental: false, language: nil,
            fetchedAt: Date().timeIntervalSince1970,
            songTitle: song.title, artistName: song.artist, coverArt: song.coverArt
        )
        save(none)
        return none
    }

    // MARK: - Navidrome

    private func fetchFromNavidrome(song: Song, serverId: String) async -> LyricsRecord? {
        guard let entry = try? await SubsonicAPIService.shared.getLyricsBySongId(songId: song.id),
              let lines = entry.line, !lines.isEmpty else { return nil }

        let plain = lines.map { $0.value }.joined(separator: "\n")
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var lrc: String? = nil
        if entry.synced {
            let lrcLines = lines.compactMap { line -> String? in
                guard let ms = line.start else { return nil }
                let min = (ms / 1000) / 60
                let sec = (ms / 1000) % 60
                let cs  = (ms % 1000) / 10
                return String(format: "[%02d:%02d.%02d] %@", min, sec, cs, line.value)
            }
            lrc = lrcLines.isEmpty ? nil : lrcLines.joined(separator: "\n")
        }

        return LyricsRecord(
            songId: song.id, serverId: serverId, source: "navidrome",
            plainText: plain, syncedLrc: lrc,
            isSynced: entry.synced && lrc != nil,
            isInstrumental: false, language: entry.lang,
            fetchedAt: Date().timeIntervalSince1970,
            songTitle: song.title, artistName: song.artist, coverArt: song.coverArt
        )
    }

    // MARK: - LRCLIB

    private func fetchFromLrcLib(song: Song, serverId: String) async -> LyricsRecord? {
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        var items: [URLQueryItem] = [URLQueryItem(name: "track_name", value: song.title)]
        if let a = song.artist  { items.append(URLQueryItem(name: "artist_name", value: a)) }
        if let a = song.album   { items.append(URLQueryItem(name: "album_name",  value: a)) }
        if let d = song.duration { items.append(URLQueryItem(name: "duration",   value: "\(d)")) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Shelv/1.0 (https://github.com/gatzenga/Shelv-Desktop)", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200
        else { return nil }

        guard let lrc = try? JSONDecoder().decode(LrcLibResponse.self, from: data) else { return nil }

        if lrc.instrumental == true {
            return LyricsRecord(
                songId: song.id, serverId: serverId, source: "lrclib",
                plainText: nil, syncedLrc: nil, isSynced: false,
                isInstrumental: true, language: nil,
                fetchedAt: Date().timeIntervalSince1970,
                songTitle: song.title, artistName: song.artist, coverArt: song.coverArt
            )
        }

        guard lrc.plainLyrics != nil || lrc.syncedLyrics != nil else { return nil }

        return LyricsRecord(
            songId: song.id, serverId: serverId, source: "lrclib",
            plainText: lrc.plainLyrics,
            syncedLrc: lrc.syncedLyrics,
            isSynced: lrc.syncedLyrics != nil,
            isInstrumental: false, language: nil,
            fetchedAt: Date().timeIntervalSince1970,
            songTitle: song.title, artistName: song.artist, coverArt: song.coverArt
        )
    }
}
