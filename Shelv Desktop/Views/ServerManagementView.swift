import SwiftUI

struct ServerManagementView: View {
    @EnvironmentObject var appState: AppState

    @State private var serverInfo: ServerInfo?
    @State private var scanStatus: ScanStatusBody?
    @State private var albumCount: Int?
    @State private var artistCount: Int?
    @State private var isLoadingInfo = true
    @State private var isScanning = false
    @State private var scanDone = false
    @State private var lastSyncDate: Date? = {
        let ts = UserDefaults.standard.double(forKey: "shelv_lastSync")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // MARK: Server Info
            Section(tr("Connected Server", "Verbundener Server")) {
                LabeledContent("URL") {
                    Text(appState.serverDisplayName)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent(tr("User", "Benutzer")) {
                    Text(appState.username)
                        .foregroundStyle(.secondary)
                }
                if isLoadingInfo {
                    LabeledContent(tr("Version", "Version")) {
                        ProgressView().controlSize(.small)
                    }
                } else if let info = serverInfo {
                    if let sv = info.serverVersion {
                        LabeledContent(tr("Version", "Version")) {
                            Text(sv + (info.serverType.map { " (\($0))" } ?? ""))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("API") {
                        Text(info.apiVersion)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: Bibliothek
            Section(tr("Library", "Bibliothek")) {
                if isLoadingInfo {
                    LabeledContent(tr("Albums", "Alben"))   { ProgressView().controlSize(.small) }
                    LabeledContent(tr("Artists", "Künstler")) { ProgressView().controlSize(.small) }
                    LabeledContent(tr("Tracks", "Titel"))   { ProgressView().controlSize(.small) }
                } else {
                    if let c = albumCount {
                        LabeledContent(tr("Albums", "Alben"))   { Text(String(c)).foregroundStyle(.secondary) }
                    }
                    if let c = artistCount {
                        LabeledContent(tr("Artists", "Künstler")) { Text(String(c)).foregroundStyle(.secondary) }
                    }
                    if let c = scanStatus?.count, c > 0 {
                        LabeledContent(tr("Tracks", "Titel"))   { Text(String(c)).foregroundStyle(.secondary) }
                    }
                }
            }

            // MARK: Synchronisation
            Section(tr("Synchronisation", "Synchronisation")) {
                LabeledContent(tr("Last Sync", "Letzte Synchronisation")) {
                    if let date = lastSyncDate {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(tr("Never", "Noch nie"))
                            .foregroundStyle(.secondary)
                    }
                }

                if isScanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(tr("Scanning library…", "Bibliothek wird gescannt…"))
                            .foregroundStyle(.secondary)
                    }
                } else if scanDone {
                    Label(tr("Sync complete", "Synchronisation abgeschlossen"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button {
                    Task { await runFullSync() }
                } label: {
                    Label(tr("Full Sync", "Vollständig synchronisieren"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(isScanning || !appState.isLoggedIn)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620)
        .padding(.vertical, 8)
        .task { await loadInfo() }
    }

    // MARK: - Load

    private func loadInfo() async {
        isLoadingInfo = true
        let api = SubsonicAPIService.shared

        async let infoTask   = api.getServerInfo()
        async let statusTask = api.getScanStatus()
        async let artistTask = api.getAllArtists()
        async let albumTask  = loadAlbumCount(api: api)

        serverInfo  = try? await infoTask
        scanStatus  = try? await statusTask
        artistCount = try? await artistTask.count
        albumCount  = await albumTask

        isLoadingInfo = false
    }

    /// Paginiert durch getAlbumList und gibt die Gesamtanzahl zurück.
    private func loadAlbumCount(api: SubsonicAPIService) async -> Int {
        var total = 0
        var offset = 0
        let pageSize = 500
        while true {
            guard let page = try? await api.getAlbumList(
                type: .alphabeticalByName, size: pageSize, offset: offset
            ) else { break }
            total += page.count
            if page.count < pageSize { break }
            offset += pageSize
        }
        return total
    }

    // MARK: - Full Sync

    private func runFullSync() async {
        isScanning = true
        scanDone = false
        errorMessage = nil

        do {
            var status = try await SubsonicAPIService.shared.startScan()
            while status.scanning {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                status = try await SubsonicAPIService.shared.getScanStatus()
            }
            scanStatus = status
            let now = Date()
            lastSyncDate = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "shelv_lastSync")
            scanDone = true
            // Counts nach Sync aktualisieren
            await loadInfo()
        } catch {
            errorMessage = error.localizedDescription
        }

        isScanning = false
    }
}

#Preview {
    ServerManagementView()
        .environmentObject(AppState.shared)
}
