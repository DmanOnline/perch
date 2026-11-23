import Foundation

/// What the system says is playing, from any app that reports to Now Playing.
nonisolated struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval?
    /// Elapsed time as of `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var rate: Double
    var isPlaying: Bool
    var bundleID: String?
    var artwork: Data?

    /// Elapsed time at `now`, extrapolated from the last report while playing.
    func elapsed(at now: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        guard isPlaying, let timestamp else { return elapsed }
        let current = elapsed + now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1)
        if let duration { return min(max(current, 0), duration) }
        return max(current, 0)
    }

    func progress(at now: Date) -> Double? {
        guard let duration, duration > 0, let elapsed = elapsed(at: now) else { return nil }
        return elapsed / duration
    }
}

/// Folds the JSON lines of `mediaremote-adapter.pl stream --micros` into the
/// current state. Diff payloads update the last full one; `null` removes a key.
nonisolated struct NowPlayingStream {
    private var payload: [String: Any] = [:]
    private var artwork: Data?

    /// Returns the new state, or `nil` when nothing is playing.
    /// Lines that are not data updates leave the state alone.
    mutating func consume(_ line: Data) -> NowPlaying?? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["type"] as? String == "data",
            let update = object["payload"] as? [String: Any]
        else { return .none }

        let isDiff = object["diff"] as? Bool ?? false
        if !isDiff {
            payload = [:]
            artwork = nil
        }
        for (key, value) in update {
            if value is NSNull { payload[key] = nil } else { payload[key] = value }
        }
        if !isDiff || update.keys.contains("artworkData") {
            artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        }
        return .some(state())
    }

    private func state() -> NowPlaying? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        let rate = payload["playbackRate"] as? Double ?? 0
        return NowPlaying(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            duration: Self.seconds(payload["durationMicros"]),
            elapsed: Self.seconds(payload["elapsedTimeMicros"]),
            timestamp: Self.seconds(payload["timestampEpochMicros"]).map { Date(timeIntervalSince1970: $0) },
            rate: rate,
            isPlaying: payload["playing"] as? Bool ?? (rate > 0),
            bundleID: payload["bundleIdentifier"] as? String,
            artwork: artwork
        )
    }

    private static func seconds(_ micros: Any?) -> TimeInterval? {
        (micros as? NSNumber).map { $0.doubleValue / 1_000_000 }
    }
}

/// MediaRemote command IDs understood by `mediaremote-adapter.pl send`.
nonisolated enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}
