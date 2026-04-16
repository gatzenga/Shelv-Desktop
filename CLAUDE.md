# CLAUDE.md – Shelv Desktop

## Build

Open `Shelv Desktop.xcodeproj` in Xcode, Mac target. No SPM. New Swift files can be added directly — `PBXFileSystemSynchronizedRootGroup` picks them up automatically.

---

## Architecture

```
Shelv_DesktopApp  (@main)
  ├── AppState.shared          (ObservableObject, @EnvironmentObject)
  │     ├── isLoggedIn, selectedSidebar: SidebarItem?, selectedPlaylist: Playlist?
  │     ├── navigationPath: NavigationPath   ← single global path
  │     ├── serverStore: ServerStore
  │     └── player: AudioPlayerService.shared
  └── WindowGroup → ContentView
        ├── LoginView          (when !isLoggedIn)
        └── MainWindowView     (NavigationSplitView + PlayerBarView + ToastOverlay)
              ├── LibraryViewModel  @StateObject held here, passed via .environmentObject
              ├── SidebarView       (custom VStack — no List due to macOS .tint() bug)
              └── NavigationStack(path: $appState.navigationPath)
                    ├── .navigationDestination(for: Album.self)  → AlbumDetailView
                    └── .navigationDestination(for: Artist.self) → ArtistDetailView
```

Settings Scene + Window("Server Management") are separate scenes in `Shelv_DesktopApp.swift`.

---

## Navigation — CRITICAL

`selectedSidebar` and `selectedPlaylist` must always be set together. `MainWindowView.sectionRoot` shows either the playlist detail view (when `selectedPlaylist != nil`) **or** the sidebar switch — never both.

```swift
// Sidebar tap: always this pattern
appState.selectedPlaylist = nil        // ← first!
appState.selectedSidebar = .albums
appState.navigationPath = NavigationPath()

// Playlist tap: always this pattern
appState.selectedSidebar = nil
appState.selectedPlaylist = playlist
appState.navigationPath = NavigationPath()

// Navigate programmatically to artist/album (e.g. from PlayerBar):
appState.selectedPlaylist = nil
appState.selectedSidebar = .artists
appState.navigationPath = NavigationPath()
appState.navigationPath.append(Artist(...))   // all 4 lines synchronously — no Task needed
```

- `navigationDestination(for:)` must receive `.environmentObject(libraryStore)` explicitly — it is not inherited automatically
- `Album` and `Artist` conform to `Hashable` for use in NavigationPath

---

## Theme / Appearance

```swift
// Accent color — always @Environment, never Color.accentColor
@Environment(\.themeColor) private var themeColor

// Appearance (Light/Dark/System) — enum in SettingsView.swift
enum AppColorScheme: String, CaseIterable { case system, light, dark }
@AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
// Applied via NSApp.appearance = storedColorScheme.nsAppearance in ContentView
```

- Play buttons use `.tint(themeColor)` with `.borderedProminent` style
- Favorite heart icons are always `.red` — never `themeColor`

---

## Queue Logic (AudioPlayerService, @MainActor)

| Array | Type | Priority |
|-------|------|----------|
| `playNextQueue` | `[Song]` | Highest |
| `queue` | `[QueueItem]` | Normal (currentIndex = current track) |
| `userQueue` | `[Song]` | Lowest |

Playback order: `playNextQueue[0]` → `queue[currentIndex+1...]` → `userQueue[0]`.

Desktop uses `[QueueItem]` for `queue` (not `[Song]` like iOS) — never mix them.

**QueueItem** has a UUID-based `id` (not `song.id`) — prevents ForEach collisions when the same song appears multiple times. All internal comparisons in `toggleShuffle` and similar methods use `item.song.id`.

**Jump methods:**
- `jumpToPlayNextTrack(at:)` — removes entries before index, starts it
- `jumpToAlbumTrack(at:)` — sets currentIndex, starts track
- `jumpToUserQueueTrack(at:)` — moves into queue, starts it

**Shuffle:** `playShuffled()` shuffles all songs, snapshot preserves original order. Deactivating restores the snapshot — no tracks are lost. `addPlayNext` and `addToUserQueue` update the shuffle snapshot automatically.

**Scrobbling:** Automatic at 50% or 4 minutes — no manual implementation needed.

