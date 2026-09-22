import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import ImageIO

struct CleanupService {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func smartCleanup(source: URL, destination: URL) throws { guard let input = CIImage(contentsOf: source) else { throw ImagingError.invalidImage }; try smartCleanup(input: input, destination: destination) }
    func smartCleanup(image: CGImage, destination: URL) throws { try smartCleanup(input: CIImage(cgImage: image), destination: destination) }
    private func smartCleanup(input: CIImage, destination: URL) throws { let controls = CIFilter.colorControls(); controls.inputImage = input; controls.contrast = 1.14; controls.brightness = 0.02; controls.saturation = 0.15; guard let output = controls.outputImage, let color = CGColorSpace(name: CGColorSpace.sRGB) else { throw ImagingError.renderFailed }; try context.writeJPEGRepresentation(of: output, to: destination, colorSpace: color, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96]) }
    func manualCleanup(source: URL, strokes: [RedactionStroke], destination: URL) throws {
        guard let input = CIImage(contentsOf: source), !strokes.isEmpty else { throw ImagingError.invalidImage }
        try manualCleanup(input: input, strokes: strokes, destination: destination)
    }

    func manualCleanup(image: CGImage, strokes: [RedactionStroke], destination: URL) throws {
        guard !strokes.isEmpty else { throw ImagingError.invalidImage }
        try manualCleanup(input: CIImage(cgImage: image), strokes: strokes, destination: destination)
    }

    private func manualCleanup(input: CIImage, strokes: [RedactionStroke], destination: URL) throws {
        let width = Int(input.extent.width), height = Int(input.extent.height)
        guard let maskContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { throw ImagingError.renderFailed }
        maskContext.setFillColor(gray: 0, alpha: 1); maskContext.fill(CGRect(x: 0, y: 0, width: width, height: height)); maskContext.setStrokeColor(gray: 1, alpha: 1)
        for stroke in strokes where !stroke.points.isEmpty {
            maskContext.setLineWidth(stroke.width * CGFloat(width)); maskContext.setLineCap(.round); maskContext.beginPath()
            maskContext.move(to: CGPoint(x: stroke.points[0].x * CGFloat(width), y: stroke.points[0].y * CGFloat(height)))
            for point in stroke.points.dropFirst() { maskContext.addLine(to: CGPoint(x: point.x * CGFloat(width), y: point.y * CGFloat(height))) }
            maskContext.strokePath()
        }
        guard let maskImage = maskContext.makeImage() else { throw ImagingError.renderFailed }
        let average = CIFilter.areaAverage(); average.inputImage = input; average.extent = input.extent
        guard var paper = average.outputImage else { throw ImagingError.renderFailed }
        paper = paper.transformed(by: CGAffineTransform(scaleX: input.extent.width, y: input.extent.height)).cropped(to: input.extent)
        let blend = CIFilter.blendWithMask(); blend.inputImage = paper; blend.backgroundImage = input; blend.maskImage = CIImage(cgImage: maskImage)
        guard let output = blend.outputImage, let color = CGColorSpace(name: CGColorSpace.sRGB) else { throw ImagingError.renderFailed }
        try context.writeJPEGRepresentation(of: output, to: destination, colorSpace: color, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96])
    }
}
