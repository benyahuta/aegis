// Screenshot text recognition for "Choose a screenshot" (SPEC §5.3 step 2, §10.1 screen 9).
//
// Uses `VNRecognizeTextRequest`, which runs on-device on iOS 18 and macOS 14 (the newer
// `RecognizeTextRequest` needs macOS 15). No network, no permission prompt: the image comes from
// PhotosPicker or a dropped file, and the recognized text stays in memory only (§5.3 "Storage:
// none"). Never log the recognized text.

import CoreGraphics
import Foundation
import ImageIO
import Vision

public enum OCRError: Error, Sendable, Equatable {
    /// The data is not an image ImageIO can decode.
    case unreadableImage
    /// Vision failed.
    case recognitionFailed
}

public enum OCR {
    /// Largest image side passed to Vision. Bigger screenshots are scaled down by ImageIO, which
    /// keeps memory low in the Share Extension (P1) and is still sharp enough for text.
    public static let maxPixelSize = 4_096

    /// Recognizes text in encoded image data (PNG, JPEG, HEIC…). Lines come back top to bottom,
    /// joined with "\n".
    public static func recognizeText(in imageData: Data) async throws(OCRError) -> String {
        guard let image = decode(imageData) else { throw .unreadableImage }
        return try await recognizeText(in: SendableImage(image: image))
    }

    /// Recognizes text in an already decoded image.
    public static func recognizeText(in image: CGImage) async throws(OCRError) -> String {
        try await recognizeText(in: SendableImage(image: image))
    }

    // MARK: - Internals

    /// CGImage is immutable; this box lets it cross into the Vision work queue.
    private struct SendableImage: @unchecked Sendable {
        let image: CGImage
    }

    private static func recognizeText(in boxed: SendableImage) async throws(OCRError) -> String {
        let result: Result<String, OCRError> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: perform(on: boxed.image))
            }
        }
        return try result.get()
    }

    private static func perform(on image: CGImage) -> Result<String, OCRError> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .failure(.recognitionFailed)
        }
        let observations = request.results ?? []
        // Vision's coordinates start at the bottom left: sort top to bottom, then left to right.
        let lines = observations
            .sorted { lhs, rhs in
                let dy = lhs.boundingBox.midY - rhs.boundingBox.midY
                if abs(dy) > 0.01 { return dy > 0 }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
        return .success(lines.joined(separator: "\n"))
    }

    static func decode(_ data: Data) -> CGImage? {
        guard !data.isEmpty, let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
