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

    private struct ShuffleSnapshot {
        var playNextQueue: [Song]
        var queue: [QueueItem]
        var currentIndex: Int
        var userQueue: [Song]
    }
    private var shuffleSnapshot: ShuffleSnapshot?
    private var isPlayingFromPlayNext = false

    private let engine = CrossfadeEngine()
    private var engineSubscriptions = Set<AnyCancellable>()
    private var crossfadeTriggered = false
    private var isEngineLoaded = false

    private var apiService: SubsonicAPIService { SubsonicAPIService.shared }

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
        static let shuffleSnapshotQueue = "shelv_mac_shuffleSnapshotQueue"
        static let shuffleSnapshotPN    = "shelv_mac_shuffleSnapshotPN"
        static let shuffleSnapshotUQ    = "shelv_mac_shuffleSnapshotUQ"
        static let shuffleSnapshotIndex = "shelv_mac_shuffleSnapshotIndex"
        static let isPlayingFromPlayNext = "shelv_mac_isPlayingFromPlayNext"
    }

    private init() {
        setupRemoteControls()
        setupEngine()
        restoreState()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.saveState() }
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
        if let snap = shuffleSnapshot {
            let snapSongs = snap.queue.map { $0.song }
            if let data = try? encoder.encode(snapSongs) { defaults.set(data, forKey: StateKey.shuffleSnapshotQueue) }
            if let data = try? encoder.encode(snap.playNextQueue) { defaults.set(data, forKey: StateKey.shuffleSnapshotPN) }
            if let data = try? encoder.encode(snap.userQueue) { defaults.set(data, forKey: StateKey.shuffleSnapshotUQ) }
            defaults.set(snap.currentIndex, forKey: StateKey.shuffleSnapshotIndex)
        } else {
            defaults.removeObject(forKey: StateKey.shuffleSnapshotQueue)
            defaults.removeObject(forKey: StateKey.shuffleSnapshotPN)
            defaults.removeObject(forKey: StateKey.shuffleSnapshotUQ)
            defaults.removeObject(forKey: StateKey.shuffleSnapshotIndex)
        }
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

        if isShuffled,
           let snapQueueData = defaults.data(forKey: StateKey.shuffleSnapshotQueue),
           let snapSongs = try? decoder.decode([Song].self, from: snapQueueData) {
            let snapQueue = snapSongs.map { QueueItem(song: $0) }
            let snapPN = (defaults.data(forKey: StateKey.shuffleSnapshotPN)
                .flatMap { try? decoder.decode([Song].self, from: $0) }) ?? []
            let snapUQ = (defaults.data(forKey: StateKey.shuffleSnapshotUQ)
                .flatMap { try? decoder.decode([Song].self, from: $0) }) ?? []
            let snapIdx = defaults.integer(forKey: StateKey.shuffleSnapshotIndex)
            shuffleSnapshot = ShuffleSnapshot(
                playNextQueue: snapPN, queue: snapQueue,
                currentIndex: snapIdx, userQueue: snapUQ
            )
        }
    }

    func play(songs: [Song], startIndex: Int = 0) {
        shuffleSnapshot = nil
        isShuffled = false
        isPlayingFromPlayNext = false
        playNextQueue = []
        userQueue = []
        queue = songs.map { QueueItem(song: $0) }
        currentIndex = startIndex
        playCurrent()
    }

    func playShuffled(songs: [Song]) {
        guard !songs.isEmpty else { return }
        let shuffled = songs.shuffled()
        let shuffledItems = shuffled.map { QueueItem(song: $0) }

        shuffleSnapshot = nil
        isShuffled = false
        isPlayingFromPlayNext = false
        playNextQueue = []
        userQueue = []
        queue = shuffledItems
        currentIndex = 0
        isShuffled = true

        shuffleSnapshot = ShuffleSnapshot(
            playNextQueue: [],
            queue: shuffledItems,
            currentIndex: 0,
            userQueue: []
        )

        playCurrent()
    }

    func playSong(_ song: Song) {
        play(songs: [song], startIndex: 0)
    }

    func playNext(triggeredByUser: Bool = true) {
        if !playNextQueue.isEmpty {
            let song = playNextQueue.removeFirst()
            isPlayingFromPlayNext = true
            currentSong = song
            hasScrobbledCurrent = false
            saveState()
            guard let url = apiService.streamURL(songId: song.id) else { return }
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

        switch repeatMode {
        case .one, .all:
            currentIndex = (currentIndex + 1) % queue.count
            playCurrent()
        case .off:
            if currentIndex < queue.count - 1 {
                currentIndex += 1
                playCurrent()
            } else if !userQueue.isEmpty {
                let song = userQueue.removeFirst()
                let item = QueueItem(song: song)
                queue.append(item)
                currentIndex = queue.count - 1
                playCurrent()
            } else {
                stop()
            }
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
        let insertAt = currentIndex + 1
        queue.insert(item, at: insertAt)
        isPlayingFromPlayNext = false
        currentIndex = insertAt
        startPlayback(queueItem: item)
        saveState()
    }

    func jumpToUserQueueTrack(at index: Int) {
        guard userQueue.indices.contains(index) else { return }
        let song = userQueue.remove(at: index)
        let item = QueueItem(song: song)
        queue.insert(item, at: currentIndex + 1)
        isPlayingFromPlayNext = false
        currentIndex = currentIndex + 1
        startPlayback(queueItem: item)
        saveState()
    }

    func addPlayNext(_ song: Song) {
        playNextQueue.append(song)
        shuffleSnapshot?.playNextQueue.append(song)
    }

    func addPlayNext(_ songs: [Song]) {
        playNextQueue.append(contentsOf: songs)
        shuffleSnapshot?.playNextQueue.append(contentsOf: songs)
    }

    func removeFromPlayNextQueue(at index: Int) {
        guard playNextQueue.indices.contains(index) else { return }
        playNextQueue.remove(at: index)
    }

    func moveInPlayNextQueue(from: IndexSet, to: Int) {
        playNextQueue.move(fromOffsets: from, toOffset: to)
        saveState()
    }

    func jumpToPlayNextTrack(at index: Int) {
        guard playNextQueue.indices.contains(index) else { return }
        let song = playNextQueue.remove(at: index)
        isPlayingFromPlayNext = true
        currentSong = song
        hasScrobbledCurrent = false
        guard let url = apiService.streamURL(songId: song.id) else { return }
        loadURL(url, song: song)
        saveState()
    }

    func addToUserQueue(_ song: Song) {
        userQueue.append(song)
        shuffleSnapshot?.userQueue.append(song)
    }

    func addToUserQueue(_ songs: [Song]) {
        userQueue.append(contentsOf: songs)
        shuffleSnapshot?.userQueue.append(contentsOf: songs)
    }

    func removeFromUserQueue(at index: Int) {
        guard userQueue.indices.contains(index) else { return }
        userQueue.remove(at: index)
    }

    func moveInUserQueue(from: IndexSet, to: Int) {
        userQueue.move(fromOffsets: from, toOffset: to)
        saveState()
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        queue.remove(at: index)
        if index < currentIndex { currentIndex -= 1 }
    }

    func moveInAlbumQueue(from: IndexSet, to: Int) {
        let offset = currentIndex + 1
        var adjustedFrom = IndexSet()
        for i in from { adjustedFrom.insert(i + offset) }
        queue.move(fromOffsets: adjustedFrom, toOffset: to + offset)
        saveState()
    }

    func clearAllQueues() {
        playNextQueue = []
        userQueue = []
        let removeFrom = currentIndex + 1
        if removeFrom < queue.count {
            queue.removeSubrange(removeFrom...)
        }
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
            guard let url = apiService.streamURL(songId: song.id) else { return }
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
        shuffleSnapshot = nil
        isShuffled = false
        updateNowPlayingInfo()
        clearSavedState()
    }

    func toggleShuffle() {
        if isShuffled {
            guard let snap = shuffleSnapshot else { isShuffled = false; saveState(); return }
            let remainingInQueue: Set<String> = currentIndex + 1 < queue.count
                ? Set(queue[(currentIndex + 1)...].map { $0.song.id }) : []
            let remainingInPN = Set(playNextQueue.map { $0.id })
            let remainingInUQ = Set(userQueue.map { $0.id })
            let allRemaining = remainingInQueue.union(remainingInPN).union(remainingInUQ)
            let currentPlayingId = currentSong?.id
            let restoredQueueSuffix = snap.queue.filter { item in
                item.song.id != currentPlayingId && allRemaining.contains(item.song.id)
            }
            if let cid = currentPlayingId, let snapItem = snap.queue.first(where: { $0.song.id == cid }) {
                queue = [snapItem] + restoredQueueSuffix
            } else {
                queue = (currentSong.map { [QueueItem(song: $0)] } ?? []) + restoredQueueSuffix
            }
            currentIndex = 0
            let snapPNIds = Set(snap.playNextQueue.map { $0.id })
            let snapUQIds = Set(snap.userQueue.map { $0.id })
            let addedPN = playNextQueue.filter { !snapPNIds.contains($0.id) }
            let addedUQ = userQueue.filter { !snapUQIds.contains($0.id) }
            playNextQueue = snap.playNextQueue.filter { allRemaining.contains($0.id) } + addedPN
            userQueue = snap.userQueue.filter { allRemaining.contains($0.id) } + addedUQ
            shuffleSnapshot = nil
            isShuffled = false
        } else {
            shuffleSnapshot = ShuffleSnapshot(
                playNextQueue: playNextQueue, queue: queue,
                currentIndex: currentIndex, userQueue: userQueue
            )
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
        guard let url = apiService.streamURL(songId: song.id) else { return }
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
                    if playing { self.isBuffering = false }
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
        crossfadeTriggered = true
        advanceQueueState()
        crossfadeToSong(nextSong)
        saveState()
    }

    private func crossfadeToSong(_ song: Song) {
        guard let url = apiService.streamURL(songId: song.id) else { return }
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
        Task { try? await apiService.scrobble(songId: songId, submission: true) }
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
