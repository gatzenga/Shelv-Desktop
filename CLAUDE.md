# CLAUDE.md – Shelv Desktop

## Projekt-Überblick

Nativer macOS Navidrome/Subsonic Client (SwiftUI). Vollständig unabhängig von Shelv iOS.

## Build

Öffne `Shelv Desktop.xcodeproj` in Xcode und führe es auf einem Mac-Target aus. Kein SPM, keine externen Abhängigkeiten. Neue Swift-Dateien einfach im Filesystem anlegen — `PBXFileSystemSynchronizedRootGroup` übernimmt sie automatisch ins Projekt.

---

## Architektur

```
Shelv_DesktopApp  (@main)
  ├── AppState.shared          (ObservableObject @EnvironmentObject)
  │     ├── isLoggedIn, selectedSidebar: SidebarItem?, errorMessage
  │     ├── navigationPath: NavigationPath   ← global, ermöglicht Navigation aus PlayerBar
  │     ├── SubsonicAPIService.shared  — API-Calls, MD5+Salt-Auth (CryptoKit)
  │     └── AudioPlayerService.shared  — AVPlayer, 3-Queue-System, MPRemoteCommandCenter
  ├── WindowGroup → ContentView
  │     ├── LoginView          (wenn !isLoggedIn)
  │     └── MainWindowView     (NavigationSplitView + PlayerBarView)
  │           ├── SidebarView  (custom VStack, kein List — wegen Theme-Farbe)
  │           ├── NavigationStack(path: $appState.navigationPath)
  │           │     ├── .navigationDestination(for: Album.self)
  │           │     └── .navigationDestination(for: Artist.self)
  │           └── PlayerBarView (Footer, immer sichtbar)
  └── Settings Scene → SettingsView
  └── Window("Server Management") → ServerManagementView
```

---

## Schlüsseldateien

| Datei | Zweck |
|-------|-------|
| `Shelv_DesktopApp.swift` | Entry Point, Commands (Menüleiste), Settings Scene, ServerManagement Window, Keyboard Shortcuts |
| `ContentView.swift` | Login-Gate, MainWindowView, Theme-Color-Sync |
| `Models/SubsonicModels.swift` | Alle Codable-Modelle (Song, Album, Artist, AlbumDetail, QueueItem, SidebarItem, RepeatMode, LibrarySortOption, …) |
| `Services/SubsonicAPIService.swift` | API + MD5+Salt-Auth + Stream/CoverArt URLs + Scrobbling + Scan |
| `Services/AudioPlayerService.swift` | AVPlayer + 3-Queue-System + State-Persistenz + Remote Controls (@MainActor) |
| `ViewModels/AppState.swift` | Login/Logout, selectedSidebar, navigationPath |
| `ViewModels/LibraryViewModel.swift` | Albums (paginiert, 500/Seite), Artists, Sortierung, Favoriten, Playlists |
| `ViewModels/DiscoverViewModel.swift` | 4 Album-Shelves (newest/recent/frequent/random) + Smart Mixes |
| `Views/PlayerBarView.swift` | Footer-Player + QueuePopover + Seekbar + Volume |
| `Views/SidebarView.swift` | Custom VStack-Sidebar (kein List) |
| `Views/DiscoverView.swift` | Smart Mix Buttons + 4 Album-Scroll-Sektionen |
| `Views/AlbumsView.swift` | Grid + Suchfilter + Sortieroptionen |
| `Views/ArtistsView.swift` | Künstler-Grid mit Albumanzahl |
| `Views/SearchView.swift` | Echtzeit-Suche (SearchViewModel inline), Artists/Albums/Songs |
| `Views/AlbumDetailView.swift` | Album-Header + Tracklist mit Kontext-Menü |
| `Views/ArtistDetailView.swift` | Künstler-Header + Play/Shuffle/Heart-Buttons + Albumgrid nach Jahr sortiert |
| `Views/FavoritesView.swift` | Favoritenliste: Künstler-Grid, Alben-Grid, Titellist (conditional via `enableFavorites`) |
| `Views/PlaylistDetailView.swift` | Playlist-Header + Tracklist, Rename/Delete-Toolbar |
| `Views/AddToPlaylistPanel.swift` | Sheet zum Hinzufügen von Songs zu bestehender oder neuer Playlist (380×440) |
| `Views/SettingsView.swift` | Server-Info, Appearance, Cache-Verwaltung |
| `Views/ServerManagementView.swift` | Server-Version/API, Bibliothekszähler, Last Sync, Full Scan mit Polling |
| `Views/LoginView.swift` | Verbindungsformular mit Validierung |
| `Helpers/ImageCache.swift` | Actor-basierter Image-Cache (NSCache + Disk) + `CoverArtView` |
| `Helpers/AlbumContextMenu.swift` | `.albumContextMenu()` ViewModifier — Play, Shuffle, Play Next, Add to Queue, Favorit, Add to Playlist |
| `Helpers/ArtistContextMenu.swift` | `.artistContextMenu()` ViewModifier — gleiche Aktionen für Künstler, lädt Songs aller Alben parallel via `withThrowingTaskGroup` |
| `Helpers/AppTheme.swift` | 10 Themes, EnvironmentKey `\.themeColor`, `Color(hex:)` |
| `Helpers/FileManager+Extensions.swift` | `directorySize(at:)` für Cache-Größenanzeige |

