import Foundation
import Observation

/// Streams Now Playing from the system.
///
/// `MediaRemote.framework` only answers processes Apple entitles, and Perch is
/// not one. `/usr/bin/perl` is, so we run the vendored `mediaremote-adapter.pl`
/// under it; the script loads our embedded `MediaRemoteAdapter.framework` and
/// writes one JSON line per change. See `Vendor/MediaRemoteAdapter/README.md`.
@Observable
final class NowPlayingService {
    private(set) var nowPlaying: NowPlaying?
    /// False when the adapter could not be started or keeps crashing.
    private(set) var isAvailable = true

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var restartTask: Task<Void, Never>?

    private static let perl = URL(filePath: "/usr/bin/perl")

    private var adapterArguments: [String]? {
        guard
            let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworks = Bundle.main.privateFrameworksURL
        else { return nil }
        let framework = frameworks.appending(path: "MediaRemoteAdapter.framework")
        return [script.path(percentEncoded: false), framework.path(percentEncoded: false)]
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        launch()
    }

    func stop() {
        isRunning = false
        restartTask?.cancel()
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        // Answer the click at once; the stream confirms a moment later.
        if var current = nowPlaying {
            switch command {
            case .play: current.isPlaying = true
            case .pause: current.isPlaying = false
            case .togglePlayPause: current.isPlaying.toggle()
            case .nextTrack, .previousTrack: break
            }
            if current.isPlaying != nowPlaying?.isPlaying {
                current.elapsed = nowPlaying?.elapsed(at: .now)
                current.timestamp = .now
                update(current)
            }
        }
        run(["send", String(command.rawValue)])
    }

    func seek(to seconds: TimeInterval) {
        if var current = nowPlaying {
            current.elapsed = seconds
            current.timestamp = .now
            update(current)
        }
        run(["seek", String(Int(seconds * 1_000_000))])
    }

    // MARK: - Process

    private func launch() {
        guard isRunning, let arguments = adapterArguments else {
            isAvailable = false
            return
        }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = arguments + ["stream", "--micros", "--debounce=60"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] state in
            Task { @MainActor in self?.update(state) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.processEnded() }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            processEnded()
        }
    }

    private func processEnded() {
        process = nil
        guard isRunning else { return }
        failures += 1
        if failures > 5 {
            isAvailable = false
            update(nil)
            return
        }
        // Back off: 1, 2, 4, 8, 16 seconds.
        let delay = Duration.seconds(1 << (failures - 1))
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.launch()
        }
    }

    private func update(_ state: NowPlaying?) {
        if state != nil { failures = 0 }
        guard state != nowPlaying else { return }
        nowPlaying = state
        onChange?()
    }

    private func run(_ command: [String]) {
        guard let arguments = adapterArguments else { return }
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = arguments + command
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

/// Splits the adapter's output into lines and parses them. Only ever called
/// from the pipe's readability handler, which runs serially.
private nonisolated final class LineReader: @unchecked Sendable {
    private var buffer = Data()
    private var stream = NowPlayingStream()
    private let emit: @Sendable (NowPlaying?) -> Void

    init(emit: @escaping @Sendable (NowPlaying?) -> Void) {
        self.emit = emit
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if case .some(let state) = stream.consume(Data(line)) {
                emit(state)
            }
        }
    }
}
