# CLAUDE.md – Shelv Desktop

## Projekt-Überblick

Nativer macOS Navidrome/Subsonic Client (SwiftUI). Vollständig unabhängig von Shelv iOS.

## Build

Öffne `Shelv Desktop.xcodeproj` in Xcode und führe es auf einem Mac-Target aus. Kein SPM, keine externen Abhängigkeiten.

## Architektur

```
Shelv_DesktopApp  (@main)
  ├── AppState.shared          (ObservableObject @EnvironmentObject)
  │     ├── selectedSidebar: SidebarItem?
  │     ├── navigationPath: NavigationPath   ← global, ermöglicht Navigation aus PlayerBar
  │     ├── SubsonicAPIService.shared  — API-Calls, MD5-Auth (CryptoKit)
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
```

## Schlüsseldateien

| Datei | Zweck |
|-------|-------|
| `Shelv_DesktopApp.swift` | Entry Point, Commands (Menüleiste), Settings Scene |
| `ContentView.swift` | Login-Gate, MainWindowView mit NavigationStack |
| `Models/SubsonicModels.swift` | Alle Codable-Modelle (Song, Album, Artist, …) |
| `Services/SubsonicAPIService.swift` | API + MD5-Auth + Stream/CoverArt URLs |
| `Services/AudioPlayerService.swift` | AVPlayer + 3-Queue-System + State-Persistenz |
| `ViewModels/AppState.swift` | Login/Logout, selectedSidebar, navigationPath |
| `Views/PlayerBarView.swift` | Footer-Player + QueuePopover |
| `Views/SidebarView.swift` | Custom VStack-Sidebar (kein List) |
| `Helpers/ImageCache.swift` | CoverArtView + NSCache |
| `Helpers/AlbumContextMenu.swift` | `.albumContextMenu()` ViewModifier |

## Warteschlangen-Logik (AudioPlayerService)

Drei getrennte Arrays — niemals mischen:

| Array | Bedeutung |
|-------|-----------|
| `playNextQueue: [Song]` | "Als nächstes" — höchste Priorität |
| `queue: [QueueItem]` | Aktuelles Album / Kontext (currentIndex zeigt aktuellen Track) |
| `userQueue: [Song]` | Nutzer-Backlog, max. 200 Songs |

Abspielreihenfolge: `playNextQueue` → `queue[currentIndex+1...]` → `userQueue` (einer nach dem anderen, nicht als Block).

**Jump-Methoden** (löschen alles davor):
- `jumpToPlayNextTrack(at:)` — entfernt playNextQueue-Einträge vor Index
- `jumpToAlbumTrack(at:)` — löscht playNextQueue, setzt currentIndex
- `jumpToUserQueueTrack(at:)` — löscht playNextQueue + verbleibende Album-Tracks + userQueue bis Index

**State-Persistenz**: `saveState()` / `restoreState()` via UserDefaults + JSONEncoder. `playCurrent()` ruft `saveState()` bereits auf — nicht nochmal danach aufrufen. `resume()` nach Neustart nutzt `resumeTime`-Pattern in `loadURL()`.

## Navigation

- `appState.navigationPath: NavigationPath` ist der einzige NavigationPath — in `AppState`, nicht lokal in Views
- Sidebar-Wechsel setzt `navigationPath = NavigationPath()` zurück
- Value-based `NavigationLink(value:)` + `.navigationDestination(for:)` — kein view-destination-Link
- `Album` und `Artist` sind `Hashable` für den NavigationPath
- Aus `PlayerBarView` heraus navigieren: `appState.navigationPath.append(Album(...))` bzw. `Artist(...)`

## Theme / Farbe

- Custom `EnvironmentKey` `\.themeColor` — immer `@Environment(\.themeColor)` verwenden, nie `Color.accentColor`
- Gesetzt in `ContentView` via `.environment(\.themeColor, AppTheme.color(for: themeColorName))`
- `AppStorage("themeColor")` speichert den Farbnamen (String)

## Wichtige Konventionen

- **Kein TabView, kein NavigationView alt** — ausschliesslich `NavigationSplitView`
- **Kein `List` für Sidebar** — macOS `List(selection:)` ignoriert `.tint()`, immer custom VStack
- **Menüleiste** via `.commands {}` in der App-Struct, nicht programmatisch
- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor** — alle ObservableObject-Klassen sind implizit @MainActor
- **Swift 6 Concurrency in Closures**: `[weak self]` → `guard let self` vor dem Task, dann `Task { @MainActor [self] in }` mit explizitem Capture
- **Seeking**: `AVURLAsset` mit Range-Header, `automaticallyWaitsToMinimizeStalling = false`, `seek()` setzt `currentTime` sofort (optimistisch) um Slider-Bounce zu verhindern
- **Auth**: MD5(`password` + `salt`) via `CryptoKit.Insecure.MD5`
- **CoverArt-URLs**: Immer `song.coverArt.flatMap { coverArtURL(id: $0, size:) }` — nie `coverArtURL(id: coverArt ?? "")`, sonst geht ein Netzwerkrequest mit leerem ID raus
- **Neue Swift-Dateien** einfach im Filesystem anlegen — `PBXFileSystemSynchronizedRootGroup` übernimmt sie automatisch

## UserDefaults-Keys

### Player-State
| Key | Inhalt |
|-----|--------|
| `shelv_mac_queue` | `[Song]` JSON |
| `shelv_mac_currentIndex` | Int |
| `shelv_mac_playNextQueue` | `[Song]` JSON |
| `shelv_mac_userQueue` | `[Song]` JSON |
| `shelv_mac_currentTime` | Double (Sekunden) |

### App-State
| Key | Inhalt |
|-----|--------|
| `serverConfig` | `ServerConfig` JSON (URL, Username, Password) |
| `themeColor` | String (Farbname) |

## Was vermieden werden soll

- Kein `AsyncImage` — immer `CoverArtView` mit `ImageCache` verwenden
- Keine feste Farbe — immer `@Environment(\.themeColor)` verwenden, nie `Color.accentColor`
- Kein `List` für Sidebar — macOS ignoriert `.tint()` auf `List(selection:)`, immer custom VStack
- Kein `TabView`, kein altes `NavigationView` — ausschliesslich `NavigationSplitView`
- `coverArtURL` nie mit leerem String aufrufen — immer `song.coverArt.flatMap { coverArtURL(id: $0, size:) }`
- `saveState()` nicht manuell nach Jump-/Add-Methoden aufrufen — bereits intern drin
- Referenzprojekte nicht verändern — nur lesen

## Referenzprojekte (nur lesen, nicht verändern)

- `/Users/vasco/Repositorys/AzuraPlayer` — iOS Radio App (MVVM, AVPlayer Pattern)
- `/Users/vasco/Repositorys/AzuraPlayer Mac` — macOS Version (NSApp, AppKit Patterns)
- `/Users/vasco/Repositorys/Shelv` — iOS Shelv (Subsonic API Konzept)
