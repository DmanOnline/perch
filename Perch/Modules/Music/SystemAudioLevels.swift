import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// How the bars next to the notch move while music plays.
nonisolated enum MusicVisualizer: String, CaseIterable, Sendable {
    /// A made-up dance, no permission needed.
    case animated
    /// The real loudness of the sound the Mac plays, per frequency band.
    case live
}

/// Loudness of the sound the Mac plays, in four bands from bass to treble,
/// for the live equalizer. Reads the system output through a Core Audio
/// process tap (macOS 14.2+), the lightest of macOS's audio permissions:
/// "system audio recording only", no microphone, no screen. Perch only
/// measures; nothing is kept or sent anywhere.
///
/// Runs only while a live equalizer is on screen: views call `acquire()` and
/// `release()`.
@MainActor
final class LiveAudio {
    static let shared = LiveAudio()

    private var users = 0
    private var engine: TapEngine?
    private var stopTask: Task<Void, Never>?

    /// Current band levels, 0...1, bass first. Zeros while not running.
    var levels: [Float] { engine?.levels ?? [0, 0, 0, 0] }
    /// When the engine last heard any sound; nil if it never has.
    var lastSignal: Date? { engine?.lastSignal }
    /// When the current engine started.
    private(set) var startedAt: Date?
    /// The tap could not be made at all (old macOS, Core Audio refused).
    private(set) var failed = false

    func acquire() {
        users += 1
        stopTask?.cancel()
        stopTask = nil
        guard engine == nil else { return }
        let engine = TapEngine()
        if engine.start() {
            self.engine = engine
            startedAt = .now
            failed = false
        } else {
            failed = true
        }
    }

    func release() {
        users = max(0, users - 1)
        guard users == 0, engine != nil else { return }
        // A short grace: switching screens or tabs re-acquires at once, and
        // building the tap again each time would be wasted work.
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.users == 0 else { return }
            self.engine?.stop()
            self.engine = nil
            self.startedAt = nil
        }
    }
}

/// The tap, its private aggregate device and the analysis, on Core Audio's
/// I/O thread. Only `levels` and `lastSignal` cross to the main actor, behind
/// a lock.
nonisolated final class TapEngine: @unchecked Sendable {
    private struct Shared {
        var levels: [Float] = [0, 0, 0, 0]
        var lastSignal: Date?
    }

    private let shared = Mutex(Shared())
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.itcompleet.perch.audio-levels", qos: .userInteractive)
    private var analyzer: BandAnalyzer?

    var levels: [Float] { shared.withLock { $0.levels } }
    var lastSignal: Date? { shared.withLock { $0.lastSignal } }

    func start() -> Bool {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "Perch equalizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            return false
        }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr,
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0 else {
            stop()
            return false
        }
        analyzer = BandAnalyzer(sampleRate: Float(format.mSampleRate),
                                channels: Int(format.mChannelsPerFrame),
                                interleaved: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)

        var aggregate: [String: Any] = [
            "name": "Perch equalizer",
            "uid": "com.itcompleet.perch.equalizer.\(UUID().uuidString)",
            "private": true,
            "stacked": false,
            "tapautostart": true,
            "taps": [["uid": description.uuid.uuidString, "drift": true]],
        ]
        if let output = Self.defaultOutputUID() {
            aggregate["master"] = output
            aggregate["subdevices"] = [["uid": output]]
        }
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else {
            deviceID = AudioObjectID(kAudioObjectUnknown)
            stop()
            return false
        }

        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard status == noErr, AudioDeviceStart(deviceID, procID) == noErr else {
            stop()
            return false
        }
        return true
    }

    func stop() {
        if deviceID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(deviceID, procID)
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        guard let analyzer else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let result = analyzer.feed(buffers) else { return }
        shared.withLock {
            $0.levels = result.levels
            if result.heard { $0.lastSignal = .now }
        }
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}

/// Turns blocks of samples into four smoothed band levels with an FFT. Each
/// band follows its own recent peak, so the bars use their whole height at
/// any volume.
nonisolated final class BandAnalyzer {
    static let size = 1024
    /// Band edges in Hz: bass, low mids, high mids, treble.
    static let edges: [Float] = [40, 180, 700, 2800, 11000]
    /// How many decibels below a band's recent peak counts as silent.
    static let range: Float = 30

    private let sampleRate: Float
    private let channels: Int
    private let interleaved: Bool
    private let setup: FFTSetup
    private let window: [Float]
    private var ring = [Float](repeating: 0, count: size)
    private var filled = 0
    private var peaks: [Float] = [-60, -60, -60, -60]
    private var smoothed: [Float] = [0, 0, 0, 0]

    init(sampleRate: Float, channels: Int, interleaved: Bool) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48000
        self.channels = max(1, channels)
        self.interleaved = interleaved
        setup = vDSP_create_fftsetup(vDSP_Length(log2(Float(Self.size))), FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Adds the new samples (mixed to mono) and analyses the latest 1024.
    func feed(_ buffers: UnsafeMutableAudioBufferListPointer) -> (levels: [Float], heard: Bool)? {
        var mono: [Float] = []
        if interleaved, let buffer = buffers.first, let data = buffer.mData {
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
            let stride = max(1, Int(buffer.mNumberChannels))
            mono.reserveCapacity(count / stride)
            var index = 0
            while index + stride <= count {
                var sum: Float = 0
                for channel in 0..<stride { sum += samples[index + channel] }
                mono.append(sum / Float(stride))
                index += stride
            }
        } else {
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
                if mono.isEmpty { mono = Array(samples) } else {
                    for i in 0..<min(count, mono.count) { mono[i] += samples[i] }
                }
            }
            if buffers.count > 1 { mono = vDSP.multiply(1 / Float(buffers.count), mono) }
        }
        guard !mono.isEmpty else { return nil }

        // Keep the newest `size` samples.
        if mono.count >= Self.size {
            ring = Array(mono.suffix(Self.size))
        } else {
            ring.removeFirst(mono.count)
            ring.append(contentsOf: mono)
        }
        filled = min(Self.size, filled + mono.count)
        guard filled == Self.size else { return nil }

        let rms = vDSP.rootMeanSquare(ring)
        let heard = rms > 0.0005
        let power = spectrum()
        let binWidth = sampleRate / Float(Self.size)

        var levels = [Float](repeating: 0, count: 4)
        for band in 0..<4 {
            let low = max(1, Int(Self.edges[band] / binWidth))
            let high = min(power.count - 1, max(low + 1, Int(Self.edges[band + 1] / binWidth)))
            let mean = vDSP.mean(power[low..<high])
            let db = 10 * log10(mean + 1e-12)
            // The peak jumps up at once and sinks about 4 dB a second.
            peaks[band] = max(db, peaks[band] - 0.04, -60)
            let target = heard ? min(1, max(0, (db - peaks[band] + Self.range) / Self.range)) : 0
            // Rise fast, fall slower: the bars snap to a beat and then ease down.
            let rate: Float = target > smoothed[band] ? 0.6 : 0.18
            smoothed[band] += (target - smoothed[band]) * rate
            levels[band] = smoothed[band]
        }
        return (levels, heard)
    }

    /// Power per frequency bin of the windowed ring.
    private func spectrum() -> [Float] {
        let half = Self.size / 2
        let windowed = vDSP.multiply(ring, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imaginaryPointer.baseAddress!)
                windowed.withUnsafeBufferPointer { samples in
                    samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, vDSP_Length(log2(Float(Self.size))), FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        return power
    }
}
