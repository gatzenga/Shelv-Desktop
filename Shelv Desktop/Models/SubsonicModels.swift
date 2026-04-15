import Foundation

// MARK: - Server Configuration

struct ServerConfig: Codable, Equatable {
    var serverURL: String
    var username: String
    var password: String

    var isValid: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }
}

// MARK: - Subsonic Server (multi-server)

struct SubsonicServer: Identifiable, Codable {
    let id: UUID
    var name: String
    var baseURL: String
    var username: String

    var displayName: String {
        name.isEmpty ? baseURL : name
    }

    init(name: String = "", baseURL: String, username: String) {
        self.id = UUID()
        self.name = name
        self.baseURL = baseURL
        self.username = username
    }
}

// MARK: - Subsonic API Response Wrapper

struct SubsonicResponse: Codable {
    let subsonicResponse: SubsonicResponseBody

    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct SubsonicResponseBody: Codable {
    let status: String
    let version: String
    let serverVersion: String?  // Navidrome-specific
    let type: String?           // Navidrome-specific
    let error: SubsonicError?
    let artists: ArtistsResult?
    let artist: ArtistDetail?
    let albumList2: AlbumListResult?
    let album: AlbumDetail?
    let randomSongs: RandomSongsResult?
    let topSongs: RandomSongsResult?   // returned by getTopSongs endpoint
    let searchResult3: SearchResult3?
    let starred2: Starred2Result?
    let scanStatus: ScanStatusBody?
    let playlists: PlaylistsResult?
    let playlist: PlaylistDetail?
}

// MARK: - Scan Status

struct ScanStatusBody: Codable {
    let scanning: Bool
    let count: Int?
}

struct SubsonicError: Codable {
    let code: Int
    let message: String
}

// MARK: - Artists

struct ArtistsResult: Codable {
    let index: [ArtistIndex]
}

struct ArtistIndex: Codable, Identifiable {
    // Navidrome's API does not include `id` on the letter-group level.
    // We use `name` (the letter, e.g. "A") as the stable identifier.
    var id: String { name }
    let name: String
    let artist: [Artist]

    enum CodingKeys: String, CodingKey {
        case name, artist
    }
}

struct Artist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
    let starred: String?

    var isStarred: Bool { starred != nil }
}

// MARK: - Artist Detail (with Albums)

struct ArtistDetail: Codable, Identifiable {
    let id: String
    let name: String
    let albumCount: Int?
    let coverArt: String?
    let album: [Album]
}

// MARK: - Albums

struct AlbumListResult: Codable {
    let album: [Album]
}

struct Album: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    let starred: String?
    let playCount: Int?

    var isStarred: Bool { starred != nil }

    var displayYear: String {
        guard let y = year else { return "" }
        return "\(y)"
    }
}

// MARK: - Album Detail (with Songs)

struct AlbumDetail: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    let genre: String?
    let starred: String?
    let song: [Song]

    var isStarred: Bool { starred != nil }
}

// MARK: - Songs / Tracks

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let artistId: String?
    let album: String?
    let albumId: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
    let discNumber: Int?
    let year: Int?
    let genre: String?
    var starred: String?   // mutable so AudioPlayerService can update star state in-place
    let playCount: Int?
    let bitRate: Int?
    let contentType: String?
    let suffix: String?

    var isStarred: Bool { starred != nil }

    var durationString: String {
        guard let d = duration else { return "--:--" }
        let m = d / 60
        let s = d % 60
        return String(format: "%d:%02d", m, s)
    }

    var displayTrack: String {
        guard let t = track else { return "" }
        return "\(t)"
    }
}

struct RandomSongsResult: Codable {
    let song: [Song]
}

// MARK: - Search

struct SearchResult3: Codable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// MARK: - Starred

struct Starred2Result: Codable {
    let artist: [Artist]?
    let album: [Album]?
    let song: [Song]?
}

// MARK: - Playlists

struct Playlist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let comment: String?
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
}

struct PlaylistDetail: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let comment: String?
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
    let songs: [Song]?

    enum CodingKeys: String, CodingKey {
        case id, name, comment, songCount, duration, coverArt
        case songs = "entry"
    }
}

struct PlaylistsResult: Codable {
    let playlist: [Playlist]
}

// MARK: - Sidebar Navigation

enum SidebarItem: String, CaseIterable, Identifiable {
    case discover = "Entdecken"
    case albums = "Alben"
    case artists = "Künstler"
    case favorites = "Favoriten"
    case search = "Suche"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .discover: return "sparkles"
        case .albums: return "square.grid.2x2"
        case .artists: return "music.mic"
        case .favorites: return "heart"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - Sort Options

enum LibrarySortOption: String, CaseIterable {
    case name = "name"
    case mostPlayed = "mostPlayed"
    case recentlyAdded = "recentlyAdded"
    case year = "year"

    var label: String {
        switch self {
        case .name:          return tr("Name (A–Z)", "Name (A–Z)")
        case .mostPlayed:    return tr("Most Played", "Meist gespielt")
        case .recentlyAdded: return tr("Recently Added", "Zuletzt hinzugefügt")
        case .year:          return tr("Year (newest)", "Jahr (neueste zuerst)")
        }
    }
}

// MARK: - Queue

struct QueueItem: Identifiable, Equatable {
    let id: String
    var song: Song   // var so star state can be updated in the queue
}

// MARK: - Repeat Mode

enum RepeatMode: CaseIterable {
    case off, all, one

    var nextMode: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    var systemImage: String {
        switch self {
        case .off:  return "repeat"
        case .all:  return "repeat"
        case .one:  return "repeat.1"
        }
    }
}
