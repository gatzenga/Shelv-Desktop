import SwiftUI

let appLang: String = Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
func tr(_ en: String, _ de: String, _ lang: String = appLang) -> String { lang == "de" ? de : en }

extension Notification.Name {
    static let addSongsToPlaylist = Notification.Name("shelv.addSongsToPlaylist")
    static let showToast = Notification.Name("shelv.showToast")
    static let recapRegistryUpdated = Notification.Name("shelv.recapRegistryUpdated")
}

@main
struct Shelv_DesktopApp: App {
    @StateObject private var appState = AppState.shared
    private let _playTracker = PlayTracker.shared
    @AppStorage("appColorScheme") private var storedColorScheme: AppColorScheme = .system
    @AppStorage("themeColor") private var themeColorName: String = "violet"
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let d = UserDefaults.standard
        if d.string(forKey: "transcodingWifiCodec") == "aac" { d.set("raw", forKey: "transcodingWifiCodec") }
        if d.string(forKey: "transcodingCellularCodec") == "aac" { d.set("raw", forKey: "transcodingCellularCodec") }
        if d.string(forKey: "transcodingDownloadCodec") == "aac" { d.set("raw", forKey: "transcodingDownloadCodec") }
        UserDefaults.standard.register(defaults: [
            "recapWeeklyEnabled": true,
            "recapMonthlyEnabled": true,
            "recapYearlyEnabled": true,
            "enableDownloads": false,
            "offlineModeEnabled": false,
            "maxBulkDownloadStorageGB": 10,
            "transcodingEnabled": false,
            "transcodingWifiCodec": "raw",
            "transcodingWifiBitrate": 256,
            "transcodingCellularCodec": "raw",
            "transcodingCellularBitrate": 128,
            "transcodingDownloadCodec": "raw",
            "transcodingDownloadBitrate": 192,
        ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(LyricsStore.shared)
                .environmentObject(CloudKitSyncService.shared.status)
                .environmentObject(RecapStore.shared)
                .environmentObject(LibraryViewModel.shared)
                .environmentObject(DownloadStore.shared)
                .environmentObject(OfflineModeService.shared)
                .frame(minWidth: 900, minHeight: 600)
                .task { await LyricsStore.shared.setup() }
                .task {
                    await PlayLogService.shared.setup()
                    await DownloadDatabase.shared.setup()
                    await DownloadService.shared.setup()
                    if let active = appState.serverStore.activeServer {
                        await DownloadStore.shared.setActiveServer(active.stableId)
                    }
                    // DB ist jetzt bereit — sicherstellt dass Downloads geladen werden,
                    // auch wenn setActiveServer oben durch den Guard blockiert wurde
                    await DownloadStore.shared.reload()
                    let api = SubsonicAPIService.shared
                    for server in appState.serverStore.servers where server.remoteUserId == nil {
                        guard let pw = appState.serverStore.password(for: server) else { continue }
                        let cfg = ServerConfig(serverURL: server.baseURL, username: server.username, password: pw)
                        api.setConfig(cfg)
                        do {
                            let uid = try await api.authLogin()
                            var updated = server
                            updated.remoteUserId = uid
                            appState.serverStore.update(server: updated, password: nil)
                            print("[ServerID] Backfill OK \(server.displayName): \(uid)")
                        } catch {
                            print("[ServerID] Backfill FAILED \(server.displayName): \(error)")
                        }
                    }
                    if let active = appState.serverStore.activeServer {
                        appState.serverStore.activate(server: active)
                        print("[ServerID] Active server stableId: \(active.stableId)")
                    }
                    await CloudKitSyncService.shared.setup()
                }
                .task(id: appState.serverStore.activeServerID) {
                    guard let server = appState.serverStore.activeServer else { return }
                    await RecapStore.shared.setup(serverId: server.stableId)
                    await DownloadStore.shared.setActiveServer(server.stableId)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await CloudKitSyncService.shared.syncNow() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    Task { await CloudKitSyncService.shared.syncNow() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .recapRegistryUpdated)) { _ in
                    guard let server = appState.serverStore.activeServer else { return }
                    Task { await RecapStore.shared.loadEntries(serverId: server.stableId) }
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 760)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .appInfo) {
                Button(tr("About Shelv", "Über Shelv")) {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            CommandMenu(tr("Profile", "Profil")) {
                if appState.isLoggedIn, let active = appState.serverStore.activeServer {
                    Text(active.displayName)
                    Text(appState.username)
                        .foregroundStyle(.secondary)
                } else {
                    Text(tr("Not logged in", "Nicht angemeldet"))
                        .foregroundStyle(.secondary)
                }
                Divider()
                ServerManagementMenuItem()
                Divider()
                Button(tr("Log Out", "Abmelden")) {
                    appState.logout()
                }
                .disabled(!appState.isLoggedIn)
            }

            CommandGroup(replacing: .help) {
                Link(tr("Shelv on GitHub", "Shelv auf GitHub"), destination: URL(string: "https://github.com/gatzenga/Shelv-Desktop")!)
                Link(tr("Navidrome Documentation", "Navidrome Dokumentation"), destination: URL(string: "https://www.navidrome.org/docs/")!)
                Divider()
                Link(tr("Developer Website", "Developer-Website"), destination: URL(string: "https://vkugler.app")!)
                Link(tr("Privacy Policy", "Datenschutz"), destination: URL(string: "https://vkugler.app/shelv_privacy.html")!)
                Link(tr("Contact", "Kontakt"), destination: URL(string: "mailto:contact@vkugler.app")!)
                Link("Discord", destination: URL(string: "https://discord.gg/UdJK5mpmZu")!)
                Divider()
                Link(tr("Support my work", "Support my work"), destination: URL(string: "https://ko-fi.com/Shelv")!)
            }

            CommandMenu(tr("Playback", "Wiedergabe")) {
                Button(tr("Play / Pause", "Abspielen / Pause")) {
                    AppState.shared.player.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                Divider()
                Button(tr("Next Track", "Nächster Titel")) {
                    AppState.shared.player.playNext()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(tr("Previous Track", "Vorheriger Titel")) {
                    AppState.shared.player.playPrevious()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Divider()
                PlaybackSettingsMenuItem()
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Toggle(isOn: Binding(get: { enableFavorites }, set: { enableFavorites = $0 })) {
                    Text(tr("Show Favorites", "Favoriten anzeigen"))
                }
                Toggle(isOn: Binding(get: { enablePlaylists }, set: { enablePlaylists = $0 })) {
                    Text(tr("Show Playlists", "Wiedergabelisten anzeigen"))
                }
                Divider()
                OfflineModeMenuItem()
            }
        }

        Window(tr("Playback Settings", "Wiedergabe-Einstellungen"), id: "playback-settings") {
            PlaybackSettingsWindow()
                .environmentObject(appState)
                .environmentObject(LyricsStore.shared)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .defaultSize(width: 820, height: 660)

        Window(tr("Insights", "Insights"), id: "insights") {
            InsightsView()
                .environmentObject(appState)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .windowResizability(.contentSize)

        Window(tr("Recap", "Recap"), id: "recap") {
            RecapView()
                .environmentObject(appState)
                .environmentObject(RecapStore.shared)
                .environmentObject(LibraryViewModel.shared)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
        .windowResizability(.contentSize)

        Window(tr("Manage Servers", "Server verwalten"), id: "server-management") {
            ServerManagementView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 660, height: 660)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .tint(AppTheme.color(for: themeColorName))
                .environment(\.themeColor, AppTheme.color(for: themeColorName))
        }
    }
}

struct PlaybackSettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Playback Settings", "Wiedergabe-Einstellungen")) {
            openWindow(id: "playback-settings")
        }
    }
}

struct ServerManagementMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Manage Servers…", "Server verwalten…")) {
            openWindow(id: "server-management")
        }
    }
}

struct InsightsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Insights…", "Insights…")) {
            openWindow(id: "insights")
        }
    }
}

struct RecapMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Recap…", "Recap…")) {
            openWindow(id: "recap")
        }
    }
}

struct OfflineModeMenuItem: View {
    @ObservedObject private var offlineMode = OfflineModeService.shared
    @AppStorage("enableDownloads") private var enableDownloads = false

    var body: some View {
        Toggle(
            tr("Offline Mode", "Offline-Modus"),
            isOn: Binding(
                get: { offlineMode.isOffline },
                set: { if $0 { offlineMode.enterOfflineMode() } else { offlineMode.exitOfflineMode() } }
            )
        )
        .disabled(!enableDownloads)
    }
}
