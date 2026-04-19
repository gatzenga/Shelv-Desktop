import SwiftUI

struct RecapView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var libraryStore: LibraryViewModel
    @StateObject private var recapStore = RecapStore.shared
    @Environment(\.themeColor) private var themeColor
    @AppStorage("recapEnabled") private var recapEnabled = false
    @AppStorage("recapWeeklyEnabled") private var weeklyEnabled = true
    @AppStorage("recapMonthlyEnabled") private var monthlyEnabled = true
    @AppStorage("recapYearlyEnabled") private var yearlyEnabled = true

    @State private var segment: RecapPeriod.PeriodType = .week
    @State private var entryToDelete: RecapRegistryRecord?
    @State private var path = NavigationPath()

    private var enabledTypes: [RecapPeriod.PeriodType] {
        var types: [RecapPeriod.PeriodType] = []
        if weeklyEnabled  { types.append(.week) }
        if monthlyEnabled { types.append(.month) }
        if yearlyEnabled  { types.append(.year) }
        return types
    }

    private var filteredEntries: [RecapRegistryRecord] {
        recapStore.entries.filter { $0.periodType == segment.rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if !recapEnabled {
                    disabledStateView
                } else if enabledTypes.isEmpty {
                    emptyStateView(
                        icon: "chart.bar.xaxis",
                        message: tr("Enable at least one period in Settings.", "Aktiviere mindestens eine Periode in den Einstellungen.")
                    )
                } else {
                    if enabledTypes.count > 1 {
                        Picker("", selection: $segment) {
                            ForEach(enabledTypes, id: \.self) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                        Divider()
                    }

                    if filteredEntries.isEmpty {
                        emptyStateView(
                            icon: "clock",
                            message: tr("No recap generated yet for this period.", "Noch kein Recap für diese Periode erstellt.")
                        )
                    } else {
                        List {
                            ForEach(filteredEntries, id: \.playlistId) { entry in
                                Button {
                                    path.append(entry)
                                } label: {
                                    recapRow(entry)
                                }
                                .buttonStyle(.plain)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                                .contextMenu {
                                    Button(role: .destructive) {
                                        entryToDelete = entry
                                    } label: {
                                        Label(tr("Delete", "Löschen"), systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .frame(width: 520, height: 580)
            .navigationTitle(tr("Recap", "Recap"))
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task {
                            guard let sid = appState.serverStore.activeServer?.stableId else { return }
                            async let cleanup: Void = recapStore.refreshWithCleanup(serverId: sid)
                            async let sync:    Void = CloudKitSyncService.shared.syncNow()
                            _ = await (cleanup, sync)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(tr("Reload", "Neu laden"))
                }
            }
            .navigationDestination(for: RecapRegistryRecord.self) { entry in
                if let sid = appState.serverStore.activeServer?.stableId {
                    RecapDetailView(entry: entry, serverId: sid)
                        .environmentObject(appState)
                }
            }
        }
        .confirmationDialog(
            tr("Delete Recap?", "Recap löschen?"),
            isPresented: Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } }),
            presenting: entryToDelete
        ) { entry in
            Button(tr("Delete", "Löschen"), role: .destructive) {
                guard let sid = appState.serverStore.activeServer?.stableId else { return }
                Task { await recapStore.deleteEntry(playlistId: entry.playlistId, serverId: sid) }
            }
            Button(tr("Cancel", "Abbrechen"), role: .cancel) {}
        } message: { entry in
            let type = RecapPeriod.PeriodType(rawValue: entry.periodType) ?? .week
            let period = RecapPeriod(
                type: type,
                start: Date(timeIntervalSince1970: entry.periodStart),
                end: Date(timeIntervalSince1970: entry.periodEnd)
            )
            Text(period.playlistName)
        }
        .onAppear {
            if let first = enabledTypes.first, !enabledTypes.contains(segment) {
                segment = first
            }
        }
        .task(id: appState.serverStore.activeServerID) {
            guard let sid = appState.serverStore.activeServer?.stableId else { return }
            await recapStore.refreshWithCleanup(serverId: sid)
        }
    }

    private func recapRow(_ entry: RecapRegistryRecord) -> some View {
        let type = RecapPeriod.PeriodType(rawValue: entry.periodType) ?? .week
        let period = RecapPeriod(
            type: type,
            start: Date(timeIntervalSince1970: entry.periodStart),
            end: Date(timeIntervalSince1970: entry.periodEnd)
        )
        let isMissing = !libraryStore.playlists.isEmpty
            && !libraryStore.playlists.contains { $0.id == entry.playlistId }
        let iconColor: Color = isMissing ? .orange : themeColor
        let iconName = isMissing ? "exclamationmark.triangle.fill" : type.icon
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.12))
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(iconColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(period.playlistName)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tr("Top \(type.songLimit)", "Top \(type.songLimit)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
    }

    private var disabledStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(tr("Recap is disabled", "Recap ist deaktiviert"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(tr("Enable Recap in Settings to start tracking your listening history.", "Aktiviere Recap in den Einstellungen, um dein Hörverhalten aufzuzeichnen."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateView(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension RecapPeriod.PeriodType {
    var label: String {
        switch self {
        case .week:  return tr("Weekly", "Wöchentlich")
        case .month: return tr("Monthly", "Monatlich")
        case .year:  return tr("Yearly", "Jährlich")
        }
    }

    var icon: String {
        switch self {
        case .week:  return "calendar"
        case .month: return "calendar.badge.clock"
        case .year:  return "calendar.badge.checkmark"
        }
    }
}
