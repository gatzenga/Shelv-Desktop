# CLAUDE.md – Shelv Desktop

## Build

Öffne `Shelv Desktop.xcodeproj` in Xcode, Mac-Target. Kein SPM. Neue Swift-Dateien einfach anlegen — `PBXFileSystemSynchronizedRootGroup` übernimmt sie automatisch.

---

## Architektur

```
Shelv_DesktopApp  (@main)
  ├── AppState.shared          (ObservableObject, @EnvironmentObject)
  │     ├── isLoggedIn, selectedSidebar: SidebarItem?, selectedPlaylist: Playlist?
  │     ├── navigationPath: NavigationPath   ← einziger globaler Pfad
  │     ├── serverStore: ServerStore
  │     └── player: AudioPlayerService.shared
  └── WindowGroup → ContentView
        ├── LoginView          (wenn !isLoggedIn)
        └── MainWindowView     (NavigationSplitView + PlayerBarView + ToastOverlay)
              ├── LibraryViewModel  @StateObject hier gehalten, via .environmentObject weitergegeben
              ├── SidebarView       (custom VStack — kein List wegen macOS .tint()-Bug)
              └── NavigationStack(path: $appState.navigationPath)
                    ├── .navigationDestination(for: Album.self)  → AlbumDetailView
                    └── .navigationDestination(for: Artist.self) → ArtistDetailView
```

Settings Scene + Window("Server Management") separat in `Shelv_DesktopApp.swift`.

---

## Navigation — KRITISCH

`selectedSidebar` und `selectedPlaylist` müssen immer zusammen gesetzt werden. `MainWindowView.sectionRoot` zeigt entweder die Playlist-Detail-View (wenn `selectedPlaylist != nil`) **oder** den Sidebar-Switch — nie beides.

```swift
// Sidebar-Klick: immer dieses Pattern
appState.selectedPlaylist = nil        // ← zuerst!
appState.selectedSidebar = .albums
appState.navigationPath = NavigationPath()

// Playlist-Klick: immer dieses Pattern
appState.selectedSidebar = nil
appState.selectedPlaylist = playlist
appState.navigationPath = NavigationPath()

// Programmatisch zu Künstler/Album navigieren (z. B. aus PlayerBar):
appState.selectedPlaylist = nil
appState.selectedSidebar = .artists
appState.navigationPath = NavigationPath()
appState.navigationPath.append(Artist(...))   // alle 4 Zeilen synchron — kein Task nötig
```

- `navigationDestination(for:)` muss `.environmentObject(libraryStore)` explizit erhalten — wird nicht automatisch vererbt
- `Album` und `Artist` sind `Hashable` für NavigationPath

---

## Theme / Appearance

```swift
// Akzentfarbe — immer @Environment, nie Color.accentColor
@Environment(\.themeColor) private var themeColor

// Appearance (Light/Dark/System) — enum in SettingsView.swift
enum AppColorScheme: String, CaseIterable { case system, light, dark }
@AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
// Gesetzt via NSApp.appearance = storedColorScheme.nsAppearance in ContentView
```

---

## Queue-Logik (AudioPlayerService, @MainActor)

| Array | Typ | Priorität |
|-------|-----|-----------|
| `playNextQueue` | `[Song]` | Höchste |
| `queue` | `[QueueItem]` | Normal (currentIndex = aktueller Track) |
| `userQueue` | `[Song]` | Niedrigste |

Abspielreihenfolge: `playNextQueue[0]` → `queue[currentIndex+1...]` → `userQueue[0]`.

Desktop nutzt `[QueueItem]` für `queue` (nicht `[Song]` wie iOS) — nie mischen.

**Jump-Methoden:**
- `jumpToPlayNextTrack(at:)` — entfernt Einträge vor Index, startet ihn
- `jumpToAlbumTrack(at:)` — setzt currentIndex, startet Track
- `jumpToUserQueueTrack(at:)` — verschiebt in queue, startet ihn

**Shuffle:** `playShuffled()` mischt alle Songs, Snapshot bewahrt Original-Reihenfolge. Beim Deaktivieren wird Snapshot wiederhergestellt — kein Titelverlust.

**Scrobbling:** Automatisch bei 50 % oder 4 Minuten — keine manuelle Implementierung.

**State:** `saveState()` wird intern von `playCurrent()`, Jump- und Queue-Methoden aufgerufen — **nicht nochmal manuell aufrufen**.

**UserDefaults-Keys:** `shelv_mac_queue`, `shelv_mac_currentIndex`, `shelv_mac_playNextQueue`, `shelv_mac_userQueue`, `shelv_mac_currentTime`, `shelv_mac_isShuffled`, `shelv_mac_repeatMode`

**App-State-Keys:** `shelv_mac_servers`, `shelv_mac_active_server`, `themeColor`, `appColorScheme`, `enableFavorites`, `enablePlaylists`

---

## Wichtige Konventionen

- **`@ObservedObject private var player = AudioPlayerService.shared`** in Views — nicht `@EnvironmentObject`, weil `AppState.objectWillChange` bei Player-Updates nicht feuert
- **Cover Art:** Nur `CoverArtView` aus `Helpers/ImageCache.swift` — nie `AsyncImage`. `coverArtURL` nie mit leerem String: `song.coverArt.flatMap { coverArtURL(id: $0, size:) }`
- **Lokalisierung:** Immer `tr("EN", "DE")` — nie hardcodierte Strings
- **LibraryViewModel:** `@StateObject` in `MainWindowView`, `@EnvironmentObject` in allen Unterviews. `AlbumDetailView` und `ArtistDetailView` haben eigene inline ViewModels (`AlbumDetailViewModel`, `ArtistDetailViewModel`) als `@StateObject`
- **Context Menus:** `.albumContextMenu(album:)` und `.artistContextMenu(artist:)` ViewModifier aus Helpers verwenden
- **ArtistContextMenu** nutzt `withThrowingTaskGroup(of: [Song].self) { group -> [Song] in ... }` — Rückgabetyp explizit annotieren, sonst inferiert Swift `[Any]`
- **ArtistDetail → Artist:** Für `toggleStarArtist()` aus `ArtistDetail` konstruieren: `Artist(id: detail.id, name: detail.name, albumCount: detail.albumCount, coverArt: detail.coverArt, starred: ...)`
- **Playlist via Notification:** `NotificationCenter.default.post(name: .addSongsToPlaylist, object: [songId])` — `MainWindowView` zeigt `AddToPlaylistPanel`
- **Toast via Notification:** `NotificationCenter.default.post(name: .showToast, object: "Text")` — 2-Sekunden-Overlay
- **Neue Menüpunkte:** `CommandGroup(after: .sidebar)` — nie `CommandMenu("Ansicht")` (Duplikat)
- **Multi-Server:** `appState.addServer(...)` / `appState.switchServer(_:)`. Legacy-Migration von `serverConfig` läuft automatisch in `ServerStore.init()`
- **Seeking:** `automaticallyWaitsToMinimizeStalling = false`, `seek()` setzt `currentTime` optimistisch für Slider-Bounce-Prävention

---

## Referenzprojekte (nur lesen, nicht verändern)

- `/Users/vasco/Repositorys/AzuraPlayer` — iOS Radio App
- `/Users/vasco/Repositorys/AzuraPlayer Mac` — macOS Version
- `/Users/vasco/Repositorys/Shelv` — iOS Shelv (gleiche API, gleiches Queue-Konzept)
