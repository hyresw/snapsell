import SwiftUI
import AVFoundation
import UIKit

// MARK: - Camera Manager

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

    @Published var capturedImage: UIImage?
    @Published var isSessionRunning = false
    @Published var permissionDenied = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isUsingFront = false

    private var photoContinuation: CheckedContinuation<UIImage, Error>?

    // MARK: - Setup

    func checkPermissionsAndSetup() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await setupSession()
            } else {
                await MainActor.run { permissionDenied = true }
            }
        default:
            await MainActor.run { permissionDenied = true }
        }
    }

    private func setupSession() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }

        session.commitConfiguration()

        await MainActor.run { isSessionRunning = true }
        session.startRunning()
    }

    func stopSession() {
        session.stopRunning()
    }

    // MARK: - Capture Photo

    func capturePhoto() async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            self.photoContinuation = continuation

            let settings = AVCapturePhotoSettings()
            settings.flashMode = flashMode

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                let hevcSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                hevcSettings.flashMode = flashMode
                photoOutput.capturePhoto(with: hevcSettings, delegate: self)
            } else {
                photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    // MARK: - Flash

    func cycleFlash() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on:   flashMode = .off
        case .off:  flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    // MARK: - Flip Camera

    func flipCamera() {
        guard let currentInput else { return }

        session.beginConfiguration()
        session.removeInput(currentInput)

        let newPosition: AVCaptureDevice.Position = isUsingFront ? .back : .front
        isUsingFront.toggle()

        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice),
              session.canAddInput(newInput)
        else {
            session.addInput(currentInput)
            session.commitConfiguration()
            return
        }

        session.addInput(newInput)
        self.currentInput = newInput
        session.commitConfiguration()
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            photoContinuation?.resume(throwing: error)
            photoContinuation = nil
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else {
            photoContinuation?.resume(throwing: CameraError.captureFailure)
            photoContinuation = nil
            return
        }

        let oriented = image.fixedOrientation()
        photoContinuation?.resume(returning: oriented)
        photoContinuation = nil
    }
}

enum CameraError: LocalizedError {
    case captureFailure
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .captureFailure: return "Failed to capture photo."
        case .permissionDenied: return "Camera permission denied. Enable in Settings."
        }
    }
}

// MARK: - UIImage Helpers

extension UIImage {
    /// Scales the image down so its longest side is at most `maxDimension` **pixels**.
    /// Must use pixel dimensions (size * scale) — UIImage.size is in points,
    /// so a 4032×3024 photo on a 3x device reports only 1344×1008 points and
    /// would skip resizing entirely if compared against a points-based threshold.
    func resizedToMaxDimension(_ maxDimension: CGFloat) -> UIImage {
        let pixelW = size.width * scale
        let pixelH = size.height * scale
        let longest = max(pixelW, pixelH)
        guard longest > maxDimension else { return self }
        let factor = maxDimension / longest
        let newSize = CGSize(width: (pixelW * factor).rounded(), height: (pixelH * factor).rounded())
        // scale = 1 so output dimensions equal the specified pixel values (no Retina multiplication)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return result
    }
}

