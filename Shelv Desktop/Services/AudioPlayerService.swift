import AVFoundation
import AppKit
import MediaPlayer
import Combine
import SwiftUI

@MainActor
class AudioPlayerService: ObservableObject {
    static let shared = AudioPlayerService()

    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentSong: Song?
    @Published var queue: [QueueItem] = []
    @Published var playNextQueue: [Song] = []
    @Published var userQueue: [Song] = []
    @Published var currentIndex: Int = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0 {
        didSet { engine.volume = volume }
    }
    @Published var isSeeking: Bool = false

    let timePublisher = PassthroughSubject<(time: Double, duration: Double), Never>()

    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var actualStreamFormat: ActualStreamFormat?

    private var formatProbeTask: Task<Void, Never>?
    private var playbackWatchdog: Task<Void, Never>?

    func probeStreamFormat(songId: String, url: URL, duration: Double) {
        formatProbeTask?.cancel()
        if url.isFileURL {
            let path = url.path
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            let bitrate: Int? = (size > 0 && duration > 1) ? Int(Double(size) * 8 / duration / 1000) : nil
            let codec = url.pathExtension.uppercased()
            actualStreamFormat = ActualStreamFormat(codecLabel: codec.isEmpty ? "?" : codec, bitrateKbps: bitrate)
            return
        }
        actualStreamFormat = nil
        let formatParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "format" })?.value
        let isTranscoded = (formatParam != nil && formatParam != "raw")
        formatProbeTask = Task { [weak self] in
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 8
            do {
                let (_, response) = try await URLSession.shared.data(for: req)
                guard !Task.isCancelled, let http = response as? HTTPURLResponse else { return }
                if http.statusCode != 200, isTranscoded {
                    print("[Transcoding] HEAD status \(http.statusCode) → fallback to raw")
                    await MainActor.run { self?.fallbackToRawStream(songId: songId, duration: duration) }
                    return
                }
                let codec = ActualStreamFormat.codecLabel(forMime: http.mimeType)
                let length = http.expectedContentLength
                var bitrate: Int? = nil
                if length > 0, duration > 1 {
                    bitrate = Int(Double(length) * 8 / duration / 1000)
                }
                await MainActor.run {
                    self?.actualStreamFormat = ActualStreamFormat(codecLabel: codec, bitrateKbps: bitrate)
                }
            } catch {
                guard !Task.isCancelled else { return }
                if isTranscoded {
                    print("[Transcoding] HEAD failed (\(error.localizedDescription)) → fallback to raw")
                    await MainActor.run { self?.fallbackToRawStream(songId: songId, duration: duration) }
                }
            }
        }
    }

    private func fallbackToRawStream(songId: String, duration: Double) {
        guard let song = currentSong, song.id == songId else { return }
        guard let raw = SubsonicAPIService.shared.rawStreamURL(songId: songId) else { return }
        playbackWatchdog?.cancel()
        let resumeAt = currentTime
        crossfadeTriggered = false
        isBuffering = true
        engine.play(url: raw)
        if resumeAt > 1 { engine.seek(to: resumeAt) }
        isEngineLoaded = true
        probeStreamFormat(songId: songId, url: raw, duration: duration)
    }

    private func schedulePlaybackWatchdog(songId: String, url: URL, duration: Double) {
        playbackWatchdog?.cancel()
        let formatParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "format" })?.value
        guard formatParam != nil, formatParam != "raw" else { return }
        playbackWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentSong?.id == songId else { return }
                let stuck = !self.isPlaying || self.currentTime < 0.1
                guard stuck else { return }
                print("[Transcoding] Playback watchdog timeout (isPlaying=\(self.isPlaying) currentTime=\(self.currentTime)) → fallback to raw")
                self.fallbackToRawStream(songId: songId, duration: duration)
            }
        }
    }

    private var truthAlbumQueue: [Song] = []
    private var truthPlayNextQueue: [Song] = []
    private var truthUserQueue: [Song] = []
    private var isPlayingFromPlayNext = false

    private let engine = CrossfadeEngine()
    private var engineSubscriptions = Set<AnyCancellable>()
    private var crossfadeTriggered = false
    private var isEngineLoaded = false

    private var apiService: SubsonicAPIService { SubsonicAPIService.shared }

    private func resolveURL(songId: String) -> URL? {
        let serverId = AppState.shared.serverStore.activeServer?.stableId ?? ""
        if !serverId.isEmpty,
           let local = LocalDownloadIndex.shared.url(songId: songId, serverId: serverId) {
            return local
        }
        guard !OfflineModeService.shared.isOffline else { return nil }
        return apiService.streamURL(songId: songId)
    }

    private var currentArtwork: MPMediaItemArtwork?
    private var artworkLoadTask: Task<Void, Never>?
    private var hasScrobbledCurrent: Bool = false
    private var resumeTime: Double = 0

    private enum StateKey {
        static let queue                = "shelv_mac_queue"
        static let currentIndex         = "shelv_mac_currentIndex"
        static let playNextQueue        = "shelv_mac_playNextQueue"
        static let userQueue            = "shelv_mac_userQueue"
        static let currentTime          = "shelv_mac_currentTime"
        static let isShuffled           = "shelv_mac_isShuffled"
        static let repeatMode           = "shelv_mac_repeatMode"
        static let volume               = "shelv_mac_volume"
        static let truthAlbum           = "shelv_mac_truthAlbum"
        static let truthPlayNext        = "shelv_mac_truthPlayNext"
        static let truthUserQueue       = "shelv_mac_truthUserQueue"
        static let isPlayingFromPlayNext = "shelv_mac_isPlayingFromPlayNext"
    }

    private var willTerminateObserver: NSObjectProtocol?

    private init() {
        setupRemoteControls()
        setupEngine()
        restoreState()
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.saveState() }
        }
    }

    deinit {
        if let obs = willTerminateObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func saveState() {
        let encoder = JSONEncoder()
        let defaults = UserDefaults.standard
        let songs = queue.map { $0.song }
        if let data = try? encoder.encode(songs) { defaults.set(data, forKey: StateKey.queue) }
        defaults.set(currentIndex, forKey: StateKey.currentIndex)
        if let data = try? encoder.encode(playNextQueue) { defaults.set(data, forKey: StateKey.playNextQueue) }
        if let data = try? encoder.encode(userQueue) { defaults.set(data, forKey: StateKey.userQueue) }
        defaults.set(currentTime, forKey: StateKey.currentTime)
        defaults.set(isShuffled, forKey: StateKey.isShuffled)
        defaults.set(repeatMode == .one ? "one" : repeatMode == .all ? "all" : "off", forKey: StateKey.repeatMode)
        defaults.set(Double(volume), forKey: StateKey.volume)
        defaults.set(isPlayingFromPlayNext, forKey: StateKey.isPlayingFromPlayNext)
        if let data = try? encoder.encode(truthAlbumQueue) { defaults.set(data, forKey: StateKey.truthAlbum) }
        if let data = try? encoder.encode(truthPlayNextQueue) { defaults.set(data, forKey: StateKey.truthPlayNext) }
        if let data = try? encoder.encode(truthUserQueue) { defaults.set(data, forKey: StateKey.truthUserQueue) }
    }

    private func clearSavedState() {
        let d = UserDefaults.standard
        [StateKey.queue, StateKey.currentIndex, StateKey.playNextQueue,
         StateKey.userQueue, StateKey.currentTime].forEach { d.removeObject(forKey: $0) }
    }

    private func restoreState() {
        let decoder = JSONDecoder()
        let defaults = UserDefaults.standard
        guard let queueData = defaults.data(forKey: StateKey.queue),
              let songs = try? decoder.decode([Song].self, from: queueData),
              !songs.isEmpty
        else { return }

        queue = songs.map { QueueItem(song: $0) }
        let idx = defaults.integer(forKey: StateKey.currentIndex)
        currentIndex = min(max(idx, 0), songs.count - 1)
        currentSong = songs[currentIndex]
        resumeTime = defaults.double(forKey: StateKey.currentTime)
        currentTime = resumeTime
        if let d = currentSong?.duration { duration = Double(d) }

        if let data = defaults.data(forKey: StateKey.playNextQueue),
           let pn = try? decoder.decode([Song].self, from: data) { playNextQueue = pn }
        if let data = defaults.data(forKey: StateKey.userQueue),
           let uq = try? decoder.decode([Song].self, from: data) { userQueue = uq }

        if let song = currentSong { updateNowPlayingInfo(song: song) }

        isShuffled = defaults.bool(forKey: StateKey.isShuffled)
        let repeatStr = defaults.string(forKey: StateKey.repeatMode) ?? "off"
        repeatMode = repeatStr == "one" ? .one : repeatStr == "all" ? .all : .off

        let savedVolume = defaults.double(forKey: StateKey.volume)
        volume = savedVolume > 0 ? Float(savedVolume) : 1.0

        isPlayingFromPlayNext = defaults.bool(forKey: StateKey.isPlayingFromPlayNext)

        if let data = defaults.data(forKey: StateKey.truthAlbum),
           let t = try? decoder.decode([Song].self, from: data) { truthAlbumQueue = t }
        if let data = defaults.data(forKey: StateKey.truthPlayNext),
           let t = try? decoder.decode([Song].self, from: data) { truthPlayNextQueue = t }
        if let data = defaults.data(forKey: StateKey.truthUserQueue),
           let t = try? decoder.decode([Song].self, from: data) { truthUserQueue = t }
    }

    func play(songs: [Song], startIndex: Int = 0) {
        isShuffled = false
        isPlayingFromPlayNext = false
        playNextQueue = []
        userQueue = []
        queue = songs.map { QueueItem(song: $0) }
        currentIndex = startIndex
        truthAlbumQueue = songs
        truthPlayNextQueue = []
        truthUserQueue = []
        playCurrent()
    }

    func playShuffled(songs: [Song]) {
        guard !songs.isEmpty else { return }
        let shuffled = songs.shuffled()
        let shuffledItems = shuffled.map { QueueItem(song: $0) }

        isShuffled = false
        isPlayingFromPlayNext = false
        playNextQueue = []
        userQueue = []
        queue = shuffledItems
        currentIndex = 0
        isShuffled = true
        truthAlbumQueue = songs
        truthPlayNextQueue = []
        truthUserQueue = []

        playCurrent()
    }

    func playSong(_ song: Song) {
        play(songs: [song], startIndex: 0)
    }

    func playNext(triggeredByUser: Bool = true) {
        if !playNextQueue.isEmpty {
            let song = playNextQueue.removeFirst()
            if let i = truthPlayNextQueue.firstIndex(where: { $0.id == song.id }) {
                truthPlayNextQueue.remove(at: i)
            }
            isPlayingFromPlayNext = true
            currentSong = song
            hasScrobbledCurrent = false
            saveState()
            guard let url = resolveURL(songId: song.id) else { return }
            loadURL(url, song: song)
            return
        }
        isPlayingFromPlayNext = false

        guard !queue.isEmpty else {
            if !userQueue.isEmpty {
                let song = userQueue.removeFirst()
                let item = QueueItem(song: song)
                queue.append(item)
                currentIndex = 0
                playCurrent()
            } else {
                stop()
            }
            return
        }

        if repeatMode == .one && !triggeredByUser {
            playCurrent()
            return
        }

        if currentIndex < queue.count - 1 {
            currentIndex += 1
            playCurrent()
        } else if !userQueue.isEmpty {
            let song = userQueue.removeFirst()
            let item = QueueItem(song: song)
            queue.append(item)
            currentIndex = queue.count - 1
            playCurrent()
        } else if repeatMode == .all {
            let fullTruth = truthAlbumQueue + truthUserQueue
            truthAlbumQueue = fullTruth
            truthUserQueue = []
            truthPlayNextQueue = []
            let items = fullTruth.map { QueueItem(song: $0) }
            queue = isShuffled ? items.shuffled() : items
            playNextQueue = []
            userQueue = []
            currentIndex = 0
            if queue.isEmpty { stop() } else { playCurrent() }
        } else if repeatMode == .one {
            playCurrent()
        } else {
            stop()
        }
    }

    func playPrevious() {
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        if isPlayingFromPlayNext {
            isPlayingFromPlayNext = false
            playCurrent()
            return
        }
        guard currentIndex > 0 else {
            seek(to: 0)
            return
        }
        currentIndex -= 1
        playCurrent()
    }

    func playQueue(at index: Int) {
        guard index >= 0 && index < queue.count else { return }
        isPlayingFromPlayNext = false
        currentIndex = index
        playCurrent()
    }

    func jumpToAlbumTrack(at index: Int) {
        guard queue.indices.contains(index), index > currentIndex else { return }
        let item = queue.remove(at: index)
        isPlayingFromPlayNext = true
        currentSong = item.song
        hasScrobbledCurrent = false
        guard let url = resolveURL(songId: item.song.id) else { return }
        loadURL(url, song: item.song)
        saveState()
    }

    func jumpToUserQueueTrack(at index: Int) {
        guard userQueue.indices.contains(index) else { return }
        let song = userQueue.remove(at: index)
        isPlayingFromPlayNext = true
        currentSong = song
        hasScrobbledCurrent = false
        guard let url = resolveURL(songId: song.id) else { return }
        loadURL(url, song: song)
        saveState()
    }

    func addPlayNext(_ song: Song) {
        truthPlayNextQueue.append(song)
        if isShuffled {
            insertRandomlyInShuffledQueue(song)
        } else {
            playNextQueue.append(song)
        }
        saveState()
    }

    func addPlayNext(_ songs: [Song]) {
        truthPlayNextQueue.append(contentsOf: songs)
        if isShuffled {
            songs.forEach { insertRandomlyInShuffledQueue($0) }
        } else {
            playNextQueue.append(contentsOf: songs)
        }
        saveState()
    }

    private func insertRandomlyInShuffledQueue(_ song: Song) {
        let lo = currentIndex + 1
        let hi = queue.count
        let pos = lo <= hi ? Int.random(in: lo...hi) : hi
        queue.insert(QueueItem(song: song), at: pos)
    }

    func removeFromPlayNextQueue(at index: Int) {
        guard playNextQueue.indices.contains(index) else { return }
        let songId = playNextQueue[index].id
        playNextQueue.remove(at: index)
        if let i = truthPlayNextQueue.firstIndex(where: { $0.id == songId }) {
            truthPlayNextQueue.remove(at: i)
        }
        saveState()
    }

    func moveInPlayNextQueue(from: IndexSet, to: Int) {
        playNextQueue.move(fromOffsets: from, toOffset: to)
        truthPlayNextQueue = playNextQueue
        saveState()
    }

    func jumpToPlayNextTrack(at index: Int) {
        guard playNextQueue.indices.contains(index) else { return }
        let song = playNextQueue.remove(at: index)
        if let i = truthPlayNextQueue.firstIndex(where: { $0.id == song.id }) {
            truthPlayNextQueue.remove(at: i)
        }
        isPlayingFromPlayNext = true
        currentSong = song
        hasScrobbledCurrent = false
        guard let url = resolveURL(songId: song.id) else { return }
        loadURL(url, song: song)
        saveState()
    }

    func addToUserQueue(_ song: Song) {
        truthUserQueue.append(song)
        if isShuffled {
            insertRandomlyInShuffledQueue(song)
        } else {
            userQueue.append(song)
        }
        saveState()
    }

    func addToUserQueue(_ songs: [Song]) {
        truthUserQueue.append(contentsOf: songs)
        if isShuffled {
            songs.forEach { insertRandomlyInShuffledQueue($0) }
        } else {
            userQueue.append(contentsOf: songs)
        }
        saveState()
    }

    func removeFromUserQueue(at index: Int) {
        guard userQueue.indices.contains(index) else { return }
        let songId = userQueue[index].id
        userQueue.remove(at: index)
        if let i = truthUserQueue.firstIndex(where: { $0.id == songId }) {
            truthUserQueue.remove(at: i)
        }
        saveState()
    }

    func moveInUserQueue(from: IndexSet, to: Int) {
        let oldTruth = truthUserQueue
        userQueue.move(fromOffsets: from, toOffset: to)
        truthUserQueue = Self.rebuildTruthPreservingTapped(
            oldTruth: oldTruth, newVisible: userQueue
        )
        saveState()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        let songId = queue[index].song.id
        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
        if let i = truthAlbumQueue.firstIndex(where: { $0.id == songId }) {
            truthAlbumQueue.remove(at: i)
        } else if let i = truthUserQueue.firstIndex(where: { $0.id == songId }) {
            truthUserQueue.remove(at: i)
        }
        saveState()
    }

    func moveInAlbumQueue(from: IndexSet, to: Int) {
        let oldAlbumTruth = truthAlbumQueue
        let oldUserTruth = truthUserQueue
        let offset = currentIndex + 1
        var adjustedFrom = IndexSet()
        for i in from { adjustedFrom.insert(i + offset) }
        queue.move(fromOffsets: adjustedFrom, toOffset: to + offset)
        if !isShuffled {
            let visibleSongs = queue.map { $0.song }
            truthAlbumQueue = Self.rebuildTruthPreservingTapped(
                oldTruth: oldAlbumTruth, newVisible: visibleSongs
            )
            let visibleIds = Set(visibleSongs.map { $0.id })
            truthUserQueue = oldUserTruth.filter { !visibleIds.contains($0.id) }
        }
        saveState()
    }

    private static func rebuildTruthPreservingTapped(oldTruth: [Song], newVisible: [Song]) -> [Song] {
        let visibleIds = Set(newVisible.map { $0.id })
        var result = newVisible
        for index in 0..<oldTruth.count {
            let song = oldTruth[index]
            if visibleIds.contains(song.id) { continue }
            if index > 0 {
                let leftAnchorId = oldTruth[index - 1].id
                if let anchorIdx = result.firstIndex(where: { $0.id == leftAnchorId }) {
                    result.insert(song, at: anchorIdx + 1)
                    continue
                }
            }
            result.insert(song, at: 0)
        }
        return result
    }

    func clearAllQueues() {
        playNextQueue = []
        userQueue = []
        let removeFrom = currentIndex + 1
        if removeFrom < queue.count {
            queue.removeSubrange(removeFrom...)
        }
        let currentId = currentSong?.id
        truthPlayNextQueue = []
        truthUserQueue = []
        if let cur = currentId {
            truthAlbumQueue = truthAlbumQueue.filter { $0.id == cur }
        } else {
            truthAlbumQueue = []
        }
        saveState()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func pause() {
        engine.pause()
        isPlaying = false
        MPNowPlayingInfoCenter.default().playbackState = .paused
        saveState()
    }

    func resume() {
        guard let song = currentSong else { return }
        if !isEngineLoaded {
            resumeTime = currentTime
            guard let url = resolveURL(songId: song.id) else { return }
            loadURL(url, song: song)
        } else {
            engine.resume()
            isPlaying = true
            MPNowPlayingInfoCenter.default().playbackState = .playing
        }
    }

    func stop() {
        engine.stop()
        isEngineLoaded = false
        crossfadeTriggered = false
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        currentSong = nil
        isPlaying = false
        isBuffering = false
        isPlayingFromPlayNext = false
        currentTime = 0
        duration = 0
        queue = []
        currentIndex = 0
        playNextQueue = []
        userQueue = []
        truthAlbumQueue = []
        truthPlayNextQueue = []
        truthUserQueue = []
        isShuffled = false
        updateNowPlayingInfo()
        clearSavedState()
    }

    func toggleShuffle() {
        if isShuffled {
            let remainingAlbum: Set<String> = Set(queue[(min(currentIndex + 1, queue.count))...].map { $0.song.id })
            let remainingPN = Set(playNextQueue.map { $0.id })
            let remainingUQ = Set(userQueue.map { $0.id })
            let allRemaining = remainingAlbum.union(remainingPN).union(remainingUQ)
            let currentId = currentSong?.id

            let restoredAlbum = truthAlbumQueue.filter {
                $0.id != currentId && allRemaining.contains($0.id)
            }
            if let cur = currentSong {
                queue = [QueueItem(song: cur)] + restoredAlbum.map { QueueItem(song: $0) }
            } else {
                queue = restoredAlbum.map { QueueItem(song: $0) }
            }
            currentIndex = 0
            playNextQueue = truthPlayNextQueue.filter {
                $0.id != currentId && allRemaining.contains($0.id)
            }
            userQueue = truthUserQueue.filter {
                $0.id != currentId && allRemaining.contains($0.id)
            }
            isShuffled = false
        } else {
            let upcoming = playNextQueue.map { QueueItem(song: $0) }
                + Array(queue[(currentIndex + 1)...])
                + userQueue.map { QueueItem(song: $0) }
            queue.replaceSubrange((currentIndex + 1)..., with: upcoming.shuffled())
            playNextQueue = []
            userQueue = []
            isShuffled = true
        }
        saveState()
    }

    func cycleRepeatMode() {
        repeatMode = repeatMode.nextMode
    }

    func seek(to time: Double) {
        isSeeking = true
        currentTime = time
        engine.seek(to: time) { [weak self] finished in
            Task { @MainActor [weak self] in
                if finished { self?.currentTime = time }
                self?.isSeeking = false
            }
        }
    }

    func setCurrentSongStarred(_ starred: Bool) {
        guard var song = currentSong else { return }
        song.starred = starred ? "starred" : nil
        currentSong = song
        if currentIndex < queue.count {
            queue[currentIndex].song.starred = song.starred
        }
        updateNowPlayingInfo()
    }

    private func playCurrent() {
        guard currentIndex >= 0 && currentIndex < queue.count else { return }
        startPlayback(queueItem: queue[currentIndex])
        saveState()
    }

    private func startPlayback(queueItem: QueueItem) {
        let song = queueItem.song
        currentSong = song
        hasScrobbledCurrent = false
        guard let url = resolveURL(songId: song.id) else {
            if OfflineModeService.shared.isOffline {
                NotificationCenter.default.post(name: .showToast, object: tr("Not available offline", "Offline nicht verfügbar"))
            }
            return
        }
        loadURL(url, song: song)
    }

    private func loadURL(_ url: URL, song: Song) {
        crossfadeTriggered = false
        artworkLoadTask?.cancel()
        artworkLoadTask = nil
        isBuffering = true
        currentTime = 0
        duration = Double(song.duration ?? 0)

        let seekTo = resumeTime
        resumeTime = 0

        engine.play(url: url)
        isEngineLoaded = true

        if seekTo > 1 {
            engine.seek(to: seekTo)
        }

        currentArtwork = nil
        loadArtworkAsync(for: song)
        updateNowPlayingInfo(song: song)
        probeStreamFormat(songId: song.id, url: url, duration: Double(song.duration ?? 0))
        schedulePlaybackWatchdog(songId: song.id, url: url, duration: Double(song.duration ?? 0))
        Task { try? await apiService.scrobble(songId: song.id, submission: false) }
    }

    // MARK: - Engine setup

    private func setupEngine() {
        engine.onTrackFinished = { [weak self] in
            guard let self else { return }
            Task { @MainActor [self] in
                if self.crossfadeTriggered {
                    self.crossfadeTriggered = false
                } else {
                    self.playNext(triggeredByUser: false)
                }
            }
        }

        engine.$currentTime
            .sink { [weak self] time in
                guard let self else { return }
                Task { @MainActor [self] in
                    guard !self.isSeeking else { return }
                    self.currentTime = time
                    self.timePublisher.send((time: time, duration: self.duration))
                    self.updateNowPlayingInfo()
                    if let songId = self.currentSong?.id {
                        self.scrobbleIfNeeded(songId: songId)
                    }
                    if !self.crossfadeTriggered {
                        self.checkCrossfadeTrigger(currentTime: time)
                    }
                }
            }
            .store(in: &engineSubscriptions)

        engine.$duration
            .sink { [weak self] d in
                guard let self, d > 0 else { return }
                Task { @MainActor [self] in
                    self.duration = d
                }
            }
            .store(in: &engineSubscriptions)

        engine.$isPlaying
            .sink { [weak self] playing in
                guard let self else { return }
                Task { @MainActor [self] in
                    if playing {
                        self.isBuffering = false
                        self.playbackWatchdog?.cancel()
                    }
                    self.isPlaying = playing
                    if playing {
                        MPNowPlayingInfoCenter.default().playbackState = .playing
                    }
                }
            }
            .store(in: &engineSubscriptions)
    }

    // MARK: - Crossfade

    private var crossfadeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "crossfadeEnabled")
    }

    private var crossfadeDuration: Double {
        let v = UserDefaults.standard.integer(forKey: "crossfadeDuration")
        return v >= 1 ? Double(v) : 5
    }

    private func checkCrossfadeTrigger(currentTime: Double) {
        guard crossfadeEnabled, !crossfadeTriggered, duration > 1 else { return }
        guard crossfadeDuration < duration else { return }
        let triggerAt = duration - crossfadeDuration
        guard currentTime >= triggerAt else { return }
        guard !(repeatMode == .one && playNextQueue.isEmpty) else { return }
        guard let nextSong = peekNextSong() else { return }
        guard !isCrossfadeIncompatibleRoute else { return }
        crossfadeTriggered = true
        advanceQueueState()
        crossfadeToSong(nextSong)
        saveState()
    }

    private var isCrossfadeIncompatibleRoute: Bool {
        engine.isExternalPlaybackActive
    }

    private func crossfadeToSong(_ song: Song) {
        guard let url = resolveURL(songId: song.id) else { return }
        engine.crossfadeDuration = crossfadeDuration
        engine.triggerCrossfade(nextURL: url)
        crossfadeTriggered = true
        currentSong = song
        currentTime = 0
        hasScrobbledCurrent = false
        isEngineLoaded = true
        if let d = song.duration { duration = Double(d) }
        updateNowPlayingInfo(song: song)
        MPNowPlayingInfoCenter.default().playbackState = .playing
        loadArtworkAsync(for: song)
        probeStreamFormat(songId: song.id, url: url, duration: Double(song.duration ?? 0))
        schedulePlaybackWatchdog(songId: song.id, url: url, duration: Double(song.duration ?? 0))
        Task { try? await apiService.scrobble(songId: song.id, submission: false) }
    }

    private func peekNextSong() -> Song? {
        if !playNextQueue.isEmpty { return playNextQueue.first }
        switch repeatMode {
        case .one: return nil
        case .all:
            guard !queue.isEmpty else { return nil }
            return queue[(currentIndex + 1) % queue.count].song
        case .off:
            if currentIndex + 1 < queue.count {
                return queue[currentIndex + 1].song
            } else if !userQueue.isEmpty {
                return userQueue.first
            }
            return nil
        }
    }

    private func advanceQueueState() {
        if !playNextQueue.isEmpty {
            playNextQueue.removeFirst()
            isPlayingFromPlayNext = true
        } else {
            isPlayingFromPlayNext = false
            switch repeatMode {
            case .one: break
            case .all:
                guard !queue.isEmpty else { return }
                currentIndex = (currentIndex + 1) % queue.count
            case .off:
                if currentIndex + 1 < queue.count {
                    currentIndex += 1
                } else if !userQueue.isEmpty {
                    let song = userQueue.removeFirst()
                    queue.append(QueueItem(song: song))
                    currentIndex = queue.count - 1
                }
            }
        }
    }

    // MARK: - Scrobble

    private func scrobbleIfNeeded(songId: String) {
        guard !hasScrobbledCurrent else { return }
        let threshold = min(duration * 0.5, 240)
        guard threshold > 0, currentTime >= threshold else { return }
        hasScrobbledCurrent = true
        let serverId = AppState.shared.serverStore.activeServer?.stableId ?? ""
        let scrobbleAt = Date().timeIntervalSince1970
        Task {
            do {
                try await apiService.scrobble(songId: songId, submission: true, playedAt: scrobbleAt)
            } catch {
                guard !serverId.isEmpty else { return }
                await PlayLogService.shared.addPendingScrobble(
                    songId: songId, serverId: serverId, playedAt: scrobbleAt
                )
            }
        }
    }

    // MARK: - Artwork

    private func loadArtworkAsync(for song: Song) {
        artworkLoadTask?.cancel()
        guard let coverID = song.coverArt,
              let artURL = apiService.coverArtURL(id: coverID, size: 600) else { return }

        artworkLoadTask = Task.detached(priority: .utility) { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: artURL),
                  !Task.isCancelled,
                  let nsImage = NSImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in nsImage }
            await MainActor.run { [weak self] in
                self?.currentArtwork = artwork
                self?.updateNowPlayingInfo()
            }
        }
    }

    // MARK: - Remote Controls

    private func setupRemoteControls() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let e = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: e.positionTime) }
            }
            return .success
        }
    }

    // MARK: - Now Playing

    private func updateNowPlayingInfo(song: Song? = nil) {
        let s = song ?? currentSong
        guard let s else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.artist ?? "",
            MPMediaItemPropertyAlbumTitle: s.album ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue as NSNumber
        ]

        if let artwork = currentArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
