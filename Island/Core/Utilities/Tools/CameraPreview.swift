import SwiftUI
import AVFoundation

/// Owns the camera session for the launcher's Camera page: starts when
/// the page appears, stops when it goes. Nothing is recorded.
///
/// Background blur is macOS's own Portrait effect (Video Effects): the
/// system applies it to the picture, so ARC just shows what it's given —
/// and offers a shortcut to the switch. Apps can't turn it on for you.
@MainActor
final class CameraController: ObservableObject {

    enum Access {
        case checking
        case allowed
        case denied
    }

    @Published private(set) var access: Access = .checking

    /// macOS's background blur is on.
    @Published private(set) var isBlurOn = AVCaptureDevice.isPortraitEffectEnabled

    /// This camera can do it (it needs an Apple silicon Mac's built-in or
    /// Continuity camera).
    @Published private(set) var canBlur = false

    let session = AVCaptureSession()

    private var isConfigured = false
    private var poller: Timer?

    func start() {

        switch AVCaptureDevice.authorizationStatus(for: .video) {

        case .authorized:
            access = .allowed
            run()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    self?.access = granted ? .allowed : .denied
                    if granted { self?.run() }
                }
            }

        default:
            access = .denied
        }

        // The user flips Video Effects in Control Center; follow it.
        let poller = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshEffects() }
        }

        RunLoop.main.add(poller, forMode: .common)
        self.poller = poller
    }

    func stop() {

        poller?.invalidate()
        poller = nil

        guard session.isRunning else { return }

        let session = self.session

        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    /// Opens macOS's Video Effects panel, where Background blur lives.
    func openVideoEffects() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    private func refreshEffects() {

        isBlurOn = AVCaptureDevice.isPortraitEffectEnabled

        if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
            canBlur = device.activeFormat.isPortraitEffectSupported
        }
    }

    private func run() {

        if !isConfigured {

            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                access = .denied
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .medium
            session.addInput(input)
            session.commitConfiguration()

            isConfigured = true
        }

        refreshEffects()

        let session = self.session

        DispatchQueue.global(qos: .userInitiated).async {
            if !session.isRunning { session.startRunning() }
        }
    }
}

/// The live picture, mirrored the way a mirror is.
struct CameraPreviewView: NSViewRepresentable {

    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {

        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill

        if let connection = view.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {}

    final class PreviewNSView: NSView {

        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = previewLayer
        }

        required init?(coder: NSCoder) { fatalError() }
    }
}
