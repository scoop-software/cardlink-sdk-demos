import SwiftUI
import AVFoundation
import Vision

// MARK: - CanScannerView

/// SwiftUI view for CAN (Card Access Number) scanning using camera OCR.
///
/// This is a standalone Swift UI component that provides camera preview and text recognition.
/// It uses the same consensus algorithm as the Kotlin SDK's CanScanner.
///
/// For programmatic use without UI, use the Kotlin `CanScanner` class directly:
/// ```swift
/// let scanner = CanScanner.Companion.shared.create()
/// let result = try await scanner.scan(config: config)
/// ```
///
/// Usage:
/// ```swift
/// CanScannerView { result in
///     switch result {
///     case .success(let can):
///         print("Detected CAN: \(can)")
///     case .failure(.cancelled):
///         print("Cancelled")
///     case .failure(let error):
///         print("Error: \(error.localizedDescription)")
///     }
/// }
/// ```
@available(iOS 13.0, *)
public struct CanScannerView: UIViewControllerRepresentable {
    public typealias ScanResult = Result<String, CanScannerError>

    public enum CanScannerError: Error, LocalizedError {
        case cancelled
        case cameraUnavailable
        case permissionDenied
        case recognitionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "Scanning was cancelled"
            case .cameraUnavailable: return "Camera is not available"
            case .permissionDenied: return "Camera permission was denied"
            case .recognitionFailed(let msg): return "Recognition failed: \(msg)"
            }
        }
    }

    private let onResult: (ScanResult) -> Void
    private let requiredReadings: Int
    private let consensusRatio: Float
    private let onProgress: ((String, Int, Int) -> Void)?

    /// Creates a CAN scanner view.
    /// - Parameters:
    ///   - requiredReadings: Number of consistent readings needed (default: 3)
    ///   - consensusRatio: Minimum ratio of agreeing readings (default: 1.0 for 100% consensus)
    ///   - onProgress: Callback for detection progress updates (can, currentCount, requiredCount)
    ///   - onResult: Callback when scanning completes
    public init(
        requiredReadings: Int = 3,
        consensusRatio: Float = 1.0,
        onProgress: ((String, Int, Int) -> Void)? = nil,
        onResult: @escaping (ScanResult) -> Void
    ) {
        self.requiredReadings = requiredReadings
        self.consensusRatio = consensusRatio
        self.onProgress = onProgress
        self.onResult = onResult
    }

    public func makeUIViewController(context: Context) -> CanScannerViewController {
        let vc = CanScannerViewController()
        vc.requiredReadings = requiredReadings
        vc.consensusRatio = consensusRatio
        vc.onProgress = onProgress
        vc.onResult = onResult
        return vc
    }

    public func updateUIViewController(_ uiViewController: CanScannerViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - CanScannerViewController

/// UIViewController that handles camera capture and text recognition for CAN scanning.
@available(iOS 13.0, *)
public class CanScannerViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    public var requiredReadings: Int = 3
    public var consensusRatio: Float = 1.0
    public var onProgress: ((String, Int, Int) -> Void)?
    public var onResult: ((CanScannerView.ScanResult) -> Void)?

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let processingQueue = DispatchQueue(label: "de.scoopsoftware.cardlink.can.processing")

    // Consensus tracking (same algorithm as Kotlin CanConsensusTracker)
    private var consensusTracker: ConsensusTracker?
    private var hasCompleted = false

    // Overlay view for targeting frame
    private var frameOverlay: UIView!

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupOverlayViews()
        consensusTracker = ConsensusTracker(
            requiredReadings: requiredReadings,
            consensusRatio: consensusRatio
        )
        checkCameraPermission()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    private func setupOverlayViews() {
        // Frame overlay to guide the user
        frameOverlay = UIView()
        frameOverlay.backgroundColor = .clear
        frameOverlay.layer.borderColor = UIColor.white.cgColor
        frameOverlay.layer.borderWidth = 2
        frameOverlay.layer.cornerRadius = 8
        frameOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(frameOverlay)

        NSLayoutConstraint.activate([
            frameOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            frameOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            frameOverlay.widthAnchor.constraint(equalToConstant: 200),
            frameOverlay.heightAnchor.constraint(equalToConstant: 60)
        ])
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupCamera()
                    } else {
                        self?.onResult?(.failure(.permissionDenied))
                    }
                }
            }
        case .denied, .restricted:
            onResult?(.failure(.permissionDenied))
        @unknown default:
            onResult?(.failure(.cameraUnavailable))
        }
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(input) else {
            onResult?(.failure(.cameraUnavailable))
            return
        }

        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: processingQueue)

        guard session.canAddOutput(output) else {
            onResult?(.failure(.cameraUnavailable))
            return
        }
        session.addOutput(output)

        // Set up preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        self.captureSession = session
        self.previewLayer = previewLayer

        // Start session
        processingQueue.async {
            session.startRunning()
        }
    }

    private func stopScanning() {
        captureSession?.stopRunning()
        captureSession = nil
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !hasCompleted,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self, !self.hasCompleted else { return }

            if let error = error {
                print("Vision error: \(error.localizedDescription)")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: " ")

            if !recognizedText.isEmpty {
                self.processRecognizedText(recognizedText)
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }

    private func processRecognizedText(_ text: String) {
        guard let tracker = consensusTracker else { return }

        // Extract 6-digit CAN candidates (same logic as Kotlin extractCanCandidates)
        let candidates = CanPatternMatcher.extractCandidates(from: text)
        guard !candidates.isEmpty else { return }

        // Add to tracker and check for consensus
        if let result = tracker.addCandidates(candidates) {
            hasCompleted = true
            DispatchQueue.main.async { [weak self] in
                self?.stopScanning()
                self?.onResult?(.success(result.can))
            }
        } else if let stats = tracker.currentStats {
            // Update progress via callback
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onProgress?(stats.can, stats.count, self.requiredReadings)
            }
        }
    }

    /// Call this to cancel scanning and return.
    public func cancel() {
        hasCompleted = true
        stopScanning()
        onResult?(.failure(.cancelled))
    }
}

