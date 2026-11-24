import AppKit
import ApplicationServices

/// The volume and brightness keys, caught before macOS shows its own pop-up.
/// Needs Accessibility permission; without it Perch only watches the volume.
nonisolated enum MediaKey: Sendable {
    case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
    case keyboardLightUp, keyboardLightDown, keyboardLightToggle

    /// NX_KEYTYPE_* codes carried in system-defined events.
    init?(code: Int) {
        switch code {
        case 0: self = .volumeUp
        case 1: self = .volumeDown
        case 7: self = .mute
        case 2: self = .brightnessUp
        case 3: self = .brightnessDown
        case 21: self = .keyboardLightUp
        case 22: self = .keyboardLightDown
        case 23: self = .keyboardLightToggle
        default: return nil
        }
    }

    /// Decodes a system-defined event: subtype 8 carries the key code in the
    /// high half of data1 and the state (0xA down, 0xB up) in the low half.
    static func decode(subtype: Int, data1: Int) -> (key: MediaKey, isDown: Bool)? {
        guard subtype == 8, let key = MediaKey(code: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let state = (data1 & 0x0000_FF00) >> 8
        return (key, state == 0xA)
    }
}

final class MediaKeyTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    fileprivate var onKey: ((MediaKey, NSEvent.ModifierFlags) -> Void)?

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Shows macOS's "allow Perch to control your computer" prompt.
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary // kAXTrustedCheckOptionPrompt
        AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    /// Starts catching the keys. Returns false without permission.
    @discardableResult
    func start(onKey: @escaping (MediaKey, NSEvent.ModifierFlags) -> Void) -> Bool {
        guard tap == nil, Self.hasPermission else { return tap != nil }
        self.onKey = onKey
        let mask = CGEventMask(1 << 14) // NSSystemDefined
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: context)
        else { return false }
        tap = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// Runs on the main run loop. Volume and brightness keys are handled by Perch
/// and swallowed, so macOS does not show its own pop-up; everything else passes.
private nonisolated func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                          refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    // Only plain values cross into the main actor.
    let tapAddress = UInt(bitPattern: refcon)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: tapAddress) else { return }
            Unmanaged<MediaKeyTap>.fromOpaque(pointer).takeUnretainedValue().reenable()
        }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14, let ns = NSEvent(cgEvent: event),
          let (key, isDown) = MediaKey.decode(subtype: Int(ns.subtype.rawValue), data1: ns.data1)
    else { return Unmanaged.passUnretained(event) }
    let flags = ns.modifierFlags.rawValue
    if isDown {
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: tapAddress) else { return }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(pointer).takeUnretainedValue()
            tap.onKey?(key, NSEvent.ModifierFlags(rawValue: flags))
        }
    }
    return nil
}
