import Foundation
import Combine
import CryptoKit

// MARK: - Subsonic API Service

class SubsonicAPIService: ObservableObject {
    static let shared = SubsonicAPIService()

    private var config: ServerConfig?
    private let clientName = "shelv-desktop"
    private let apiVersion = "1.16.1"

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private init() {
        config = loadConfig()
    }

    // MARK: - Configuration

    func setConfig(_ config: ServerConfig) {
        self.config = config
        saveConfig(config)
    }

    func clearConfig() {
        self.config = nil
        UserDefaults.standard.removeObject(forKey: "serverConfig")
    }

    var hasConfig: Bool { config != nil && config!.isValid }
    var currentConfig: ServerConfig? { config }

    private func saveConfig(_ config: ServerConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "serverConfig")
        }
    }

    private func loadConfig() -> ServerConfig? {
        guard let data = UserDefaults.standard.data(forKey: "serverConfig"),
              let config = try? JSONDecoder().decode(ServerConfig.self, from: data) else {
            return nil
        }
        return config
    }

    // MARK: - Auth

    private func md5(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }

    private func authParams(config: ServerConfig) -> [URLQueryItem] {
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10)
        let token = md5(config.password + salt)
        return [
            URLQueryItem(name: "u", value: config.username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: String(salt)),
            URLQueryItem(name: "v", value: apiVersion),
            URLQueryItem(name: "c", value: clientName),
            URLQueryItem(name: "f", value: "json")
        ]
    }

    private func buildURL(endpoint: String, params: [URLQueryItem] = []) throws -> URL {
        guard let cfg = config else { throw APIError.notConfigured }
        var base = cfg.serverURL
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard var components = URLComponents(string: base + "/rest/" + endpoint) else {
            throw APIError.invalidURL
        }
        components.queryItems = authParams(config: cfg) + params
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    // MARK: - Generic Request

    private func fetch<T: Decodable>(_ type: T.Type, endpoint: String, params: [URLQueryItem] = []) async throws -> T {
        let url = try buildURL(endpoint: endpoint, params: params)
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.httpError
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    private func fetchSubsonic(endpoint: String, params: [URLQueryItem] = []) async throws -> SubsonicResponseBody {
        let wrapper = try await fetch(SubsonicResponse.self, endpoint: endpoint, params: params)
        let body = wrapper.subsonicResponse
        if body.status != "ok" {
            throw APIError.serverError(body.error?.message ?? "Unbekannter Fehler")
        }
        return body
    }

    // MARK: - Artists

    func getArtists() async throws -> [ArtistIndex] {
        let body = try await fetchSubsonic(endpoint: "getArtists")
        return body.artists?.index ?? []
    }

    func getArtist(id: String) async throws -> ArtistDetail {
        let body = try await fetchSubsonic(endpoint: "getArtist", params: [
            URLQueryItem(name: "id", value: id)
        ])
        guard let artist = body.artist else { throw APIError.missingData }
        return artist
    }

    // MARK: - Albums

    func getAlbumList(type: AlbumListType, size: Int = 50, offset: Int = 0) async throws -> [Album] {
        let body = try await fetchSubsonic(endpoint: "getAlbumList2", params: [
            URLQueryItem(name: "type", value: type.rawValue),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ])
        return body.albumList2?.album ?? []
    }

    func getAlbum(id: String) async throws -> AlbumDetail {
        let body = try await fetchSubsonic(endpoint: "getAlbum", params: [
            URLQueryItem(name: "id", value: id)
        ])
        guard let album = body.album else { throw APIError.missingData }
        return album
    }

    // MARK: - Songs / Mixes

    func getRandomSongs(size: Int = 100, genre: String? = nil) async throws -> [Song] {
        var params = [URLQueryItem(name: "size", value: "\(size)")]
        if let g = genre { params.append(URLQueryItem(name: "genre", value: g)) }
        let body = try await fetchSubsonic(endpoint: "getRandomSongs", params: params)
        return body.randomSongs?.song ?? []
    }

    func getTopSongs(artistName: String, count: Int = 50) async throws -> [Song] {
        let body = try await fetchSubsonic(endpoint: "getTopSongs", params: [
            URLQueryItem(name: "artist", value: artistName),
            URLQueryItem(name: "count", value: "\(count)")
        ])
        return body.topSongs?.song ?? []
    }

    // MARK: - Scrobble

    /// Notifies the server about a song being played.
    /// - Parameter songId: The ID of the song being played.
    /// - Parameter submission: `true` = actual scrobble (play count); `false` = now-playing notification only.
    func scrobble(songId: String, submission: Bool = true) async throws {
        _ = try await fetchSubsonic(endpoint: "scrobble", params: [
            URLQueryItem(name: "id", value: songId),
            URLQueryItem(name: "submission", value: submission ? "true" : "false")
        ])
    }

    // MARK: - Search

    func search(query: String) async throws -> SearchResult3 {
        let body = try await fetchSubsonic(endpoint: "search3", params: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "artistCount", value: "10"),
            URLQueryItem(name: "albumCount", value: "20"),
            URLQueryItem(name: "songCount", value: "30")
        ])
        return body.searchResult3 ?? SearchResult3(artist: [], album: [], song: [])
    }

    // MARK: - Starred

    func getStarred() async throws -> Starred2Result {
        let body = try await fetchSubsonic(endpoint: "getStarred2")
        return body.starred2 ?? Starred2Result(artist: nil, album: nil, song: nil)
    }

    func star(songId: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = songId { params.append(URLQueryItem(name: "id", value: id)) }
        if let id = albumId { params.append(URLQueryItem(name: "albumId", value: id)) }
        if let id = artistId { params.append(URLQueryItem(name: "artistId", value: id)) }
        _ = try await fetchSubsonic(endpoint: "star", params: params)
    }

    func unstar(songId: String? = nil, albumId: String? = nil, artistId: String? = nil) async throws {
        var params: [URLQueryItem] = []
        if let id = songId { params.append(URLQueryItem(name: "id", value: id)) }
        if let id = albumId { params.append(URLQueryItem(name: "albumId", value: id)) }
        if let id = artistId { params.append(URLQueryItem(name: "artistId", value: id)) }
        _ = try await fetchSubsonic(endpoint: "unstar", params: params)
    }

    // MARK: - Cover Art URL

    func coverArtURL(id: String, size: Int? = nil) -> URL? {
        guard let cfg = config else { return nil }
        var base = cfg.serverURL
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard var components = URLComponents(string: base + "/rest/getCoverArt") else { return nil }
        var items = authParams(config: cfg)
        items.append(URLQueryItem(name: "id", value: id))
        if let s = size { items.append(URLQueryItem(name: "size", value: "\(s)")) }
        components.queryItems = items
        return components.url
    }

    // MARK: - Stream URL

    func streamURL(songId: String) -> URL? {
        guard let cfg = config else { return nil }
        var base = cfg.serverURL
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        guard var components = URLComponents(string: base + "/rest/stream") else { return nil }
        var items = authParams(config: cfg)
        items.append(URLQueryItem(name: "id", value: songId))
        items.append(URLQueryItem(name: "format", value: "raw"))
        components.queryItems = items
        return components.url
    }

    // MARK: - Smart Mix Helpers (ported from iOS Shelv)

    /// Newest albums → all their songs (parallel fetch), shuffled.
    func getNewestSongs(albumCount: Int = 10) async throws -> [Song] {
        try await fetchSongsFromAlbums(type: .newest, albumCount: albumCount)
    }

    /// Frequently played albums → songs sorted by playCount descending.
    func getFrequentSongs(albumCount: Int = 50, limit: Int = 100) async throws -> [Song] {
        let albums = try await getAlbumList(type: .frequent, size: albumCount)
        let allSongs = try await withThrowingTaskGroup(of: [Song].self) { group in
            for album in albums {
                group.addTask { try await self.getAlbum(id: album.id).song }
            }
            var songs: [Song] = []
            for try await albumSongs in group { songs.append(contentsOf: albumSongs) }
            return songs
        }
        return Array(allSongs.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }.prefix(limit))
    }

    /// Recently played albums → songs in album order (album order preserved).
    func getRecentSongs(albumCount: Int = 50, limit: Int = 100) async throws -> [Song] {
        let albums = try await getAlbumList(type: .recentlyPlayed, size: albumCount)
        let indexed = Array(albums.enumerated())
        let songsByIndex = try await withThrowingTaskGroup(of: (Int, [Song]).self) { group in
            for (i, album) in indexed {
                group.addTask { (i, try await self.getAlbum(id: album.id).song) }
            }
            var result: [(Int, [Song])] = []
            for try await pair in group { result.append(pair) }
            return result
        }
        let ordered = songsByIndex.sorted { $0.0 < $1.0 }.flatMap { $0.1 }
        return Array(ordered.prefix(limit))
    }

    private func fetchSongsFromAlbums(type: AlbumListType, albumCount: Int) async throws -> [Song] {
        let albums = try await getAlbumList(type: type, size: albumCount)
        return try await withThrowingTaskGroup(of: [Song].self) { group in
            for album in albums {
                group.addTask { try await self.getAlbum(id: album.id).song }
            }
            var songs: [Song] = []
            for try await albumSongs in group { songs.append(contentsOf: albumSongs) }
            return songs
        }
    }

    // MARK: - Ping / Auth Test

    func ping() async throws {
        _ = try await fetchSubsonic(endpoint: "ping")
    }

    // MARK: - Server Info

    func getServerInfo() async throws -> ServerInfo {
        let body = try await fetchSubsonic(endpoint: "ping")
        return ServerInfo(
            apiVersion: body.version,
            serverVersion: body.serverVersion,
            serverType: body.type
        )
    }

    // MARK: - Library Scan

    func startScan() async throws -> ScanStatusBody {
        let body = try await fetchSubsonic(endpoint: "startScan")
        guard let status = body.scanStatus else { throw APIError.missingData }
        return status
    }

    func getScanStatus() async throws -> ScanStatusBody {
        let body = try await fetchSubsonic(endpoint: "getScanStatus")
        guard let status = body.scanStatus else { throw APIError.missingData }
        return status
    }

    // MARK: - All Artists (flattened)

    func getAllArtists() async throws -> [Artist] {
        let indices = try await getArtists()
        return indices.flatMap { $0.artist }
    }
}

// MARK: - Server Info

struct ServerInfo {
    let apiVersion: String
    let serverVersion: String?
    let serverType: String?
}

// MARK: - Album List Type

enum AlbumListType: String {
    case newest
    case recentlyPlayed = "recent"   // Subsonic API uses "recent", not "recentlyPlayed"
    case frequent
    case random
    case starred
    case alphabeticalByName
    case alphabeticalByArtist
    case byYear
    case byGenre
}

// MARK: - Errors

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case httpError
    case decodingError(Error)
    case serverError(String)
    case missingData

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Kein Server konfiguriert."
        case .invalidURL: return "Ungültige Server-URL."
        case .httpError: return "HTTP-Fehler beim Server."
        case .decodingError(let e): return "Antwort konnte nicht gelesen werden: \(e.localizedDescription)"
        case .serverError(let msg): return "Server-Fehler: \(msg)"
        case .missingData: return "Unerwartete leere Antwort."
        }
    }
}
