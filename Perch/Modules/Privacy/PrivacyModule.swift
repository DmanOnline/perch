import CoreAudio
import CoreMediaIO
import Observation
import SwiftUI

/// When an app turns on the camera or microphone, a short moment slides out
/// of the notch. No lasting dot: macOS already shows its own indicator at the
/// notch and in the menu bar, and a third would only repeat it.
@Observable
final class PrivacyModule: PerchModule {
    let id = "privacy"
    let title = "Camera & Microphone"
    let symbol = "video.fill"
    let summary = "A short moment when an app turns on your camera or microphone."
    let tabID = "none"

    private(set) var cameraOn = false
    private(set) var microphoneOn = false
    private(set) var activity: Activity?
    /// What the last moment announced.
    private(set) var announced: Kind = .camera

    enum Kind { case camera, microphone }

    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var clearTask: Task<Void, Never>?
    /// The Mirror's own use of the camera is not news.
    @ObservationIgnored weak var mirror: MirrorModule?

    static let shared = PrivacyModule()

    func start() {
        cameraOn = Self.isCameraRunning()
        microphoneOn = Self.isMicrophoneRunning()
        // Device lists change (AirPods, external cameras), so re-reading every
        // two seconds is simpler and sturdier than listeners per device; it is
        // a handful of property reads.
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }

    func stop() {
        poll?.cancel()
        clearTask?.cancel()
    }

    private func refresh() {
        let camera = Self.isCameraRunning() && !(mirror?.camera.session.isRunning ?? false)
        let microphone = Self.isMicrophoneRunning()
        if camera, !cameraOn { announce(.camera) } else if microphone, !microphoneOn { announce(.microphone) }
        cameraOn = camera
        microphoneOn = microphone
    }

    private func announce(_ kind: Kind) {
        announced = kind
        Haptics.play(.event)
        clearTask?.cancel()
        let shown = Activity(id: "on", moduleID: id, priority: .attention, expiresAt: .now + 3)
        activity = shown
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.activity?.id == shown.id else { return }
            self?.activity = nil
        }
    }

    // MARK: Reading the devices

    nonisolated static func isCameraRunning() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return false }
        return devices.contains { device in
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &value) == 0 && value != 0
        }
    }

    nonisolated static func isMicrophoneRunning() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return false }
        return devices.contains { device in
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return false }
            var running = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &running, 0, nil, &valueSize, &value) == noErr && value != 0
        }
    }

    // MARK: Views

    static let cameraGreen = Color(red: 0.20, green: 0.84, blue: 0.40)
    static let microphoneOrange = Color(red: 1.0, green: 0.62, blue: 0.04)

    func compactLeading() -> AnyView {
        AnyView(
            Image(systemName: announced == .camera ? "video.fill" : "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(announced == .camera ? Self.cameraGreen : Self.microphoneOrange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 9)
        )
    }

    func compactTrailing() -> AnyView {
        AnyView(
            Text(announced == .camera ? "Camera" : "Mic")
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(announced == .camera ? Self.cameraGreen : Self.microphoneOrange)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 9)
        )
    }

    func expanded() -> AnyView { AnyView(EmptyView()) }
}