// MARK: - Shared Logic (matches Kotlin implementation)

/// Pattern matcher for CAN values. Matches the Kotlin `extractCanCandidates` function.
private enum CanPatternMatcher {
    private static let pattern = try! NSRegularExpression(pattern: "\\b\\d{6}\\b")

    /// Extracts all valid 6-digit CAN candidates from text.
    static func extractCandidates(from text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let candidate = String(text[range])
            return isValidCan(candidate) ? candidate : nil
        }
    }

    /// Validates a CAN string. Matches the Kotlin `isValidCan` function.
    static func isValidCan(_ value: String) -> Bool {
        return value.count == 6 && value.allSatisfy { $0.isNumber }
    }
}

/// Consensus tracker for reliable CAN detection. Matches the Kotlin `CanConsensusTracker` class.
private class ConsensusTracker {
    private let requiredReadings: Int
    private let consensusRatio: Float
    private var detectedNumbers: [String] = []

    struct Stats {
        let can: String
        let count: Int
    }

    struct Result {
        let can: String
        let confidence: Int
    }

    init(requiredReadings: Int, consensusRatio: Float) {
        self.requiredReadings = requiredReadings
        self.consensusRatio = consensusRatio
    }

    var currentStats: Stats? {
        let counts = Dictionary(grouping: detectedNumbers, by: { $0 }).mapValues { $0.count }
        guard let mostCommon = counts.max(by: { $0.value < $1.value }) else { return nil }
        return Stats(can: mostCommon.key, count: mostCommon.value)
    }

    /// Adds candidates and returns result if consensus is reached.
    func addCandidates(_ candidates: [String]) -> Result? {
        guard !candidates.isEmpty else { return nil }

        detectedNumbers.append(contentsOf: candidates)

        let counts = Dictionary(grouping: detectedNumbers, by: { $0 }).mapValues { $0.count }
        guard let mostCommon = counts.max(by: { $0.value < $1.value }) else { return nil }

        // Check if we have enough readings
        if detectedNumbers.count >= requiredReadings {
            let minRequired = Int(Float(requiredReadings) * consensusRatio)
            if mostCommon.value >= minRequired {
                return Result(can: mostCommon.key, confidence: mostCommon.value)
            } else {
                // No clear consensus, trim old readings
                while detectedNumbers.count > requiredReadings / 2 {
                    detectedNumbers.removeFirst()
                }
            }
        }

        return nil
    }

    func reset() {
        detectedNumbers.removeAll()
    }
}

// MARK: - Preview Provider

#if DEBUG
@available(iOS 13.0, *)
struct CanScannerView_Previews: PreviewProvider {
    static var previews: some View {
        CanScannerView { result in
            print("Result: \(result)")
        }
    }
}
#endif
