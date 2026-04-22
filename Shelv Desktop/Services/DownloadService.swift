import Foundation
import Combine

extension Notification.Name {
    static let downloadStateChanged = Notification.Name("shelv.downloadStateChanged")
    static let downloadsLibraryChanged = Notification.Name("shelv.downloadsLibraryChanged")
    static let libraryArtistsLoaded = Notification.Name("shelv.libraryArtistsLoaded")
}

private struct DownloadJob {
    let song: Song
    let serverId: String
    var downloadURL: URL
    let coverURL: URL?
    let coverArtId: String?
    let albumId: String
    let albumTitle: String
    let artistName: String
    let artistId: String?
    let title: String
    let track: Int?
    let disc: Int?
    let duration: Int?
    var fileExtension: String
    let isFavorite: Bool
    var requestedFormat: TranscodingCodec? = nil
    var fellBackToRaw: Bool = false
    var attempt: Int = 0
    let queuedAt: Date = Date()
}

actor DownloadService {
    static let shared = DownloadService()

    private let coordinator = DownloadSessionCoordinator()
    private var session: URLSession?
    private let coverSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    private let backgroundIdentifier = "ch.vkugler.ShelvDesktop.downloads"
    private let maxConcurrent = 3
    private let maxAttempts = 3

    private var pendingJobs: [DownloadJob] = []
    private var inflightJobs: [Int: DownloadJob] = [:]
    private var jobKeyByTask: [Int: String] = [:]

    nonisolated private let progressSubject = CurrentValueSubject<[String: Double], Never>([:])
    nonisolated private let stateSubject = PassthroughSubject<(key: String, state: DownloadState), Never>()
    nonisolated private let batchSubject = CurrentValueSubject<BatchProgress?, Never>(nil)

    nonisolated var progressUpdates: AnyPublisher<[String: Double], Never> {
        progressSubject.eraseToAnyPublisher()
    }
    nonisolated var stateUpdates: AnyPublisher<(key: String, state: DownloadState), Never> {
        stateSubject.eraseToAnyPublisher()
    }
    nonisolated var batchUpdates: AnyPublisher<BatchProgress?, Never> {
        batchSubject.eraseToAnyPublisher()
    }

    private var batchTotal = 0
    private var batchCompleted = 0
    private var batchFailed = 0

    private init() {
        coordinator.service = self
    }

    static func key(songId: String, serverId: String) -> String {
        "\(serverId)::\(songId)"
    }

    // MARK: - Setup

    func setup() {
        if session == nil {
            let cfg = URLSessionConfiguration.background(withIdentifier: backgroundIdentifier)
            cfg.isDiscretionary = false
            cfg.sessionSendsLaunchEvents = true
            cfg.allowsCellularAccess = true
            cfg.httpMaximumConnectionsPerHost = maxConcurrent
            session = URLSession(configuration: cfg, delegate: coordinator, delegateQueue: nil)
        }
    }

    // MARK: - Enqueueing

    func enqueue(songs: [Song], serverId: String) async {
        guard !songs.isEmpty else { return }
        let api = SubsonicAPIService.shared
        guard let cfg = api.currentConfig else { return }
        let downloadedIds = await DownloadDatabase.shared.allSongIds(serverId: serverId)
        var added = 0
        for song in songs {
            let key = Self.key(songId: song.id, serverId: serverId)
            if downloadedIds.contains(song.id) { continue }
            if inflightJobs.values.contains(where: { Self.key(songId: $0.song.id, serverId: $0.serverId) == key }) { continue }
            if pendingJobs.contains(where: { Self.key(songId: $0.song.id, serverId: $0.serverId) == key }) { continue }
            let transcoding = TranscodingPolicy.currentDownloadFormat()
            guard let url = api.downloadURL(forConfig: cfg, songId: song.id, transcoding: transcoding) else { continue }
            let cover = song.coverArt.flatMap { api.coverArtURL(forConfig: cfg, id: $0, size: 600) }
            let initialExt: String = {
                if let t = transcoding { return t.codec.fileExtension }
                return (song.suffix?.isEmpty == false) ? song.suffix! : "mp3"
            }()
            let job = DownloadJob(
                song: song,
                serverId: serverId,
                downloadURL: url,
                coverURL: cover,
                coverArtId: song.coverArt,
                albumId: song.albumId ?? "",
                albumTitle: song.album ?? "",
                artistName: song.artist ?? "",
                artistId: song.artistId,
                title: song.title,
                track: song.track,
                disc: song.discNumber,
                duration: song.duration,
                fileExtension: initialExt,
                isFavorite: false,
                requestedFormat: transcoding?.codec
            )
            pendingJobs.append(job)
            stateSubject.send((key, .queued))
            added += 1
        }
        if added > 0 { incrementBatchTotal(by: added) }
        startNextJobs()
    }

    func enqueueAlbum(album: Album, serverId: String) async {
        let api = SubsonicAPIService.shared
        do {
            let detail = try await api.getAlbum(id: album.id)
            let songs = detail.song.map { song -> Song in
                if song.artist != nil && song.albumId != nil { return song }
                return Song(
                    id: song.id,
                    title: song.title,
                    artist: song.artist ?? detail.artist,
                    artistId: song.artistId ?? detail.artistId,
                    album: song.album ?? detail.name,
                    albumId: song.albumId ?? detail.id,
                    coverArt: song.coverArt ?? detail.coverArt,
                    duration: song.duration,
                    track: song.track,
                    discNumber: song.discNumber,
                    year: song.year,
                    genre: song.genre,
                    starred: song.starred,
                    playCount: song.playCount,
                    bitRate: song.bitRate,
                    contentType: song.contentType,
                    suffix: song.suffix
                )
            }
            await enqueue(songs: songs, serverId: serverId)
        } catch {
            DBErrorLog.logPlayLog("DownloadService.enqueueAlbum: \(error.localizedDescription)")
        }
    }

    func enqueueArtist(artist: Artist, serverId: String) async {
        let api = SubsonicAPIService.shared
        do {
            let detail = try await api.getArtist(id: artist.id)
            for album in detail.album {
                await enqueueAlbum(album: album, serverId: serverId)
            }
        } catch {
            DBErrorLog.logPlayLog("DownloadService.enqueueArtist: \(error.localizedDescription)")
        }
    }

    // MARK: - Cancel / Delete

    func cancel(songId: String, serverId: String) {
        let key = Self.key(songId: songId, serverId: serverId)
        pendingJobs.removeAll { Self.key(songId: $0.song.id, serverId: $0.serverId) == key }
        for (taskId, job) in inflightJobs where Self.key(songId: job.song.id, serverId: job.serverId) == key {
            session?.getAllTasks { tasks in
                tasks.first(where: { $0.taskIdentifier == taskId })?.cancel()
            }
            inflightJobs.removeValue(forKey: taskId)
            jobKeyByTask.removeValue(forKey: taskId)
        }
        publishProgress(key: key, value: nil)
        stateSubject.send((key, .none))
    }

    func delete(songId: String, serverId: String) async {
        cancel(songId: songId, serverId: serverId)
        if let path = await DownloadDatabase.shared.filePath(songId: songId, serverId: serverId) {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: Self.coverPath(forFilePath: path))
        }
        await DownloadDatabase.shared.delete(songId: songId, serverId: serverId)
        let key = Self.key(songId: songId, serverId: serverId)
        stateSubject.send((key, .none))
        notifyLibraryChanged()
    }

    func deleteAlbum(albumId: String, serverId: String) async {
        let records = await DownloadDatabase.shared.allRecords(serverId: serverId)
            .filter { $0.albumId == albumId }
        for r in records {
            await delete(songId: r.songId, serverId: serverId)
        }
    }

    func deleteArtist(artistId: String, serverId: String) async {
        let all = await DownloadDatabase.shared.allRecords(serverId: serverId)
        let records: [DownloadRecord]
        if artistId.hasPrefix("name:") {
            let name = String(artistId.dropFirst("name:".count))
            records = all.filter { $0.artistName == name }
        } else {
            records = all.filter { $0.artistId == artistId || $0.artistName == artistId }
        }
        for r in records {
            await delete(songId: r.songId, serverId: serverId)
        }
    }

    func cancelBatch() {
        pendingJobs.removeAll()
        let inflightKeys = inflightJobs.values.map { Self.key(songId: $0.song.id, serverId: $0.serverId) }
        for taskId in Array(inflightJobs.keys) {
            inflightJobs.removeValue(forKey: taskId)
            jobKeyByTask.removeValue(forKey: taskId)
        }
        session?.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        for key in inflightKeys {
            publishProgress(key: key, value: nil)
            stateSubject.send((key, .none))
        }
        batchTotal = 0; batchCompleted = 0; batchFailed = 0
        batchSubject.send(nil)
    }

    func deleteAllForServer(_ serverId: String) async {
        let records = await DownloadDatabase.shared.allRecords(serverId: serverId)
        for r in records {
            cancel(songId: r.songId, serverId: serverId)
            try? FileManager.default.removeItem(atPath: r.filePath)
            try? FileManager.default.removeItem(atPath: Self.coverPath(forFilePath: r.filePath))
        }
        await DownloadDatabase.shared.deleteAllForServer(serverId)
        let dir = Self.serverDirectory(serverId: serverId)
        try? FileManager.default.removeItem(at: dir)
        notifyLibraryChanged()
    }

    func deleteAll() async {
        pendingJobs.removeAll()
        for taskId in Array(inflightJobs.keys) {
            inflightJobs.removeValue(forKey: taskId)
            jobKeyByTask.removeValue(forKey: taskId)
        }
        session?.getAllTasks { tasks in tasks.forEach { $0.cancel() } }

        await DownloadDatabase.shared.deleteAll()

        let root = Self.rootDirectory()
        let dbPath = DownloadDatabase.dbURL.path
        let protectedPaths: Set<String> = [dbPath, dbPath + "-wal", dbPath + "-shm"]
        if let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in entries {
                if protectedPaths.contains(url.path) { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }

        progressSubject.send([:])
        batchTotal = 0; batchCompleted = 0; batchFailed = 0
        batchSubject.send(nil)
        notifyLibraryChanged()
    }

    // MARK: - Bulk Plan

    func planBulkDownload(serverId: String, maxBytes: Int64,
                          favorites enabled: Bool,
                          libraryAlbums: [Album]) async -> BulkDownloadPlan {
        let api = SubsonicAPIService.shared
        let alreadyDownloaded = await DownloadDatabase.shared.allSongIds(serverId: serverId)

        let allSongs: [Song] = await withTaskGroup(of: [Song].self) { group in
            let limit = 10
            var index = 0
            var result: [Song] = []
            for album in libraryAlbums.prefix(limit) {
                group.addTask { (try? await api.getAlbum(id: album.id))?.song ?? [] }
                index += 1
            }
            for await songs in group {
                result.append(contentsOf: songs)
                if index < libraryAlbums.count {
                    let next = libraryAlbums[index]
                    group.addTask { (try? await api.getAlbum(id: next.id))?.song ?? [] }
                    index += 1
                }
            }
            return result
        }

        let mostPlayed = allSongs
            .filter { ($0.playCount ?? 0) > 0 }
            .sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
            .map(\.id)
        let starred = enabled
            ? allSongs.filter { $0.isStarred }.map(\.id)
            : []
        let alphabetical = allSongs.sorted {
            let a = ($0.artist ?? "").lowercased()
            let b = ($1.artist ?? "").lowercased()
            if a != b { return a < b }
            let aa = ($0.album ?? "").lowercased()
            let bb = ($1.album ?? "").lowercased()
            if aa != bb { return aa < bb }
            return ($0.track ?? 0) < ($1.track ?? 0)
        }.map(\.id)

        var ordered: [String] = []
        var seen = Set<String>()
        func appendUnique(_ ids: [String]) {
            for id in ids where !seen.contains(id) {
                ordered.append(id); seen.insert(id)
            }
        }
        appendUnique(mostPlayed)
        appendUnique(starred)
        appendUnique(alphabetical)

        let songsById = Dictionary(uniqueKeysWithValues: allSongs.map { ($0.id, $0) })
        var planned: [Song] = []
        var skipped: [Song] = []
        var totalBytes: Int64 = 0
        for songId in ordered {
            guard let song = songsById[songId] else { continue }
            if alreadyDownloaded.contains(song.id) { continue }
            let estBytes = estimatedBytes(for: song)
            if totalBytes + estBytes > maxBytes {
                skipped.append(song)
                continue
            }
            planned.append(song)
            totalBytes += estBytes
        }
        return BulkDownloadPlan(planned: planned, skipped: skipped, totalBytes: totalBytes, limitBytes: maxBytes)
    }

    private func estimatedBytes(for song: Song) -> Int64 {
        let kbps = song.bitRate ?? 192
        let duration = song.duration ?? 200
        return Int64(kbps) * Int64(duration) * 1024 / 8
    }

    // MARK: - Status

    func currentState(songId: String, serverId: String) -> DownloadState {
        let key = Self.key(songId: songId, serverId: serverId)
        if let p = progressSubject.value[key] { return .downloading(progress: p) }
        if pendingJobs.contains(where: { Self.key(songId: $0.song.id, serverId: $0.serverId) == key }) {
            return .queued
        }
        return .none
    }

    // MARK: - Job Lifecycle

    private func startNextJobs() {
        guard let session else { return }
        while inflightJobs.count < maxConcurrent, !pendingJobs.isEmpty {
            let job = pendingJobs.removeFirst()
            let task = session.downloadTask(with: job.downloadURL)
            inflightJobs[task.taskIdentifier] = job
            jobKeyByTask[task.taskIdentifier] = Self.key(songId: job.song.id, serverId: job.serverId)
            publishProgress(key: Self.key(songId: job.song.id, serverId: job.serverId), value: 0)
            stateSubject.send((Self.key(songId: job.song.id, serverId: job.serverId), .downloading(progress: 0)))
            task.resume()
        }
    }

    func handleProgress(taskIdentifier: Int, written: Int64, total: Int64) {
        guard let key = jobKeyByTask[taskIdentifier] else { return }
        let p = total > 0 ? Double(written) / Double(total) : 0
        publishProgress(key: key, value: p)
        stateSubject.send((key, .downloading(progress: p)))
    }

    func handleCompletion(taskIdentifier: Int, tempURL: URL, byteSize: Int64, mimeType: String?) async {
        guard let job = inflightJobs[taskIdentifier] else {
            try? FileManager.default.removeItem(at: tempURL)
            return
        }
        inflightJobs.removeValue(forKey: taskIdentifier)
        jobKeyByTask.removeValue(forKey: taskIdentifier)

        let key = Self.key(songId: job.song.id, serverId: job.serverId)
        let serverDir = Self.serverDirectory(serverId: job.serverId)
        let actualExt = TranscodingPolicy.extensionFor(mimeType: mimeType) ?? job.fileExtension
        let finalURL = serverDir.appendingPathComponent("\(job.song.id).\(actualExt)")
        do {
            try FileManager.default.createDirectory(at: serverDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
        } catch {
            DBErrorLog.logPlayLog("DownloadService move failed: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            await retryOrFail(job: job, error: error)
            return
        }

        await downloadCoverIfNeeded(for: job, audioPath: finalURL.path)

        let bytes = byteSize > 0 ? byteSize :
            (Int64((try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? NSNumber)?.int64Value ?? 0))

        let record = DownloadRecord(
            songId: job.song.id,
            serverId: job.serverId,
            albumId: job.albumId,
            artistId: job.artistId,
            title: job.title,
            albumTitle: job.albumTitle,
            artistName: job.artistName,
            track: job.track,
            disc: job.disc,
            duration: job.duration,
            bytes: bytes,
            coverArtId: job.coverArtId,
            isFavorite: job.isFavorite,
            filePath: finalURL.path,
            fileExtension: actualExt,
            addedAt: Date().timeIntervalSince1970
        )
        await DownloadDatabase.shared.upsert(record)
        publishProgress(key: key, value: nil)
        stateSubject.send((key, .completed))
        notifyLibraryChanged()
        incrementBatchCompleted()
        startNextJobs()
    }

    func handleError(taskIdentifier: Int, error: Error?) async {
        guard let job = inflightJobs.removeValue(forKey: taskIdentifier) else {
            jobKeyByTask.removeValue(forKey: taskIdentifier)
            return
        }
        jobKeyByTask.removeValue(forKey: taskIdentifier)
        await retryOrFail(job: job, error: error ?? NSError(domain: "DownloadService", code: 0))
    }

    private func retryOrFail(job: DownloadJob, error: Error) async {
        let key = Self.key(songId: job.song.id, serverId: job.serverId)
        var next = job
        next.attempt += 1
        if next.attempt < maxAttempts {
            let backoff = pow(2.0, Double(next.attempt))
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            pendingJobs.append(next)
            stateSubject.send((key, .queued))
            startNextJobs()
            return
        }
        // Letzter Versuch ohne Transcoding (Original)
        if job.requestedFormat != nil, !job.fellBackToRaw,
           let cfg = SubsonicAPIService.shared.currentConfig,
           let rawURL = SubsonicAPIService.shared.downloadURL(forConfig: cfg, songId: job.song.id, transcoding: nil) {
            var raw = job
            raw.attempt = 0
            raw.fellBackToRaw = true
            raw.downloadURL = rawURL
            raw.fileExtension = (job.song.suffix?.isEmpty == false) ? job.song.suffix! : "mp3"
            pendingJobs.append(raw)
            stateSubject.send((key, .queued))
            startNextJobs()
            return
        }
        publishProgress(key: key, value: nil)
        stateSubject.send((key, .failed(message: error.localizedDescription)))
        incrementBatchFailed()
    }

    private func incrementBatchTotal(by n: Int) {
        batchTotal += n
        publishBatch()
    }

    private func incrementBatchCompleted() {
        batchCompleted += 1
        publishBatch()
        resetBatchIfDone()
    }

    private func incrementBatchFailed() {
        batchFailed += 1
        publishBatch()
        resetBatchIfDone()
    }

    private func resetBatchIfDone() {
        guard pendingJobs.isEmpty, inflightJobs.isEmpty else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self?.flushBatchIfStillIdle()
        }
    }

    private func flushBatchIfStillIdle() {
        guard pendingJobs.isEmpty, inflightJobs.isEmpty else { return }
        batchTotal = 0; batchCompleted = 0; batchFailed = 0
        batchSubject.send(nil)
    }

    private func publishBatch() {
        if batchTotal > 0 {
            batchSubject.send(BatchProgress(total: batchTotal, completed: batchCompleted, failed: batchFailed))
        } else {
            batchSubject.send(nil)
        }
    }

    private func downloadCoverIfNeeded(for job: DownloadJob, audioPath: String) async {
        let coverPath = Self.coverPath(forFilePath: audioPath)
        if FileManager.default.fileExists(atPath: coverPath) { return }
        guard let coverURL = job.coverURL else { return }
        do {
            let (data, _) = try await coverSession.data(from: coverURL)
            try data.write(to: URL(fileURLWithPath: coverPath), options: .atomic)
        } catch {
            // best effort
        }
    }

    private func publishProgress(key: String, value: Double?) {
        var current = progressSubject.value
        if let value { current[key] = value } else { current.removeValue(forKey: key) }
        progressSubject.send(current)
    }

    private func notifyLibraryChanged() {
        NotificationCenter.default.post(name: .downloadsLibraryChanged, object: nil)
    }

    // MARK: - Paths

    static func rootDirectory() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shelv_downloads", isDirectory: true)
    }

    static func serverDirectory(serverId: String) -> URL {
        let safe = serverId.isEmpty ? "_default" : serverId
        return rootDirectory().appendingPathComponent(safe, isDirectory: true)
    }

    static func coverPath(forFilePath audioPath: String) -> String {
        let url = URL(fileURLWithPath: audioPath)
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent("\(stem)_cover.jpg").path
    }
}

private final class DownloadSessionCoordinator: NSObject, URLSessionDownloadDelegate {
    weak var service: DownloadService?

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let id = downloadTask.taskIdentifier
        Task { [weak service] in
            await service?.handleProgress(taskIdentifier: id,
                                          written: totalBytesWritten,
                                          total: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let id = downloadTask.taskIdentifier
        let safeURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("shelv-dl-\(id)-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: location, to: safeURL)
        } catch {
            return
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: safeURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        let mime = (downloadTask.response as? HTTPURLResponse)?.mimeType
        Task { [weak service] in
            await service?.handleCompletion(taskIdentifier: id, tempURL: safeURL, byteSize: bytes, mimeType: mime)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard error != nil else { return }
        let id = task.taskIdentifier
        Task { [weak service] in
            await service?.handleError(taskIdentifier: id, error: error)
        }
    }
}
