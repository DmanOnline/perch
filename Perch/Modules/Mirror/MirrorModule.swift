import AppKit
@preconcurrency import AVFoundation
import Observation
import SwiftUI

/// Your camera in the open notch, mirrored, for a look before a call. The
/// camera runs only while the Mirror tab is on screen, so the green light
/// means what it says.
@Observable
final class MirrorModule: PerchModule {
    let id = "mirror"
    let title = "Mirror"
    let symbol = "person.crop.square"
    let summary = "Your camera in the notch, for a quick look before a call. On only while you look."
    let activity: Activity? = nil
    /// Room for a face: about a 16:9 picture across the open notch.
    let expandedHeight: CGFloat? = 380

    private(set) var access: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @ObservationIgnored let camera = CameraSession()

    func start() {}

    func stop() {
        camera.stop()
    }

    /// Called when the tab appears.
    func show() {
        access = AVCaptureDevice.authorizationStatus(for: .video)
        switch access {
        case .authorized:
            camera.start()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                access = granted ? .authorized : .denied
                if granted { camera.start() }
            }
        default:
            break
        }
    }

    /// Called when the tab goes away: the camera goes off at once.
    func hide() {
        camera.stop()
    }

    func compactLeading() -> AnyView { AnyView(EmptyView()) }
    func compactTrailing() -> AnyView { AnyView(EmptyView()) }

    func expanded() -> AnyView {
        AnyView(MirrorView(module: self))
    }
}

/// The capture session, run on its own queue as AVFoundation asks.
nonisolated final class CameraSession: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.itcompleet.perch.camera")
    private var configured = false

    func start() {
        queue.async { [self] in
            if !configured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configure() {
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        // The built-in FaceTime camera when there is one; else any camera.
        let device = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified
        ).devices.first ?? AVCaptureDevice.default(for: .video)
        if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
    }
}

private struct MirrorView: View {
    let module: MirrorModule

    var body: some View {
        Group {
            switch module.access {
            case .authorized:
                CameraPreview(session: module.camera.session)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    )
            case .notDetermined:
                message("camera", "Asking for the camera…")
            default:
                VStack(spacing: 10) {
                    message("video.slash", "Perch may not use the camera")
                    Button("Open Camera settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                    }
                    .controlSize(.small)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { module.show() }
        .onDisappear { module.hide() }
    }

    private func message(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24))
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.55))
    }
}

/// The live picture, mirrored like a mirror and filling its frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        } else {
            layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
