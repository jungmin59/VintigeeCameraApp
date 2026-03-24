import AVFoundation
import CoreImage
import UIKit
import SwiftUI
import Combine
import Photos

class CameraManager: NSObject, ObservableObject {
    
    @Published var previewImage: UIImage?
    @Published var capturedImage: UIImage?
    
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var filter: DICA2005Filter?
    
    override init() {
        super.init()
        filter = DICA2005Filter()
    }
    
    func configure() {
        checkPermission()
    }
    
    private func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.setupSession() }
            }
        default:
            break
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        // ✅ 고해상도 활성화
        photoOutput.isHighResolutionCaptureEnabled = true
        
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    func capturePhoto() {
        var settings = AVCapturePhotoSettings()
        // ✅ 픽셀버퍼 포맷 지정 (무압축)
        if photoOutput.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) {
            settings = AVCapturePhotoSettings(format: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        }
        settings.flashMode = .on
        settings.isHighResolutionPhotoEnabled = true
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func switchCamera() {
        guard let currentInput = videoInput else { return }
        let currentPosition = currentInput.device.position
        let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }
        
        session.beginConfiguration()
        session.removeInput(currentInput)
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        }
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
        }
        session.commitConfiguration()
    }
    
    private func saveToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }
}

// MARK: - 실시간 프리뷰
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        let currentPosition = videoInput?.device.position
        let orientation: UIImage.Orientation = currentPosition == .front ? .upMirrored : .up
        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
        
        let filtered = filter?.apply(to: uiImage) ?? uiImage
        
        DispatchQueue.main.async { [weak self] in
            self?.previewImage = filtered
        }
    }
}

// MARK: - 사진 촬영
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        
        // ✅ 픽셀버퍼 직접 사용 (무압축)
        if let pixelBuffer = photo.pixelBuffer {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
            
            let currentPosition = videoInput?.device.position
            let orientation: UIImage.Orientation = currentPosition == .front ? .leftMirrored : .right
            let image = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
            
            let filtered = filter?.apply(to: image) ?? image
            saveToPhotoLibrary(filtered)
            
            DispatchQueue.main.async { [weak self] in
                self?.capturedImage = filtered
            }
            return
        }
        
        // ✅ pixelBuffer 없을 때 fallback
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        
        let currentPosition = videoInput?.device.position
        let finalImage: UIImage
        if currentPosition == .front, let cgImage = image.cgImage {
            finalImage = UIImage(cgImage: cgImage, scale: image.scale, orientation: .leftMirrored)
        } else {
            finalImage = image
        }
        
        let filtered = filter?.apply(to: finalImage) ?? finalImage
        saveToPhotoLibrary(filtered)
        
        DispatchQueue.main.async { [weak self] in
            self?.capturedImage = filtered
        }
    }
}