---

## Modelle (SubsonicModels.swift)

Alle Datenstrukturen in einer Datei:
- `ServerConfig` — URL, Username, Password (Codable, UserDefaults)
- `Song`, `Album`, `AlbumDetail`, `Artist`, `ArtistDetail` — Codable Entities
- `QueueItem` — Wrapper für Songs in der `queue`-Liste (Desktop nutzt `[QueueItem]`, nicht `[Song]`)
- `Playlist` — `id`, `name`, `comment`, `songCount`, `duration`, `coverArt` (Codable, Identifiable, Hashable)
- `PlaylistDetail` — enthält `songs` (CodingKey `"entry"`) als `[Song]`
- `PlaylistsResult` — `playlist: [Playlist]` (CodingKey für API-Response)
- `SidebarItem` enum — `discover`, `albums`, `artists`, `favorites`, `search` (`.favorites` mit `icon: "heart"`)
- `LibrarySortOption` enum — Sortieroptionen für Alben/Künstler
- `RepeatMode` enum — `off`, `all`, `one` (mit `.toggled` und `.systemImage`)

---

## Warteschlangen-Logik (AudioPlayerService, @MainActor)

Drei getrennte Arrays — niemals mischen:

| Array | Typ | Bedeutung |
|-------|-----|-----------|
| `playNextQueue` | `[Song]` | "Als nächstes" — höchste Priorität |
| `queue` | `[QueueItem]` | Aktuelles Album / Kontext (currentIndex zeigt aktuellen Track) |
| `userQueue` | `[Song]` | Nutzer-Backlog (unbegrenzt) |

Abspielreihenfolge: `playNextQueue` → `queue[currentIndex+1...]` → `userQueue` (einer nach dem anderen, nicht als Block).

**Jump-Methoden** (springen zum Track):
- `jumpToPlayNextTrack(at:)` — entfernt Einträge vor Index aus playNextQueue, startet ihn
- `jumpToAlbumTrack(at:)` — löscht playNextQueue, setzt currentIndex, startet Track
- `jumpToUserQueueTrack(at:)` — löscht playNextQueue + verbleibende Album-Tracks + userQueue bis Index, startet ihn

**Scrobbling**: automatisch wenn 50% oder 4 Minuten gespielt — keine manuelle Implementierung nötig.

**State-Persistenz**: `saveState()` / `restoreState()` via UserDefaults + JSONEncoder. `playCurrent()` ruft `saveState()` bereits auf — **nicht nochmal danach aufrufen**. `resume()` nach Neustart nutzt `resumeTime`-Pattern in `loadURL()`.

