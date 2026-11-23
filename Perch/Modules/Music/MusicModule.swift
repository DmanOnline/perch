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

    var nowPlaying: NowPlaying? { service.nowPlaying }

    func start() {
        service.onChange = { [weak self] in self?.refresh() }
        service.start()
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
