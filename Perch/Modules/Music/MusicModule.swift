import AppKit
import CoreImage
import Observation
import SwiftUI

/// What is playing, with artwork and controls. Holds the notch while music
/// plays and lingers after a pause (a setting), so a quick pause does not flicker.
@Observable
final class MusicModule: PerchModule {
    let id = "music"
    let title = "Music"
    let symbol = "music.note"
    let summary = "What is playing in any app, with artwork and controls."

    let service = NowPlayingService()
    private(set) var activity: Activity?
    /// Average colour of the artwork, lifted so it reads on black.
    private(set) var accent: Color = .white
    private(set) var artwork: NSImage?

    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var artworkData: Data?
    @ObservationIgnored private var demoObserver: NSObjectProtocol?

    var nowPlaying: NowPlaying? { service.nowPlaying }

    func start() {
        service.onChange = { [weak self] in self?.refresh() }
        service.start()
        #if DEBUG
        // Screenshots and demo GIFs without anyone's real music or artwork:
        // post the distributed notification "com.itcompleet.perch.debug.demoMusic".
        demoObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.itcompleet.perch.debug.demoMusic"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.showDemo(DemoTrack.make()) }
        }
        #endif
    }

    func stop() {
        service.stop()
        lingerTask?.cancel()
    }

    private func refresh() {
        let state = service.nowPlaying
        if state?.artwork != artworkData {
            artworkData = state?.artwork
            artwork = artworkData.flatMap(NSImage.init(data:))
            accent = artworkData.flatMap(Self.accentColor(of:)) ?? .white
        }

        guard let state else {
            lingerTask?.cancel()
            activity = nil
            return
        }
        if state.isPlaying {
            lingerTask?.cancel()
            lingerTask = nil
            if activity == nil {
                activity = Activity(id: "playing", moduleID: id, priority: .info)
            }
        } else if activity != nil, lingerTask == nil {
            let linger = Duration.milliseconds(Int(Preferences.shared.musicLinger * 1000))
            lingerTask = Task { [weak self] in
                try? await Task.sleep(for: linger)
                guard !Task.isCancelled else { return }
                self?.activity = nil
                self?.lingerTask = nil
            }
        }
    }

    /// Sneak peek: artwork and a resting equalizer whenever something is loaded.
    var restingActivity: Activity? {
        nowPlaying == nil ? nil : Activity(id: "resting", moduleID: id, priority: .background, startedAt: .distantPast)
    }

    func openSourceApp() {
        guard let bundleID = nowPlaying?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: - Views

    func compactLeading() -> AnyView {
        AnyView(ArtworkView(image: artwork, size: 22, radius: 6).frame(maxWidth: .infinity, alignment: .center))
    }

    func compactTrailing() -> AnyView {
        AnyView(EqualizerView(isPlaying: nowPlaying?.isPlaying ?? false, color: accent).frame(width: 18, height: 14).frame(maxWidth: .infinity))
    }

    func expanded() -> AnyView {
        AnyView(MusicExpandedView(module: self))
    }

    func settings() -> AnyView? {
        AnyView(MusicSettingsView())
    }

    // MARK: - Colour

    private nonisolated static let ciContext = CIContext(options: [.workingColorSpace: NSNull()])

    nonisolated static func accentColor(of data: Data) -> Color? {
        guard let image = CIImage(data: data) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: image,
            kCIInputExtentKey: CIVector(cgRect: image.extent),
        ])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(output, toBitmap: &pixel, rowBytes: 4,
                         bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                         format: .RGBA8, colorSpace: nil)
        let average = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                              blue: CGFloat(pixel[2]) / 255, alpha: 1)
        // Keep the hue, but make it bright enough to read on the black notch.
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(hue: hue, saturation: min(saturation * 1.1, 0.75), brightness: max(brightness, 0.85))
    }
}

#if DEBUG
/// A made-up track with generated artwork, for screenshots.
private enum DemoTrack {
    static func make() -> NowPlaying {
        NowPlaying(
            title: "Golden Hour",
            artist: "The Notch Birds",
            album: "Perch Sessions",
            duration: 214,
            elapsed: 71,
            timestamp: .now,
            rate: 1,
            isPlaying: true,
            bundleID: "com.apple.Music",
            artwork: artwork()
        )
    }

    /// Warm, soft colour fields, like a sunrise seen from a branch.
    private static func artwork() -> Data? {
        let size = 600
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSGradient(colors: [
            NSColor(red: 0.16, green: 0.07, blue: 0.28, alpha: 1),
            NSColor(red: 0.85, green: 0.30, blue: 0.36, alpha: 1),
            NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 1),
        ])?.draw(in: rect, angle: 90)
        let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
            (0.72, 0.30, 0.55, NSColor(red: 1.0, green: 0.85, blue: 0.45, alpha: 0.85)),
            (0.20, 0.75, 0.50, NSColor(red: 0.55, green: 0.25, blue: 0.75, alpha: 0.7)),
            (0.50, 0.55, 0.30, NSColor(red: 1.0, green: 0.55, blue: 0.40, alpha: 0.6)),
        ]
        for (x, y, r, color) in blobs {
            let centre = NSPoint(x: CGFloat(size) * x, y: CGFloat(size) * y)
            NSGradient(colors: [color, color.withAlphaComponent(0)])?
                .draw(fromCenter: centre, radius: 0, toCenter: centre, radius: CGFloat(size) * r, options: [])
        }
        // A sun low on the horizon.
        NSColor(red: 1.0, green: 0.93, blue: 0.75, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: size / 2 - 70, y: 150, width: 140, height: 140)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