**Seeking**: `AVURLAsset` mit Range-Header, `automaticallyWaitsToMinimizeStalling = false`, `seek()` setzt `currentTime` sofort (optimistisch) um Slider-Bounce zu verhindern.

---

## Navigation

- `appState.navigationPath: NavigationPath` ist der **einzige** NavigationPath — in `AppState`, nicht lokal in Views
- Sidebar-Wechsel setzt `navigationPath = NavigationPath()` zurück
- Value-based `NavigationLink(value:)` + `.navigationDestination(for:)` — kein view-destination-Link
- `Album` und `Artist` sind `Hashable` für den NavigationPath
- Aus `PlayerBarView` heraus navigieren: `appState.navigationPath.append(Album(...))` bzw. `Artist(...)`

---

## Theme / Farbe

- Custom `EnvironmentKey` `\.themeColor` — immer `@Environment(\.themeColor)` verwenden, **nie** `Color.accentColor` oder `AppTheme.color(for:)` direkt
- Gesetzt in `ContentView` via `.environment(\.themeColor, AppTheme.color(for: themeColorName))`
- `AppStorage("themeColor")` speichert den Farbnamen (String), Standard `"violet"`
- 10 Themes in `AppTheme.swift` (violet, blue, green, lightPink, lime, pink, pumpkin, red, teal, yellow)

---

## Cover Art

- Immer `CoverArtView` aus `Helpers/ImageCache.swift` verwenden — nie `AsyncImage`
- `ImageCache` ist ein Actor: NSCache (300 Items, 100 MB) + Disk-Cache in `~/Library/Caches/shelv_covers/`
- Deduplication via inflight task tracking, keine parallelen Requests für gleiche URL
- **Nie** `coverArtURL` mit leerem String aufrufen: `song.coverArt.flatMap { coverArtURL(id: $0, size:) }` — sonst unnötiger Netzwerkrequest

---

## Wichtige Konventionen

- **Kein TabView, kein NavigationView alt** — ausschliesslich `NavigationSplitView`
- **Kein `List` für Sidebar** — macOS `List(selection:)` ignoriert `.tint()`, immer custom VStack mit manuellem Selection-Tracking
- **Menüleiste** via `.commands {}` in der App-Struct, nicht programmatisch
- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor** — alle ObservableObject-Klassen sind implizit @MainActor
- **Swift 6 Concurrency in Closures**: `[weak self]` → `guard let self` vor dem Task, dann `Task { @MainActor [self] in }` mit explizitem Capture
- **Auth**: MD5(`password` + `salt`) via `CryptoKit.Insecure.MD5`
- **AlbumContextMenu**: ViewModifier `.albumContextMenu(album:)` aus `Helpers/AlbumContextMenu.swift` — für einheitliche Context Menus auf allen Albumkarten verwenden
- **ArtistContextMenu**: ViewModifier `.artistContextMenu(artist:)` aus `Helpers/ArtistContextMenu.swift` — lädt Songs aller Alben parallel via `withThrowingTaskGroup`, begrenzt auf 200 zufällige Titel
- **LibraryViewModel**: Album-Pagination 500 Items/Seite; Sortierung: alphabetisch, mostPlayed, recentlyAdded, year; **wird als `@EnvironmentObject` von `MainWindowView` gehalten und weitergegeben** — nie als `@StateObject` in Unterviews anlegen
- **DiscoverViewModel**: 4 Shelves (newest/recent/frequent/random) + 3 Smart Mix Typen
- **Lokalisierung**: `tr(_ en: String, _ de: String)` — nie hartcodierte Strings in Views
- **Playlist-Integration über Notification**: Songs zu Playlist hinzufügen via `NotificationCenter.default.post(name: .addSongsToPlaylist, object: [songId])` — `MainWindowView` fängt es auf und zeigt `AddToPlaylistPanel`
- **Menü-Erweiterung**: Neue Menüpunkte in bestehendes "View"-Menü via `CommandGroup(after: .sidebar)` — **kein** `CommandMenu("Ansicht")` (erzeugt Duplikat)
- **Tab-Leiste entfernen**: `NSWindow.allowsAutomaticWindowTabbing = false` in `App.init()` — verhindert "Show Tab Bar"/"Show All Tabs"-Einträge
- **withThrowingTaskGroup Rückgabetyp**: Bei Typ-Inferenzproblemen immer explizit annotieren: `{ group -> [Song] in ... }` (Swift-Compiler kann sonst `[Any]` inferieren)
- **ArtistDetail vs. Artist**: API liefert zwei getrennte Typen; für `toggleStarArtist()` aus `ArtistDetail` ein `Artist`-Objekt konstruieren: `Artist(id: detail.id, name: detail.name, albumCount: detail.albumCount, coverArt: detail.coverArt, starred: ...)`
- **navigationDestination + EnvironmentObject**: Bei `navigationDestination(for:)` immer `.environmentObject(libraryStore)` explizit anhängen — wird nicht automatisch vererbt
- **playShuffled**: Mischt alle Songs, startet bei Index 0 der gemischten Liste; Snapshot speichert die gemischte Reihenfolge — beim Deaktivieren von Shuffle bleibt diese zufällige Reihenfolge erhalten, kein Titelverlust

