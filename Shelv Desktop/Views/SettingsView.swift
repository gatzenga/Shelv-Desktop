import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appColorScheme") private var colorScheme: AppColorScheme = .system

    var body: some View {
        TabView {
            ServerTab()
                .tabItem {
                    Image(systemName: "server.rack")
                    Text(tr("Server", "Server"))
                }
            AppearanceTab(colorScheme: $colorScheme)
                .tabItem {
                    Image(systemName: "paintpalette")
                    Text(tr("Appearance", "Darstellung"))
                }
            RecapTab()
                .tabItem {
                    Image(systemName: "calendar.badge.clock")
                    Text(tr("Recap", "Recap"))
                }
            CacheTab()
                .tabItem {
                    Image(systemName: "internaldrive")
                    Text(tr("Cache", "Cache"))
                }
            AboutTab()
                .tabItem {
                    Image(systemName: "info.circle")
                    Text(tr("Info", "Info"))
                }
        }
        .frame(width: 820, height: 660)
        .environmentObject(appState)
        .transaction { $0.animation = nil }
    }
}

struct ServerTab: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddServer = false
    @State private var serverToEdit: SubsonicServer?
    @State private var serverToDelete: SubsonicServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                ForEach(appState.serverStore.servers) { server in
                    ServerRow(
                        server: server,
                        isActive: appState.serverStore.activeServerID == server.id,
                        onActivate: { appState.switchServer(server) },
                        onEdit: { serverToEdit = server },
                        onDelete: { serverToDelete = server }
                    )
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 140)

            Divider()

            HStack {
                Button {
                    showAddServer = true
                } label: {
                    Label(tr("Add Server…", "Server hinzufügen…"), systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Spacer()
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet()
                .environmentObject(appState)
        }
        .sheet(item: $serverToEdit) { server in
            EditServerSheet(server: server)
                .environmentObject(appState)
        }
        .confirmationDialog(
            tr("Remove Server?", "Server entfernen?"),
            isPresented: Binding(get: { serverToDelete != nil }, set: { if !$0 { serverToDelete = nil } }),
            presenting: serverToDelete
        ) { server in
            Button(tr("Remove", "Entfernen"), role: .destructive) {
                appState.deleteServer(server)
                serverToDelete = nil
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) { serverToDelete = nil }
        } message: { server in
            Text(tr("\"\(server.displayName)\" will be removed and its credentials deleted.",
                    "\"\(server.displayName)\" wird entfernt und die Zugangsdaten gelöscht."))
        }
    }
}

