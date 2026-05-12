import SwiftUI

private struct BatchProgressSection: View {
    @ObservedObject private var downloadStore = DownloadStore.shared
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        if let progress = downloadStore.batchProgress {
            Section(tr("Active Downloads", "Aktive Downloads")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(progress.completed) / \(progress.total)")
                            .monospacedDigit()
                        Spacer()
                        if progress.failed > 0 {
                            Text(tr("\(progress.failed) failed", "\(progress.failed) fehlgeschlagen"))
                                .foregroundStyle(.red)
                        }
                    }
                    ProgressView(value: progress.fraction)
                        .tint(themeColor)
                    HStack {
                        Spacer()
                        Button(tr("Cancel download", "Download abbrechen")) {
                            Task { await DownloadService.shared.cancelBatch() }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .font(.caption)
                    }
                }
            }
        }
    }
}

private struct DownloadStatsSection: View {
    @ObservedObject private var downloadStore = DownloadStore.shared
    @ObservedObject private var libraryStore = LibraryViewModel.shared
    @State private var stats: DownloadStorageStats?

    var body: some View {
        Section(tr("Statistics", "Statistik")) {
            if let stats {
                LabeledContent(tr("Used", "Belegt"),
                               value: ByteCountFormatter.string(fromByteCount: stats.totalBytes, countStyle: .file))
                if let free = stats.freeDiskBytes {
                    LabeledContent(tr("Free on device", "Frei auf Gerät"),
                                   value: ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                }
                LabeledContent(tr("Songs", "Titel"), value: "\(stats.songCount)")
                LabeledContent(tr("Albums", "Alben"), value: "\(stats.albumCount)")
                LabeledContent(tr("Artists", "Künstler"), value: "\(stats.artistCount)")
            } else {
                ProgressView()
            }
        }
        .task { await refreshStats() }
        .onChange(of: downloadStore.totalBytes) { _, _ in Task { await refreshStats() } }
        .onChange(of: downloadStore.songs.count) { _, _ in Task { await refreshStats() } }
    }

    @MainActor private func refreshStats() async {
        let counts = Dictionary(uniqueKeysWithValues: libraryStore.albums.compactMap { album -> (String, Int)? in
            guard let c = album.songCount else { return nil }
            return (album.id, c)
        })
        let artistAlbums: [String: Set<String>] = Dictionary(
            grouping: libraryStore.albums.compactMap { album -> (String, String)? in
                guard let aid = album.artistId else { return nil }
                return (aid, album.id)
            },
            by: { $0.0 }
        ).mapValues { Set($0.map(\.1)) }
        stats = await DownloadStore.shared.computeStats(albumSongCounts: counts, artistAlbumIds: artistAlbums)
    }
}

struct DownloadsTab: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var offlineMode = OfflineModeService.shared
    @AppStorage("enableDownloads") private var enableDownloads = false
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @AppStorage("maxBulkDownloadStorageGB") private var maxBulkStorageGB = 10

    @State private var showBulkSheet = false
    @State private var showDeleteAllConfirm = false

    private var maxAllowedStorageGB: Int {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return 500 }
        let gb = Int(bytes / 1_000_000_000)
        return max(10, (gb / 10) * 10)
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("Enable Downloads", "Downloads aktivieren"), isOn: $enableDownloads)
                Toggle(tr("Offline Mode", "Offline-Modus"),
                       isOn: Binding(
                            get: { offlineMode.isOffline },
                            set: { newValue in
                                if newValue { offlineMode.enterOfflineMode() } else { offlineMode.exitOfflineMode() }
                            }
                       ))
                    .disabled(!enableDownloads)
            }

            if enableDownloads {
                BatchProgressSection()

                Section(tr("Bulk Download", "Massen-Download")) {
                    Button {
                        showBulkSheet = true
                    } label: {
                        Label(tr("Download Everything…", "Alles herunterladen…"),
                              systemImage: "square.and.arrow.down.on.square")
                    }
                    .disabled(offlineMode.isOffline)

                    HStack {
                        Text(tr("Max Storage", "Max. Speicher"))
                        Spacer()
                        Stepper("\(maxBulkStorageGB) GB",
                                value: $maxBulkStorageGB,
                                in: 10...maxAllowedStorageGB,
                                step: 10)
                            .labelsHidden()
                        Text("\(maxBulkStorageGB) GB")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .onAppear {
                        maxBulkStorageGB = min(maxBulkStorageGB, maxAllowedStorageGB)
                    }
                }

                DownloadStatsSection()

                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirm = true
                    } label: {
                        Label(tr("Delete All Downloads", "Alle Downloads löschen"), systemImage: "trash")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            tr("Delete all downloaded songs?", "Alle Downloads löschen?"),
            isPresented: $showDeleteAllConfirm,
            titleVisibility: .visible
        ) {
            Button(tr("Delete", "Löschen"), role: .destructive) {
                DownloadStore.shared.deleteAll()
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        }
        .sheet(isPresented: $showBulkSheet) {
            BulkDownloadSheet(maxBytes: Int64(maxBulkStorageGB) * 1_000_000_000)
                .environmentObject(appState)
                .frame(width: 520, height: 540)
        }
    }
}