---

## UserDefaults-Keys

### Player-State
| Key | Inhalt |
|-----|--------|
| `shelv_mac_queue` | `[QueueItem]` JSON |
| `shelv_mac_currentIndex` | Int |
| `shelv_mac_playNextQueue` | `[Song]` JSON |
| `shelv_mac_userQueue` | `[Song]` JSON |
| `shelv_mac_currentTime` | Double (Sekunden) |

### App-State
| Key | Inhalt |
|-----|--------|
| `serverConfig` | `ServerConfig` JSON (URL, Username, Password) |
| `themeColor` | String (Farbname) |
| `enableFavorites` | Bool — Favoriten-Feature aktiv (Sidebar-Eintrag, Herz-Buttons, Context Menus) |
| `enablePlaylists` | Bool — Playlists-Feature aktiv (Sidebar-Sektion, Context Menus) |

---

## Was vermieden werden soll

- Kein `AsyncImage` — immer `CoverArtView` mit `ImageCache` verwenden
- Keine feste Farbe — immer `@Environment(\.themeColor)`, nie `Color.accentColor`
- Kein `List` für Sidebar — macOS ignoriert `.tint()` auf `List(selection:)`, immer custom VStack
- Kein `TabView`, kein altes `NavigationView` — ausschliesslich `NavigationSplitView`
- `coverArtURL` nie mit leerem String aufrufen — immer `song.coverArt.flatMap { coverArtURL(id: $0, size:) }`
- `saveState()` nicht manuell nach Jump-/Add-Methoden aufrufen — bereits intern
- Lokalen `navigationPath` in Views anlegen — immer `appState.navigationPath` verwenden
- Keine hardcodierten Strings in Views — immer `tr("EN", "DE")` verwenden
- `LibraryViewModel` nicht als `@StateObject` in Unterviews erstellen — immer als `@EnvironmentObject` von `MainWindowView` beziehen
- `CommandMenu("Ansicht")` nicht verwenden — erzeugt Duplikat-Menü; stattdessen `CommandGroup(after: .sidebar)`
- Referenzprojekte nicht verändern — nur lesen

---

## Referenzprojekte (nur lesen, nicht verändern)

- `/Users/vasco/Repositorys/AzuraPlayer` — iOS Radio App (MVVM, AVPlayer Pattern)
- `/Users/vasco/Repositorys/AzuraPlayer Mac` — macOS Version (NSApp, AppKit Patterns)
- `/Users/vasco/Repositorys/Shelv` — iOS Shelv (gleiche Subsonic API, gleiches 3-Queue-Konzept)
