import SwiftUI
import AVFoundation
import Vision
import CoreImage

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

    /// Blurs everything behind you (see `BackgroundBlurProcessor`).
    @Published var blurBackground = false {
        didSet { processor.isBlurring = blurBackground }
    }

    let session = AVCaptureSession()

    let processor = BackgroundBlurProcessor()

    private let videoOutput = AVCaptureVideoDataOutput()

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

        blurBackground = false

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

            // Frames for the background blur. Idle (and cheap) until it's on.
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.setSampleBufferDelegate(processor, queue: processor.queue)

            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

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


// MARK: - Background blur

/// Blurs everything but the person in front of the camera: Vision finds
/// the person in each frame, Core Image blurs the rest and blends the two.
/// All on this Mac, and only while the blur is switched on.
final class BackgroundBlurProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    let queue = DispatchQueue(label: "arc.camera.blur", qos: .userInitiated)

    private let lock = NSLock()
    private var blurring = false

    private let context = CIContext()
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .fast
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    /// Where finished frames go (the on-screen view), set from the main thread.
    weak var target: ProcessedFrameNSView?

    var isBlurring: Bool {
        get { lock.withLock { blurring } }
        set { lock.withLock { blurring = newValue } }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard isBlurring, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)

        guard
            (try? handler.perform([request])) != nil,
            let maskBuffer = request.results?.first?.pixelBuffer
        else {
            return
        }

        let image = CIImage(cvPixelBuffer: buffer)

        var mask = CIImage(cvPixelBuffer: maskBuffer)

        mask = mask.transformed(by: CGAffineTransform(
            scaleX: image.extent.width / mask.extent.width,
            y: image.extent.height / mask.extent.height
        ))

        let blurred = image
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 14)
            .cropped(to: image.extent)

        let output = image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: mask
        ])

        guard let frame = context.createCGImage(output, from: image.extent) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.target?.layer?.contents = frame
        }
    }
}

/// Shows the blurred frames (mirrored, like the plain preview).
struct ProcessedFrameView: NSViewRepresentable {

    let processor: BackgroundBlurProcessor

    func makeNSView(context: Context) -> ProcessedFrameNSView {
        let view = ProcessedFrameNSView()
        processor.target = view
        return view
    }

    func updateNSView(_ nsView: ProcessedFrameNSView, context: Context) {
        processor.target = nsView
    }
}

final class ProcessedFrameNSView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        // Mirrored.
        layer?.sublayerTransform = CATransform3DIdentity
        layer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
    }

    required init?(coder: NSCoder) { fatalError() }
}