struct ServerRow: View {
    let server: SubsonicServer
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? AnyShapeStyle(themeColor) : AnyShapeStyle(.tertiary))
                .font(.body)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)
                Text(server.username + " · " + server.baseURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let uid = server.remoteUserId {
                    Text("ID: \(uid)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isActive {
                Button(tr("Connect", "Verbinden")) { onActivate() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }

            Button { onEdit() } label: {
                Image(systemName: "pencil").font(.caption)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

struct AddServerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColor) private var themeColor

    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text(tr("Add Server", "Server hinzufügen"))
                .font(.title2.bold())

            serverForm

            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button(tr("Cancel", "Abbrechen")) { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button {
                    Task { await connect() }
                } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Text(tr("Connect", "Verbinden")) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || url.isEmpty || username.isEmpty || password.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    @ViewBuilder
    private var serverForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            formFieldLabel(tr("Server Name", "Servername"))
            TextField(tr("My Navidrome", "Mein Navidrome"), text: $name)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel("URL")
            TextField("https://music.example.com", text: $url)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel(tr("Username", "Benutzername"))
            TextField(tr("Username", "Benutzername"), text: $username)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            formFieldLabel(tr("Password", "Passwort"))
            SecureField(tr("Password", "Passwort"), text: $password)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func connect() async {
        isLoading = true
        errorMessage = nil
        let success = await appState.addServer(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            serverURL: url.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username,
            password: password
        )
        if success { dismiss() }
        else { errorMessage = appState.errorMessage ?? tr("Connection failed.", "Verbindung fehlgeschlagen.") }
        isLoading = false
    }
}

struct EditServerSheet: View {
    let server: SubsonicServer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String = ""

    init(server: SubsonicServer) {
        self.server = server
        _name = State(initialValue: server.name)
        _url = State(initialValue: server.baseURL)
        _username = State(initialValue: server.username)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(tr("Edit Server", "Server bearbeiten"))
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 10) {
                formFieldLabel(tr("Server Name", "Servername"))
                TextField(tr("My Navidrome", "Mein Navidrome"), text: $name)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                formFieldLabel("URL")
                TextField("https://music.example.com", text: $url)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                formFieldLabel(tr("Username", "Benutzername"))
                TextField(tr("Username", "Benutzername"), text: $username)
                    .textFieldStyle(.roundedBorder).autocorrectionDisabled()

                formFieldLabel(tr("Password", "Passwort"))
                SecureField(tr("Leave blank to keep current", "Leer lassen zum Beibehalten"), text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(tr("Cancel", "Abbrechen")) { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button(tr("Save", "Speichern")) {
                    var updated = server
                    updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    appState.serverStore.update(
                        server: updated,
                        password: password.isEmpty ? nil : password
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(url.isEmpty || username.isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

}

enum AppColorScheme: String, CaseIterable {
    case system = "System"
    case light = "Hell"
    case dark = "Dunkel"

    var displayName: String {
        switch self {
        case .system: return tr("System", "System")
        case .light:  return tr("Light", "Hell")
        case .dark:   return tr("Dark", "Dunkel")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

struct AppearanceTab: View {
    @Binding var colorScheme: AppColorScheme

    var body: some View {
        Form {
            Section(tr("Appearance", "Erscheinungsbild")) {
                Picker(tr("Mode", "Modus"), selection: $colorScheme) {
                    ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct CacheTab: View {
    @State private var cacheSize = "–"
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            Section(tr("Cover Images", "Cover-Bilder")) {
                LabeledContent(tr("Size", "Grösse")) {
                    Text(cacheSize).foregroundStyle(.secondary)
                }
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Label(tr("Clear Cache", "Cache leeren"), systemImage: "trash")
                }
                .confirmationDialog(tr("Clear Cache?", "Cache leeren?"), isPresented: $showClearConfirm) {
                    Button(tr("Clear", "Leeren"), role: .destructive) {
                        Task {
                            await ImageCacheService.shared.clearAll()
                            await recalculateCacheSize()
                        }
                    }
                    Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
                } message: {
                    Text(tr(
                        "All cached cover images will be deleted and reloaded next time they are displayed.",
                        "Alle zwischengespeicherten Cover-Bilder werden gelöscht und beim nächsten Anzeigen neu geladen."
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task { await recalculateCacheSize() }
    }

    private func recalculateCacheSize() async {
        let bytes = await ImageCacheService.shared.diskUsageBytes()
        cacheSize = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            : "0 KB"
    }
}

struct RecapTab: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var recapStore = RecapStore.shared
    @StateObject private var ckStatus = CloudKitSyncService.shared.status
    @Environment(\.openWindow) private var openWindow
    @Environment(\.themeColor) private var themeColor

    @AppStorage("recapEnabled")          private var recapEnabled          = false
    @AppStorage("iCloudSyncEnabled")     private var iCloudSyncEnabled     = true
    @AppStorage("recapWeeklyEnabled")    private var recapWeeklyEnabled    = true
    @AppStorage("recapMonthlyEnabled")   private var recapMonthlyEnabled   = true
    @AppStorage("recapYearlyEnabled")    private var recapYearlyEnabled    = true
    @AppStorage("recapWeeklyRetention")  private var recapWeeklyRetention  = 1
    @AppStorage("recapMonthlyRetention") private var recapMonthlyRetention = 12
    @AppStorage("recapYearlyRetention")  private var recapYearlyRetention  = 3
    @AppStorage("recapThreshold")        private var recapThreshold        = 30

    @State private var isPreparingExport = false
    @State private var exportError: String?
    @State private var isSyncingManually = false
    @State private var showPlayLog = false
    @State private var showRegistry = false
    @State private var showSyncLog = false
    @State private var showRecapLog = false
    @State private var showDBLog = false
    @State private var showMarkersLog = false
    @State private var showAdvanced = false
    @State private var showVerify = false
    @State private var totalPlays: Int = 0

    @State private var weekRetentionDraft: Int = 1
    @State private var monthRetentionDraft: Int = 12
    @State private var yearRetentionDraft: Int = 3
    @State private var pendingRetention: PendingRetentionChange?

    private struct PendingRetentionChange: Identifiable {
        let id = UUID()
        let type: RecapPeriod.PeriodType
        let newValue: Int
        let excess: Int
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("Enable Recap", "Recap aktivieren"), isOn: $recapEnabled)
            } footer: {
                if !recapEnabled {
                    Text(tr(
                        "Track your listening history and generate automatic playlists.",
                        "Hörhistorie aufzeichnen und automatische Playlists erstellen."
                    ))
                    .font(.caption).foregroundStyle(.secondary)
                }
            }

            if recapEnabled {
                Section(tr("Periods", "Perioden")) {
                    periodRow(title: tr("Weekly", "Wöchentlich"),
                              enabled: $recapWeeklyEnabled,
                              retention: $weekRetentionDraft, range: 1...52,
                              type: .week)
                    periodRow(title: tr("Monthly", "Monatlich"),
                              enabled: $recapMonthlyEnabled,
                              retention: $monthRetentionDraft, range: 1...24,
                              type: .month)
                    periodRow(title: tr("Yearly", "Jährlich"),
                              enabled: $recapYearlyEnabled,
                              retention: $yearRetentionDraft, range: 1...10,
                              type: .year)
                    Picker(tr("Count from", "Zählen ab"), selection: $recapThreshold) {
                        ForEach([10, 20, 30, 40, 50], id: \.self) { pct in
                            Text("\(pct)%").tag(pct)
                        }
                    }
                }

                Section(tr("Overview", "Übersicht")) {
                    LabeledContent(tr("Total plays", "Gesamte Plays")) {
                        Text("\(totalPlays)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button {
                        showVerify = true
                    } label: {
                        Label(tr("Sync with Navidrome", "Mit Navidrome abgleichen"),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                Section(tr("Database", "Datenbank")) {
                    Button {
                        guard !isPreparingExport else { return }
                        isPreparingExport = true
                        Task {
                            defer { isPreparingExport = false }
                            do {
                                let url = try await recapStore.exportBackupURL()
                                await runExportSavePanel(sourceURL: url)
                            } catch {
                                exportError = error.localizedDescription
                            }
                        }
                    } label: {
                        if isPreparingExport {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(tr("Export database", "Datenbank exportieren"), systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isPreparingExport)

                    Button {
                        runImportOpenPanel()
                    } label: {
                        Label(tr("Import database", "Datenbank importieren"), systemImage: "square.and.arrow.down")
                    }
                }

                Section(tr("iCloud Sync", "iCloud-Sync")) {
                    Toggle(tr("Enable iCloud Sync", "iCloud-Sync aktivieren"), isOn: $iCloudSyncEnabled)
                        .onChange(of: iCloudSyncEnabled) { _, _ in
                            Task { await CloudKitSyncService.shared.handleSyncEnabledChange() }
                        }

                    if !iCloudSyncEnabled {
                        Text(tr(
                            "Data stays local. Multiple devices may create duplicate recap playlists.",
                            "Daten bleiben lokal. Mehrere Geräte können doppelte Recap-Playlists erstellen."
                        ))
                        .font(.caption).foregroundStyle(.secondary)
                    } else if !ckStatus.accountAvailable {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tr("No iCloud account", "Kein iCloud-Konto"))
                                Text(tr("Use Export/Import as backup instead.",
                                        "Export/Import als Datensicherung nutzen."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent(tr("Last sync", "Letzter Sync")) {
                            if let date = ckStatus.lastSyncDate {
                                Text(date, style: .relative).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(tr("Never", "Noch nie")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent(tr("Pending uploads", "Ausstehende Uploads")) {
                            Text(ckStatus.pendingUploads > 0 ? "\(ckStatus.pendingUploads)" : "—")
                                .font(.caption)
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        LabeledContent(tr("Pending scrobbles", "Ausstehende Scrobbles")) {
                            Text(ckStatus.pendingScrobbles > 0 ? "\(ckStatus.pendingScrobbles)" : "—")
                                .font(.caption)
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Button {
                            guard !isSyncingManually else { return }
                            isSyncingManually = true
                            Task {
                                defer { isSyncingManually = false }
                                await CloudKitSyncService.shared.syncNow()
                            }
                        } label: {
                            Label {
                                Text(tr("Sync now", "Jetzt synchronisieren"))
                            } icon: {
                                if isSyncingManually {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                            }
                        }
                        .disabled(isSyncingManually)
                    }
                }

                Section(tr("Logs", "Logs")) {
                    Button {
                        showPlayLog = true
                    } label: {
                        Label(tr("Recent plays", "Letzte Plays"), systemImage: "list.bullet.clipboard")
                    }
                    Button {
                        showRegistry = true
                    } label: {
                        Label(tr("Registry", "Registry"), systemImage: "square.stack.3d.up")
                    }
                    Button {
                        showRecapLog = true
                    } label: {
                        Label(tr("Recap log", "Recap-Protokoll"), systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        showSyncLog = true
                    } label: {
                        Label(tr("Sync log", "Sync-Protokoll"), systemImage: "doc.text")
                    }
                    Button {
                        showDBLog = true
                    } label: {
                        Label(tr("Database errors", "Datenbank-Fehler"), systemImage: "exclamationmark.octagon")
                    }
                    Button {
                        showMarkersLog = true
                    } label: {
                        Label(tr("Auto-gen markers", "Auto-Gen-Marker"), systemImage: "checkmark.circle.badge.questionmark")
                    }
                }

                Section {
                    Button {
                        showAdvanced = true
                    } label: {
                        Label(tr("Advanced", "Erweitert"), systemImage: "slider.horizontal.2.square")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task(id: appState.serverStore.activeServerID) { await refreshTotalPlays() }
        .task {
            weekRetentionDraft  = recapWeeklyRetention
            monthRetentionDraft = recapMonthlyRetention
            yearRetentionDraft  = recapYearlyRetention
        }
        .alert(
            pendingRetention.map {
                tr(
                    "Delete \($0.excess) \(periodTypeName($0.type))?",
                    "\($0.excess) \(periodTypeName($0.type)) löschen?"
                )
            } ?? "",
            isPresented: Binding(
                get: { pendingRetention != nil },
                set: { if !$0 { pendingRetention = nil } }
            ),
            presenting: pendingRetention
        ) { pending in
            Button(tr("Delete", "Löschen"), role: .destructive) {
                guard let sid = appState.serverStore.activeServer?.stableId else { return }
                let type = pending.type
                let newValue = pending.newValue
                Task {
                    await recapStore.applyRetention(
                        periodType: type, limit: newValue, serverId: sid
                    )
                    setStoredRetention(type, newValue)
                }
                pendingRetention = nil
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {
                setDraft(pending.type, storedRetention(for: pending.type))
                pendingRetention = nil
            }
        } message: { _ in
            Text(tr(
                "These playlists will be permanently deleted from Navidrome and iCloud.",
                "Diese Playlists werden unwiderruflich aus Navidrome und iCloud gelöscht."
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: .recapRegistryUpdated)) { _ in
            Task { await refreshTotalPlays() }
        }
        .onChange(of: ckStatus.lastSyncDate) { _, _ in
            Task { await refreshTotalPlays() }
        }
        .alert(
            tr("Export failed", "Export fehlgeschlagen"),
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            presenting: exportError
        ) { _ in
            Button(tr("OK", "OK"), role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showPlayLog) {
            if let sid = appState.serverStore.activeServer?.stableId {
                RecapPlayLogView(serverId: sid)
            }
        }
        .sheet(isPresented: $showRegistry) {
            if let sid = appState.serverStore.activeServer?.stableId {
                RecapRegistryView(serverId: sid)
            }
        }
        .sheet(isPresented: $showSyncLog) {
            RecapSyncLogView()
        }
        .sheet(isPresented: $showRecapLog) {
            RecapCreationLogView()
        }
        .sheet(isPresented: $showDBLog) {
            RecapDBLogView()
        }
        .sheet(isPresented: $showMarkersLog) {
            if let sid = appState.serverStore.activeServer?.stableId {
                RecapMarkersLogView(serverId: sid)
            }
        }
        .sheet(isPresented: $showAdvanced, onDismiss: {
            Task { await refreshTotalPlays() }
        }) {
            if let sid = appState.serverStore.activeServer?.stableId {
                RecapAdvancedView(serverId: sid)
            }
        }
        .sheet(isPresented: $showVerify, onDismiss: {
            Task { await refreshTotalPlays() }
        }) {
            if let sid = appState.serverStore.activeServer?.stableId {
                RecapVerifyView(serverId: sid)
            }
        }
    }

    private func refreshTotalPlays() async {
        guard let sid = appState.serverStore.activeServer?.stableId else {
            totalPlays = 0
            return
        }
        totalPlays = await PlayLogService.shared.logCount(serverId: sid)
    }

    @ViewBuilder
    private func periodRow(title: String, enabled: Binding<Bool>,
                           retention: Binding<Int>, range: ClosedRange<Int>,
                           type: RecapPeriod.PeriodType) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(title, isOn: enabled)
            if enabled.wrappedValue {
                Stepper(value: retention, in: range) {
                    HStack {
                        Text(tr("Keep", "Behalten")).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(retention.wrappedValue)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .onChange(of: retention.wrappedValue) { _, newValue in
                    handleRetentionChange(type: type, newValue: newValue)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func storedRetention(for type: RecapPeriod.PeriodType) -> Int {
        switch type {
        case .week:  return recapWeeklyRetention
        case .month: return recapMonthlyRetention
        case .year:  return recapYearlyRetention
        }
    }

    private func setStoredRetention(_ type: RecapPeriod.PeriodType, _ value: Int) {
        switch type {
        case .week:  recapWeeklyRetention = value
        case .month: recapMonthlyRetention = value
        case .year:  recapYearlyRetention = value
        }
    }

    private func setDraft(_ type: RecapPeriod.PeriodType, _ value: Int) {
        switch type {
        case .week:  weekRetentionDraft = value
        case .month: monthRetentionDraft = value
        case .year:  yearRetentionDraft = value
        }
    }

    private func handleRetentionChange(type: RecapPeriod.PeriodType, newValue: Int) {
        let current = storedRetention(for: type)
        guard newValue != current else { return }
        guard newValue < current else {
            setStoredRetention(type, newValue)
            return
        }
        guard let sid = appState.serverStore.activeServer?.stableId else {
            setDraft(type, current)
            return
        }
        Task {
            let excess = await recapStore.excessRetentionCount(
                periodType: type, limit: newValue, serverId: sid
            )
            if excess > 0 {
                pendingRetention = PendingRetentionChange(type: type, newValue: newValue, excess: excess)
            } else {
                setStoredRetention(type, newValue)
            }
        }
    }

    private func periodTypeName(_ type: RecapPeriod.PeriodType) -> String {
        switch type {
        case .week:  return tr("weekly recaps", "Wochen-Recaps")
        case .month: return tr("monthly recaps", "Monats-Recaps")
        case .year:  return tr("yearly recaps", "Jahres-Recaps")
        }
    }

    @MainActor
    private func runExportSavePanel(sourceURL: URL) async {
        let panel = NSSavePanel()
        panel.title = tr("Save Recap database", "Recap-Datenbank speichern")
        panel.nameFieldStringValue = "shelv_recap_export.db"
        let response = await panel.beginSheetModalForCurrentWindow()
        guard response == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func runImportOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = tr("Import Recap database", "Recap-Datenbank importieren")
        panel.allowedContentTypes = [.data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let sid = appState.serverStore.activeServer?.stableId else { return }
        Task { await recapStore.importDatabase(from: url, serverId: sid) }
    }
}

private extension NSSavePanel {
    @MainActor
    func beginSheetModalForCurrentWindow() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                self.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            } else {
                let response = self.runModal()
                continuation.resume(returning: response)
            }
        }
    }
}

struct AboutTab: View {
    @Environment(\.themeColor) private var themeColor

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
            Text("Shelv Desktop")
                .font(.title2.bold())
            Text(appVersion)
                .foregroundStyle(.secondary)
            Text(tr("Navidrome / Subsonic Client for macOS", "Navidrome / Subsonic Client für macOS"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/gatzenga/Shelv-Desktop")!)
                Text("·").foregroundStyle(.secondary)
                Link(tr("Privacy Policy", "Datenschutz"), destination: URL(string: "https://gatzenga.github.io/Shelv-Desktop/privacy.html")!)
                Text("·").foregroundStyle(.secondary)
                Link(tr("Contact", "Kontakt"), destination: URL(string: "mailto:kontakt@vkugler.ch")!)
                Text("·").foregroundStyle(.secondary)
                Link("Discord", destination: URL(string: "https://discord.gg/a8VvwDeR")!)
            }
            .font(.callout)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}
