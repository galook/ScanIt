import Foundation
import Vision
import ImageIO
import CoreGraphics

protocol DocumentAnalyzing: Sendable { func analyze(pageAt url: URL) async throws -> PageAnalysis }
struct VisionDocumentAnalyzer: DocumentAnalyzing {
    func analyze(pageAt url: URL) async throws -> PageAnalysis {
        try Task.checkCancellation()
        return try await Task.detached(priority: .userInitiated) {
            let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate; text.recognitionLanguages = DocumentLanguage.allCases.map(\.recognitionIdentifier); text.usesLanguageCorrection = true
            let barcode = VNDetectBarcodesRequest()
            barcode.symbologies = [.qr, .code128, .code39, .code93, .ean8, .ean13, .dataMatrix, .pdf417, .aztec]
            try VNImageRequestHandler(url: url).perform([text, barcode]); try Task.checkCancellation()
            let textObservations: [VNRecognizedTextObservation] = text.results ?? []
            let barcodeObservations: [VNBarcodeObservation] = barcode.results ?? []
            let tokens: [RecognizedToken] = textObservations.compactMap { observation in guard let candidate = observation.topCandidates(1).first else { return nil }; return RecognizedToken(id: UUID(), text: candidate.string, bounds: observation.boundingBox, confidence: candidate.confidence) }
            let angles = textObservations.map { observation in atan2(Double(observation.topRight.y - observation.topLeft.y), Double(observation.topRight.x - observation.topLeft.x)) * 180 / .pi }
            let barcodes: [RecognizedBarcode] = barcodeObservations.compactMap { observation in guard let value = observation.payloadStringValue else { return nil }; return RecognizedBarcode(id: UUID(), payload: value, symbology: observation.symbology.rawValue, bounds: observation.boundingBox) }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let sample = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 128,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { throw AnalysisError.invalidImage }
            let characteristics = sampledCharacteristics(sample)
            let textHeights: [Double] = tokens.compactMap { token in
                let height = Double(token.bounds.height)
                return height > 0 ? height : nil
            }
            return PageAnalysis(tokens: tokens, barcodes: barcodes, lineAngles: angles, analyzedAt: Date(), visualComplexity: characteristics.complexity, mostlyGrayscale: characteristics.mostlyGrayscale, smallestTextHeight: textHeights.min())
        }.value
    }
}

private func sampledCharacteristics(_ image: CGImage) -> (complexity: Double, mostlyGrayscale: Bool) {
    let width = 128, height = 128, bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return (0.5, false) }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var edgeTotal = 0.0, colorTotal = 0.0
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * 4
            let red = Double(pixels[offset]), green = Double(pixels[offset + 1]), blue = Double(pixels[offset + 2])
            colorTotal += (max(red, max(green, blue)) - min(red, min(green, blue))) / 255
            if x > 0 {
                let previous = offset - 4
                let luminance = red * 0.299 + green * 0.587 + blue * 0.114
                let prior = Double(pixels[previous]) * 0.299 + Double(pixels[previous + 1]) * 0.587 + Double(pixels[previous + 2]) * 0.114
                edgeTotal += abs(luminance - prior) / 255
            }
        }
    }
    let count = Double(width * height)
    let colorfulness = colorTotal / count
    let edgeDensity = edgeTotal / count
    return (min(1, edgeDensity * 3.5 + colorfulness * 0.75), colorfulness < 0.035)
}

enum AnalysisError: LocalizedError { case invalidImage; var errorDescription: String? { String(localized: "The page could not be analyzed.") } }

func conservativeOrientation(from angles: [Double], readableCharacters: Int) -> Int {
    guard readableCharacters >= 6, !angles.isEmpty else { return 0 }
    let buckets = angles.reduce(into: [Int: Int]()) { counts, angle in
        let normalized = ((angle + 180).truncatingRemainder(dividingBy: 360)) - 180
        let bucket: Int = abs(normalized) <= 30 ? 0 : abs(abs(normalized) - 90) <= 30 ? (normalized > 0 ? 270 : 90) : abs(abs(normalized) - 180) <= 30 ? 180 : -1
        if bucket >= 0 { counts[bucket, default: 0] += 1 }
    }
    guard let best = buckets.max(by: { $0.value < $1.value }), best.value * 100 >= max(1, angles.count) * 65 else { return 0 }
    return best.key
}
