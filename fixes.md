
1. Echte Bugs
#	Datei	Zeile	Problem	Wichtigkeit
1	SearchView.swift	140, 160	coverArtURL(id: artist.coverArt ?? "", size: 50) — bei nil wird leerer String übergeben, erzeugt sinnlosen Netzwerk-Request. CLAUDE.md verbietet das explizit. Muss .flatMap nutzen.	Hoch
2	ContentView.swift	94–101	Toast Race Condition: Jeder Toast startet eigenen 2s-Sleep-Task. Kommt ein zweiter Toast während der erste noch sichtbar ist, löscht der erste Task den zweiten vorzeitig.	Mittel
3	PlayerBarView.swift	181	Next-Button .disabled-Logik prüft nur queue und currentIndex, ignoriert aber playNextQueue und userQueue. Button erscheint disabled obwohl noch Songs in diesen Queues sind.	Hoch
4	AudioPlayerService.swift	258–265	addPlayNext() im Shuffle-Modus: Song wird via insertRandomlyInShuffledQueue an zufälliger Stelle eingefügt statt direkt nach dem aktuellen Track. "Als nächstes" spielt nicht als nächstes.	Hoch
5	AudioPlayerService.swift	297–304	addToUserQueue() im Shuffle-Modus: Gleiche Logik wie Bug #4 — Song geht an zufällige Position statt ans Ende der Warteschlange.	Mittel
6	SubsonicModels.swift	287–290	QueueItem.id nutzt song.id. Wenn derselbe Song mehrfach in der Queue ist (z.B. Playlist mit Wiederholungen), kollidieren die IDs. SwiftUI ForEach kann Einträge falsch rendern oder überspringen.	Mittel
7	SearchView.swift	110–114	onChange(of: vm.query) sucht erst ab 2 Zeichen. Löscht der User auf 1 Zeichen, bleiben alte Ergebnisse der vorherigen Suche sichtbar — irreführend.	Niedrig
8	PlayerBarView.swift	108–111	Favoriten-Toggle ruft nur libraryStore.toggleStarSong() auf, aber nie player.setCurrentSongStarred(). Now-Playing-Info im System und Queue-Status bleiben veraltet. setCurrentSongStarred() existiert, wird aber nirgends aufgerufen.	Mittel
9	PlaylistDetailView.swift:121–125	songs.remove(at: index) nach await-API-Call: Index kann veraltet sein, potentieller Crash (out of bounds). Muss ID-basiert entfernen.	Hoch
10	AlbumDetailView.swift:158	.task ohne id:-Parameter. Bei Album→Album-Navigation lädt der Task nicht neu. Fix: .task(id: albumId)	Mittel
11	ArtistDetailView.swift:116	Gleicher Fehler: .task ohne .task(id: artistId).	Mittel
Sonst ist alles drin.






2. Sicherheitsprobleme
#	Datei	Zeile	Problem	Wichtigkeit
1	SubsonicAPIService.swift	38–41	saveConfig() speichert ServerConfig inkl. Passwort im Klartext in UserDefaults unter Key "serverConfig". Obwohl ServerStore das Passwort korrekt im Keychain ablegt, wird es parallel bei jedem setConfig()-Aufruf erneut in UserDefaults geschrieben.	Hoch
2	KeychainService.swift	9–18	SecItemAdd Rückgabewert wird ignoriert. Wenn Keychain-Speicherung fehlschlägt, wird kein Fehler gemeldet — Passwort geht lautlos verloren.	Niedrig





3. Inkonsistenzen (UI/Verhalten)
#	Stelle A	Stelle B	Problem	Wichtigkeit
1	AlbumDetailView.swift:99 (Herz = .red)	ArtistDetailView.swift:79 (Herz = themeColor)	Favoriten-Herz-Farbe: Album + PlayerBar nutzen Rot, Artist nutzt Theme-Color. Sollte einheitlich sein.	Mittel
2	ArtistDetailView.swift:51 (Play-Button .tint(themeColor))	AlbumDetailView.swift:73 und PlaylistDetailView.swift:64 (kein .tint)	Play-Button-Farbe: Artist nutzt Theme-Color-Tint, Album und Playlist nutzen System-Akzentfarbe.	Mittel
3	AlbumDetailView.swift TrackRow Context Menu	FavoritesView.swift FavoriteSongRow Context Menu	TrackRow und PlaylistTrackRow haben kein "Abspielen" im Context-Menu (nur Doppelklick). FavoriteSongRow und SearchSongRow haben "Abspielen" als ersten Eintrag.	Hoch
4	AlbumDetailView.swift:136–139 (Toast bei Play Next / Add to Queue)	FavoritesView.swift:74–77 und SearchView.swift:91–93 (kein Toast)	Toast-Feedback nur in AlbumDetailView. FavoritesView und SearchView zeigen kein Toast bei "Als nächstes" / "Zur Warteschlange".	Mittel
5	SidebarView.swift:141 (LocalizedStringKey(item.rawValue))	SidebarItem rawValues sind deutsch ("Entdecken", "Alben" etc.)	Sidebar zeigt immer Deutsch, unabhängig von der Systemsprache. LocalizedStringKey findet keinen Übersetzungs-Key und nutzt den deutschen rawValue direkt.	Hoch
6	Shelv_DesktopApp.swift:43	Alle anderen Menüs nutzen tr()	CommandMenu("Profil") — hartcodiert deutsch, nicht lokalisiert.	Niedrig
7	DiscoverView.swift:306	—	ThemePickerPopover .help(option.nameDE) — Tooltip zeigt immer deutschen Namen, auch bei englischer Systemsprache.	Niedrig
8	AppTheme.swift:76–80 (formFieldLabel als freie Funktion)	SettingsView.swift:282–286 (editFieldLabel als private Methode)	Identische Implementierung, zwei verschiedene Namen. editFieldLabel sollte gelöscht und formFieldLabel überall genutzt werden.	Niedrig


