import SwiftUI

struct LyricsSettingsPanel: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var lyricsStore: LyricsStore
    @Environment(\.themeColor) private var themeColor
    @AppStorage("autoFetchLyrics") private var autoFetchLyrics = true

    @State private var showResetConfirm = false

    private var serverId: String {
        appState.serverStore.activeServerID?.uuidString ?? ""
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoFetchLyrics) {
                    Label(tr("Auto-fetch on playback", "Beim Abspielen laden"), systemImage: "wand.and.stars")
                }
                .tint(themeColor)
            }

            Section(tr("Database", "Datenbank")) {
                LabeledContent(tr("Stored", "Gespeichert")) {
                    if lyricsStore.isDownloading {
                        Text("\(lyricsStore.downloadFetched) / \(lyricsStore.downloadTotal)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("\(lyricsStore.fetchedCount) · \(lyricsStore.dbSize)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if lyricsStore.isDownloading {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(
                            value: Double(lyricsStore.downloadFetched),
                            total: Double(max(lyricsStore.downloadTotal, 1))
                        )
                        .tint(themeColor)
                        Button(tr("Cancel download", "Download abbrechen")) {
                            lyricsStore.cancelBulkDownload()
                        }
                        .foregroundStyle(.red)
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        guard !serverId.isEmpty else { return }
                        lyricsStore.startBulkDownload(serverId: serverId)
                    } label: {
                        Label(tr("Download all lyrics", "Alle Lyrics laden"), systemImage: "arrow.down.circle")
                    }
                    .disabled(serverId.isEmpty)
                }

                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label(tr("Reset lyrics database", "Lyrics zurücksetzen"), systemImage: "trash")
                }
                .confirmationDialog(
                    tr("Reset lyrics database?", "Lyrics-Datenbank zurücksetzen?"),
                    isPresented: $showResetConfirm
                ) {
                    Button(tr("Reset", "Zurücksetzen"), role: .destructive) {
                        Task {
                            await lyricsStore.reset(serverId: serverId)
                        }
                    }
                    Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
                } message: {
                    Text(tr(
                        "All stored lyrics for the active server will be deleted.",
                        "Alle gespeicherten Lyrics für den aktiven Server werden gelöscht."
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await lyricsStore.refreshFetchedCount(serverId: serverId)
            lyricsStore.refreshDbSize()
        }
    }
}