struct BulkDownloadSheet: View {
    let maxBytes: Int64
    @EnvironmentObject var appState: AppState
    @ObservedObject var libraryStore = LibraryViewModel.shared
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var recapStore = RecapStore.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("recapEnabled") private var recapEnabled = false

    @State private var plan: BulkDownloadPlan?
    @State private var isPlanning = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(tr("Download Everything", "Alles herunterladen"))
                    .font(.title3).bold()
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            Form {
                if let plan {
                    Section {
                        LabeledContent(tr("Songs to download", "Songs"),
                                       value: "\(plan.planned.count)")
                        LabeledContent(tr("Estimated size", "Geschätzte Grösse"),
                                       value: ByteCountFormatter.string(fromByteCount: plan.totalBytes, countStyle: .file))
                        LabeledContent(tr("Storage limit", "Limit"),
                                       value: ByteCountFormatter.string(fromByteCount: plan.limitBytes, countStyle: .file))
                        if !plan.skipped.isEmpty {
                            LabeledContent(tr("Skipped (over limit)", "Übersprungen (über Limit)"),
                                           value: "\(plan.skipped.count)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if plan.isEmpty {
                        Section {
                            Text(tr(
                                "Nothing new fits in the configured storage limit.",
                                "Es passt nichts Neues in das konfigurierte Speicher-Limit."
                            ))
                            .foregroundStyle(.secondary)
                        }
                    } else {
                        Section(tr("Order", "Reihenfolge")) {
                            Label(tr("Frequently played first", "Häufig gespielt zuerst"),
                                  systemImage: "chart.line.uptrend.xyaxis")
                            Label(tr("Then recently played", "Dann kürzlich gespielt"),
                                  systemImage: "clock.arrow.circlepath")
                            if enableFavorites {
                                Label(tr("Then favorites", "Dann Favoriten"),
                                      systemImage: "heart")
                            }
                            if recapEnabled && !recapStore.recapPlaylistIds.isEmpty {
                                Label(tr("Then recap playlists", "Dann Recap-Playlists"),
                                      systemImage: "calendar.badge.clock")
                            }
                            Label(tr("Then alphabetical by artist", "Dann alphabetisch"),
                                  systemImage: "textformat")
                        }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }
                } else {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView(tr("Calculating…", "Berechne…"))
                            Spacer()
                        }
                        .padding(.vertical, 24)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button(tr("Cancel", "Abbrechen")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("Start", "Starten")) {
                    guard let plan else { return }
                    downloadStore.enqueueSongs(plan.planned)
                    let plannedIds = Set(plan.planned.map(\.id))
                    for (playlistId, songIds) in plan.recapPlaylistSongIds {
                        let allCovered = songIds.allSatisfy { downloadStore.isDownloaded(songId: $0) || plannedIds.contains($0) }
                        if allCovered {
                            downloadStore.markPlaylistDownloaded(id: playlistId, name: "", songIds: songIds)
                        }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(plan?.isEmpty ?? true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .task { await recompute() }
    }

    private func recompute() async {
        guard let stable = appState.serverStore.activeServer?.stableId, !stable.isEmpty else { return }
        isPlanning = true
        if libraryStore.albums.isEmpty {
            await libraryStore.loadAlbums()
        }
        let recapIds = recapEnabled ? Array(recapStore.recapPlaylistIds) : []
        let computed = await DownloadService.shared.planBulkDownload(
            serverId: stable, maxBytes: maxBytes,
            favorites: enableFavorites,
            recapPlaylistIds: recapIds,
            libraryAlbums: libraryStore.albums
        )
        plan = computed
        isPlanning = false
    }
}
