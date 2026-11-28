import SwiftUI
import AVFoundation

/// Owns the camera session for the launcher's Camera page: starts when
/// the page appears, stops when it goes. Nothing is recorded.
@MainActor
final class CameraController: ObservableObject {

    enum Access {
        case checking
        case allowed
        case denied
    }

    @Published private(set) var access: Access = .checking

    let session = AVCaptureSession()

    private var isConfigured = false

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
    }

    func stop() {

        guard session.isRunning else { return }

        let session = self.session

        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
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
