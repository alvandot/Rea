import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// On-device Vision OCR. Returns normalized (0…1) boxes with a top-left origin.
struct VisionTextRecognizer: ImageTextRecognizer {
    func recognizeText(in imageData: Data, preferredLanguages: [String]) async throws -> [RecognizedText] {
        #if canImport(Vision) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TranslationError.failed("could not decode image")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if !preferredLanguages.isEmpty { request.recognitionLanguages = preferredLanguages }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            // Vision's origin is bottom-left; flip into top-left normalized space.
            let flipped = CGRect(
                x: box.origin.x,
                y: 1 - box.origin.y - box.height,
                width: box.width,
                height: box.height
            )
            return RecognizedText(
                string: candidate.string,
                boundingBox: flipped,
                confidence: candidate.confidence
            )
        }
        #else
        throw TranslationError.unavailable
        #endif
    }
}