**State:** `saveState()` is called internally by `playCurrent()`, jump methods, and queue mutations — **do not call it manually**. Persisted state includes volume, shuffle snapshot (all three queues), and `isPlayingFromPlayNext`.

**UserDefaults keys:** `shelv_mac_queue`, `shelv_mac_currentIndex`, `shelv_mac_playNextQueue`, `shelv_mac_userQueue`, `shelv_mac_currentTime`, `shelv_mac_isShuffled`, `shelv_mac_repeatMode`, `shelv_mac_volume`, `shelv_mac_shuffleSnapshotQueue`, `shelv_mac_shuffleSnapshotPN`, `shelv_mac_shuffleSnapshotUQ`, `shelv_mac_shuffleSnapshotIndex`, `shelv_mac_isPlayingFromPlayNext`

**App state keys:** `shelv_mac_servers`, `shelv_mac_active_server`, `themeColor`, `appColorScheme`, `enableFavorites`, `enablePlaylists`

---

## Security

- Passwords are stored **only in the Keychain** via `KeychainService` — never in UserDefaults or `SubsonicAPIService`
- `SubsonicAPIService.setConfig()` holds credentials in memory only; `clearConfig()` nils them
- `KeychainService.save()` returns `@discardableResult Bool`

---

## Conventions

- **`@ObservedObject private var player = AudioPlayerService.shared`** in views — not `@EnvironmentObject`, because `AppState.objectWillChange` does not fire on player updates
- **Cover art:** Always use `CoverArtView` from `Helpers/ImageCache.swift` — never `AsyncImage`. Never pass an empty string to `coverArtURL`: `song.coverArt.flatMap { SubsonicAPIService.shared.coverArtURL(id: $0, size:) }`
- **Localization:** Always `tr("EN", "DE")` — never hardcoded strings. `SidebarItem.displayName` uses `tr()`, raw values are English
- **LibraryViewModel:** `@StateObject` in `MainWindowView`, `@EnvironmentObject` in all child views. `AlbumDetailView` and `ArtistDetailView` have their own inline view models (`AlbumDetailViewModel`, `ArtistDetailViewModel`) as `@StateObject`
- **Detail views:** Use `.task(id: albumId)` / `.task(id: artistId)` — not plain `.task` — so they reload when the ID changes (e.g. navigating between items)
- **Context menus:** Use `.albumContextMenu(album:)` and `.artistContextMenu(artist:)` ViewModifiers from Helpers. `AlbumContextMenu` uses a `withAlbumSongs(errorMsg:_:)` helper to avoid duplicate `getAlbum()` fetches. "Play" is always the first menu item, followed by a `Divider()`
- **ArtistContextMenu** uses `withThrowingTaskGroup(of: [Song].self) { group -> [Song] in ... }` — annotate the return type explicitly, otherwise Swift infers `[Any]`
- **ArtistDetail → Artist:** When calling `toggleStarArtist()`, construct from `ArtistDetail`: `Artist(id: detail.id, name: detail.name, albumCount: detail.albumCount, coverArt: detail.coverArt, starred: ...)`
- **Playlist via notification:** `NotificationCenter.default.post(name: .addSongsToPlaylist, object: [songId])` — `MainWindowView` presents `AddToPlaylistPanel`
- **Toast via notification:** `NotificationCenter.default.post(name: .showToast, object: "Text")` — 2-second overlay. Always post a toast on Play Next / Add to Queue actions and on async errors
- **New menu items:** `CommandGroup(after: .sidebar)` — never `CommandMenu("View")` (creates duplicate)
- **Multi-server:** `appState.addServer(...)` / `appState.switchServer(_:)`. Legacy migration from `serverConfig` runs automatically in `ServerStore.init()`
- **Seeking:** `automaticallyWaitsToMinimizeStalling = false`, `seek()` sets `currentTime` optimistically to prevent slider bounce
- **Race conditions in async mutations:** Capture IDs before `await` when using them after the suspension point (e.g. `let songId = song.id` before `await` in playlist removal)
- **No comments in code** — self-explanatory names only; no `// MARK:`, no `///`, no inline section labels

---

## Reference Projects (read-only)

- `/Users/vasco/Repositorys/AzuraPlayer` — iOS Radio App
- `/Users/vasco/Repositorys/AzuraPlayer Mac` — macOS version
- `/Users/vasco/Repositorys/Shelv` — iOS Shelv (same API, same queue concept)