4. Fehlende Fehlerbehandlung
#	Datei	Zeile	Problem	Wichtigkeit
1	ArtistDetailView.swift	172	playAll(): } catch {} — Fehler beim Laden aller Artist-Songs wird komplett verschluckt. User bekommt kein Feedback wenn es nicht funktioniert.	Mittel
2	SearchView.swift	259	search(): } catch { } — Suchfehler (Netzwerk, Server) werden komplett verschluckt. Kein Hinweis für den User.	Mittel
3	AlbumContextMenu.swift	15, 20, 26, 35	Jede Context-Menu-Aktion: guard let detail = try? await ... else { return } — bei Netzwerkfehler passiert einfach nichts, User wartet und sieht kein Feedback.	Mittel
4	ArtistContextMenu.swift	68–82	fetchSongs(): Fehler beim Laden von Artist-Alben werden verschluckt, Context-Menu-Aktion tut lautlos nichts.	Mittel

5. State- & Persistenz-Probleme
#	Datei	Zeile	Problem	Wichtigkeit
1	AudioPlayerService.swift	20	volume wird nicht in saveState()/restoreState() berücksichtigt. Nach App-Neustart steht Lautstärke immer auf 1.0 (Maximum).	Hoch
2	AudioPlayerService.swift	34	shuffleSnapshot wird nicht persistiert. Nach App-Neustart ist isShuffled = true, aber Snapshot ist nil. toggleShuffle() zum Deaktivieren kann Originalreihenfolge nicht wiederherstellen — Queue-Chaos.	Hoch
3	AudioPlayerService.swift	35	isPlayingFromPlayNext wird nicht persistiert. Nach Neustart während PlayNext-Wiedergabe verhält sich playPrevious() falsch (springt nicht zurück zum Album-Track).	Niedrig
4	DiscoverViewModel.swift	—	DiscoverViewModel ist @StateObject in DiscoverView, nicht geteilt. Bei Serverwechsel (wenn Sidebar auf Discover bleibt) zeigt die View weiterhin Daten des alten Servers bis man weg- und zurücknavigiert.	Mittel
5	SubsonicAPIService.swift	38–41	saveConfig() speichert nach jeder Serveraktivierung ein neues "serverConfig" in UserDefaults — obwohl die Migration in ServerStore diesen Legacy-Key explizit löscht. Erzeugt Endlosschleife Legacy-Key → Migration → Neuanlage.	Mittel





6. Code-Qualität / Kleinere Probleme
#	Datei	Zeile	Problem	Wichtigkeit
1	SubsonicAPIService.swift	399–408	APIError.errorDescription alle auf Deutsch hartcodiert. Sollte tr() nutzen für konsistente Zweisprachigkeit.	Niedrig
2	FavoritesView.swift	93	.refreshable auf macOS ScrollView hat keine sichtbare Wirkung (kein Pull-to-Refresh auf macOS). Toter Code.	Niedrig
3	LibraryViewModel.swift	39–68	loadAlbums() bei Sort-Wechsel: Wechsel von .name zu .year lädt alle Alben komplett neu von der API, obwohl die gleichen Daten nur lokal umsortiert werden müssten.	Niedrig
4	AlbumContextMenu.swift / ArtistContextMenu.swift	—	Jede einzelne Context-Menu-Aktion (Play, Shuffle, Play Next, Queue, Playlist) startet einen eigenen API-Call zum Laden der Album-/Artist-Details. Bei 5 Aktionen = 5 potenzielle Requests für dasselbe Album. Kein Caching.	Niedrig
5	AlbumDetailView.swift	162	albumId as String? — unnötiger Cast, albumId ist bereits String. Kein Bug, aber verwirrend.	Niedrig

Zusammenfassung: 8 echte Bugs, 2 Sicherheitsprobleme, 8 Inkonsistenzen, 4 fehlende Fehlerbehandlungen, 5 State-Probleme, 5 Code-Qualitäts-Themen. Die kritischsten sind: Passwort in UserDefaults (#S1), Shuffle-Play-Next-Bug (#B4), fehlende Volume-Persistenz (#P1), Shuffle-Snapshot-Persistenz (#P2), fehlendes "Abspielen" im Context-Menu (#I3), und die Sidebar-Lokalisierung (#I5).

