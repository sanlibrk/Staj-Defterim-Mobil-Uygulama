import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PhotoCodec {
    private static let maxSide = 1_800

    static func load(_ item: PhotosPickerItem) async throws -> Data {
        guard let source = try await item.loadTransferable(type: Data.self) else {
            throw PhotoConversionError()
        }
        return try await Task.detached(priority: .userInitiated) {
            guard let jpeg = jpeg(fromPickedData: source) else { throw PhotoConversionError() }
            return jpeg
        }.value
    }

    private static func jpeg(fromPickedData data: Data) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions),
              let context = CGContext(
                data: nil, width: thumbnail.width, height: thumbnail.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(thumbnail.width), height: CGFloat(thumbnail.height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(bounds)
        context.draw(thumbnail, in: bounds)
        let output = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(
                output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
              ) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    @MainActor
    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let longestSide = max(size.width, size.height)
        guard longestSide > 0, size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, CGFloat(maxSide) / longestSide)
        let target = CGSize(width: max(1, (size.width * scale).rounded()),
                            height: max(1, (size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).jpegData(withCompressionQuality: 0.82) { context in
            let bounds = CGRect(origin: .zero, size: target)
            context.cgContext.setFillColor(CGColor(gray: 1, alpha: 1))
            context.cgContext.fill(bounds)
            image.draw(in: bounds)
        }
    }
}

private struct PhotoConversionError: LocalizedError {
    var errorDescription: String? { "Görsel fotoğraf olarak hazırlanamadı." }
}

@MainActor
struct CameraPicker: UIViewControllerRepresentable {
    enum Access {
        case ready, denied, restricted, unavailable
    }

    let completion: (UIImage?) -> Void

    static func access() async -> Access {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}
