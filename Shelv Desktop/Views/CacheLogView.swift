import SwiftUI

struct CacheLogView: View {
    @ObservedObject private var cacheLog = StreamCacheLog.shared

    var body: some View {
        VStack(spacing: 0) {
            if cacheLog.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(tr("No cache events yet.", "Noch keine Cache-Ereignisse."))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(cacheLog.entries.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .navigationTitle(tr("Cache Log", "Cache-Log"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(tr("Clear", "Leeren")) { StreamCacheLog.shared.clear() }
                    .disabled(cacheLog.entries.isEmpty)
            }
        }
    }
}
