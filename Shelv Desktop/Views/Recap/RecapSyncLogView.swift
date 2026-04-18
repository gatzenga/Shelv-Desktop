import SwiftUI

struct RecapSyncLogView: View {
    @StateObject private var ckStatus = CloudKitSyncService.shared.status
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if ckStatus.debugLogEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(tr("No log entries yet.", "Noch keine Log-Einträge."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(ckStatus.debugLogEntries) { entry in
                            Text(entry.text)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 640, height: 520)
        .navigationTitle(tr("Sync log", "Sync-Protokoll"))
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("Done", "Fertig")) { dismiss() }
            }
        }
    }
}
