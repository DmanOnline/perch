import AppKit
import AudioToolbox
import CoreAudio

/// Volume of the default output device, through CoreAudio.
nonisolated enum SystemVolume {
    static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static var volume: Float? {
        guard let device = defaultOutput() else { return nil }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ value: Float) {
        guard let device = defaultOutput() else { return }
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var level = Float32(min(max(value, 0), 1))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &level)
        if level > 0, isMuted { setMuted(false) }
    }

    static var isMuted: Bool {
        guard let device = defaultOutput() else { return false }
        var address = address(kAudioDevicePropertyMute)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutput() else { return }
        var address = address(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

/// Listens to volume and mute of whatever the default output is, following
/// the default output when it changes (AirPods in, speakers out).
final class VolumeWatcher {
    private var onChange: (() -> Void)?
    private var device: AudioDeviceID?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var valueListener: AudioObjectPropertyListenerBlock?
    private var defaultAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attach() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, block)
        attach()
    }

    func stop() {
        detach()
        if let deviceListener {
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultAddress, .main, deviceListener)
        }
        deviceListener = nil
    }

    private func attach() {
        detach()
        guard let output = SystemVolume.defaultOutput() else { return }
        device = output
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.onChange?() }
        }
        valueListener = block
        AudioObjectAddPropertyListenerBlock(output, &volumeAddress, .main, block)
        AudioObjectAddPropertyListenerBlock(output, &muteAddress, .main, block)
    }

    private func detach() {
        guard let device, let valueListener else { return }
        AudioObjectRemovePropertyListenerBlock(device, &volumeAddress, .main, valueListener)
        AudioObjectRemovePropertyListenerBlock(device, &muteAddress, .main, valueListener)
        self.device = nil
        self.valueListener = nil
    }
}

/// Brightness of the built-in display, through the DisplayServices framework
/// that Control Center uses. Private, so looked up at runtime; without it the
/// brightness half of the pop-up simply stays off.
nonisolated enum SystemBrightness {
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    nonisolated(unsafe) private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getter: Get? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: Get.self) }
    private static let setter: Set? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: Set.self) }

    static var display: CGDirectDisplayID? {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        CGGetOnlineDisplayList(8, &ids, &count)
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var brightness: Float? {
        guard let getter, let display else { return nil }
        var value: Float = 0
        return getter(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ value: Float) {
        guard let setter, let display else { return }
        _ = setter(display, min(max(value, 0), 1))
    }
}

/// The keyboard backlight, through CoreBrightness's KeyboardBrightnessClient
/// (what Control Center uses). Private, so looked up at runtime; nil when the
/// Mac has no backlit keyboard or the class is gone.
nonisolated enum SystemKeyboardBacklight {
    private typealias Get = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias Set = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    nonisolated(unsafe) private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    private static var keyboard: UInt64? {
        guard let client, client.responds(to: NSSelectorFromString("copyKeyboardBacklightIDs")),
              let ids = client.perform(NSSelectorFromString("copyKeyboardBacklightIDs"))?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.first?.uint64Value
    }

    static var brightness: Float? {
        let selector = NSSelectorFromString("brightnessForKeyboard:")
        guard let client, let keyboard, client.responds(to: selector), let imp = client.method(for: selector) else { return nil }
        return unsafeBitCast(imp, to: Get.self)(client, selector, keyboard)
    }

    static func setBrightness(_ value: Float) {
        let selector = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let client, let keyboard, client.responds(to: selector), let imp = client.method(for: selector) else { return }
        _ = unsafeBitCast(imp, to: Set.self)(client, selector, min(max(value, 0), 1), keyboard)
    }
}
