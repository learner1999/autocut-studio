import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPreviewPlayer: ObservableObject {
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackRate: Double = 1.0

    private var player: AVPlayer?
    private var mediaURL: URL?
    private var ranges: [PlaybackRange] = []
    private var timer: Timer?
    private var pendingSeekTarget: Double?

    func play(mediaURL: URL, from requestedTime: Double, ranges: [PlaybackRange], duration: Double) {
        if self.mediaURL != mediaURL {
            self.mediaURL = mediaURL
            let item = AVPlayerItem(url: mediaURL)
            item.audioTimePitchAlgorithm = .timeDomain
            self.player = AVPlayer(playerItem: item)
        }
        self.ranges = ranges.isEmpty ? [PlaybackRange(start: 0, end: duration)] : ranges
        guard let start = nextPlayableTime(from: requestedTime) else {
            pause()
            return
        }
        seek(to: start)
        resumePlayback()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func setPlaybackRate(_ rate: Double) {
        playbackRate = min(max(rate, 0.5), 2.0)
        if isPlaying {
            resumePlayback()
        }
    }

    @discardableResult
    func jump(to requestedTime: Double, ranges: [PlaybackRange], duration: Double) -> Double {
        self.ranges = ranges.isEmpty ? [PlaybackRange(start: 0, end: duration)] : ranges
        guard let target = nextPlayableTime(from: requestedTime) else {
            pause()
            return currentTime
        }

        seek(to: target, resumeAfterSeek: true)
        if isPlaying {
            resumePlayback()
            startTimer()
        }
        return target
    }

    func seek(to time: Double, resumeAfterSeek: Bool = false) {
        currentTime = max(0, time)
        pendingSeekTarget = currentTime
        let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)
        guard let player else {
            pendingSeekTarget = nil
            return
        }

        let target = currentTime
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard finished, let self, self.pendingSeekTarget == target else { return }
                self.currentTime = target
                self.pendingSeekTarget = nil
                if resumeAfterSeek, self.isPlaying {
                    self.resumePlayback()
                }
            }
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func resumePlayback() {
        player?.rate = Float(playbackRate)
    }

    private func tick() {
        guard let player else { return }
        let time = player.currentTime().seconds
        guard time.isFinite else { return }

        if let pendingSeekTarget {
            guard abs(time - pendingSeekTarget) < 0.08 else { return }
            self.pendingSeekTarget = nil
        }

        currentTime = time

        guard let range = ranges.first(where: { $0.contains(time) }) else {
            if let next = nextPlayableTime(from: time) {
                seek(to: next, resumeAfterSeek: true)
                resumePlayback()
            } else {
                pause()
            }
            return
        }

        if time >= range.end - 0.03 {
            if let next = nextPlayableTime(after: range.end) {
                seek(to: next, resumeAfterSeek: true)
                resumePlayback()
            } else {
                pause()
            }
        }
    }

    private func nextPlayableTime(from time: Double) -> Double? {
        if let containing = ranges.first(where: { $0.contains(time) }) {
            return max(time, containing.start)
        }
        return ranges.first(where: { $0.end > time })?.start
    }

    private func nextPlayableTime(after time: Double) -> Double? {
        ranges.first(where: { $0.start > time + 0.001 })?.start
    }
}
