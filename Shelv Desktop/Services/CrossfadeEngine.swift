import AVFoundation
import Combine
import Foundation

final class CrossfadeEngine: ObservableObject {

    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying: Bool = false
    private(set) var isCrossfading: Bool = false

    var crossfadeDuration: TimeInterval = 5
    var volume: Float = 1.0 {
        didSet {
            guard !isCrossfading else { return }
            activePlayer.volume = volume
        }
    }
    var onTrackFinished: (() -> Void)?
    var isExternalPlaybackActive: Bool { activePlayer.isExternalPlaybackActive }

    private let playerA: AVPlayer
    private let playerB: AVPlayer
    private var activePlayer: AVPlayer
    private var inactivePlayer: AVPlayer

    private var timeObserverToken: Any?
    private var timeObserverPlayer: AVPlayer?
    private var fadeCancellable: AnyCancellable?
    private var fadeStartDate: Date?
    private var itemFinishedObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStallObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var currentURL: URL?
    private var retryCount: Int = 0
    private let maxRetries: Int = 3
    private var isSeeking = false

    init() {
        let a = AVPlayer()
        let b = AVPlayer()
        a.allowsExternalPlayback = true
        b.allowsExternalPlayback = true
        a.automaticallyWaitsToMinimizeStalling = false
        b.automaticallyWaitsToMinimizeStalling = false
        playerA = a
        playerB = b
        activePlayer = a
        inactivePlayer = b
    }

    deinit {
        cancelFade()
        removeTimeObserver()
        removeItemFinishedObserver()
        itemStatusObservation?.invalidate()
        if let obs = itemFailureObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = itemStallObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Public API

    func play(url: URL) {
        currentURL = url
        retryCount = 0
        loadAndPlay(url: url)
    }

    private func loadAndPlay(url: URL) {
        cancelFade()
        isCrossfading = false

        inactivePlayer.pause()
        inactivePlayer.replaceCurrentItem(with: nil)
        inactivePlayer.volume = volume

        let item = makePlayerItem(url: url)
        activePlayer.replaceCurrentItem(with: item)
        activePlayer.volume = volume
        activePlayer.play()

        isPlaying = true
        setupTimeObserver()
        setupItemFinishedObserver()
        setupFailureObservation(item: item, url: url)
    }

    private func setupFailureObservation(item: AVPlayerItem, url: URL) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            if observedItem.status == .failed {
                Task { @MainActor in self.scheduleRetry(for: url) }
            }
        }

        if let obs = itemFailureObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        itemFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.scheduleRetry(for: url) }
        }

        if let obs = itemStallObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        itemStallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, let currentItem = self.activePlayer.currentItem else { return }
            if currentItem.status == .failed {
                Task { @MainActor in self.scheduleRetry(for: url) }
            }
        }
    }

    @MainActor
    private func scheduleRetry(for url: URL) {
        guard currentURL == url else { return }
        guard retryCount < maxRetries else { return }
        retryCount += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard self.currentURL == url else { return }
            self.loadAndPlay(url: url)
        }
    }

    func triggerCrossfade(nextURL: URL) {
        inactivePlayer.replaceCurrentItem(with: makePlayerItem(url: nextURL))
        inactivePlayer.volume = 0
        beginFade()
    }

    func pause() {
        activePlayer.pause()
        if isCrossfading { inactivePlayer.pause() }
        isPlaying = false
    }

    func resume() {
        activePlayer.play()
        if isCrossfading { inactivePlayer.play() }
        isPlaying = true
    }

    func seek(to seconds: TimeInterval, completion: ((Bool) -> Void)? = nil) {
        let time = CMTime(seconds: seconds, preferredTimescale: 1000)
        isSeeking = true
        currentTime = seconds
        let targetPlayer = isCrossfading ? inactivePlayer : activePlayer
        targetPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            self?.isSeeking = false
            completion?(finished)
        }
    }

    func stop() {
        cancelFade()
        removeTimeObserver()
        removeItemFinishedObserver()
        removeFailureObservation()
        currentURL = nil
        retryCount = 0
        activePlayer.pause()
        activePlayer.replaceCurrentItem(with: nil)
        inactivePlayer.pause()
        inactivePlayer.replaceCurrentItem(with: nil)
        inactivePlayer.volume = volume
        isPlaying = false
        isCrossfading = false
        currentTime = 0
        duration = 0
    }

    private func removeFailureObservation() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let obs = itemFailureObserver {
            NotificationCenter.default.removeObserver(obs)
            itemFailureObserver = nil
        }
        if let obs = itemStallObserver {
            NotificationCenter.default.removeObserver(obs)
            itemStallObserver = nil
        }
    }

    // MARK: - Crossfade

    private func beginFade() {
        isCrossfading = true
        fadeStartDate = Date()
        inactivePlayer.seek(to: .zero)
        inactivePlayer.play()

        fadeCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.fadeStep() }
    }

    private func fadeStep() {
        guard let start = fadeStartDate else { return }
        let progress = min(Date().timeIntervalSince(start) / crossfadeDuration, 1.0)
        activePlayer.volume = volume * Float(1.0 - progress)
        inactivePlayer.volume = volume * Float(progress)
        if !isSeeking { currentTime = inactivePlayer.currentTime().seconds }
        if progress >= 1.0 { completeFade() }
    }

    private func completeFade() {
        cancelFade()
        removeTimeObserver()
        removeItemFinishedObserver()

        let outgoing = activePlayer
        outgoing.pause()
        outgoing.replaceCurrentItem(with: nil)
        outgoing.volume = volume

        swap(&activePlayer, &inactivePlayer)
        activePlayer.volume = volume
        isCrossfading = false
        isPlaying = true

        setupTimeObserver()
        setupItemFinishedObserver()
        onTrackFinished?()
    }

    private func cancelFade() {
        fadeCancellable?.cancel()
        fadeCancellable = nil
        fadeStartDate = nil
    }

    // MARK: - Observers

    private func setupTimeObserver() {
        removeTimeObserver()
        let player = activePlayer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 1000)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            self.refreshDuration()
            guard !self.isCrossfading, !self.isSeeking else { return }
            self.currentTime = time.seconds
        }
        timeObserverPlayer = player
    }

    private func removeTimeObserver() {
        guard let token = timeObserverToken, let player = timeObserverPlayer else { return }
        player.removeTimeObserver(token)
        timeObserverToken = nil
        timeObserverPlayer = nil
    }

    private func setupItemFinishedObserver() {
        removeItemFinishedObserver()
        guard let item = activePlayer.currentItem else { return }
        itemFinishedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self, !self.isCrossfading else { return }
            self.isPlaying = false
            self.onTrackFinished?()
        }
    }

    private func removeItemFinishedObserver() {
        guard let obs = itemFinishedObserver else { return }
        NotificationCenter.default.removeObserver(obs)
        itemFinishedObserver = nil
    }

    private func refreshDuration() {
        guard let item = activePlayer.currentItem else { return }
        let d = item.duration.seconds
        if d.isFinite && d > 0 { duration = d }
    }

    // MARK: - AVPlayerItem factory

    private func makePlayerItem(url: URL) -> AVPlayerItem {
        let headers: [String: String] = ["Range": "bytes=0-"]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 10
        return item
    }
}
