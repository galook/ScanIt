import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

struct RedactionRenderer {
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    func apply(strokes: [RedactionStroke], to sourceURL: URL, outputURL: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImagingError.invalidImage }
        try apply(strokes: strokes, to: image, outputURL: outputURL)
    }
    func apply(strokes: [RedactionStroke], to image: CGImage, outputURL: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB(); guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImagingError.renderFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); context.setStrokeColor(UIColor.black.cgColor); context.setLineCap(.square)
        for stroke in strokes where stroke.points.count > 1 { context.setLineWidth(stroke.width * CGFloat(image.width)); context.beginPath(); context.move(to: CGPoint(x: stroke.points[0].x * CGFloat(image.width), y: stroke.points[0].y * CGFloat(image.height))); for point in stroke.points.dropFirst() { context.addLine(to: CGPoint(x: point.x * CGFloat(image.width), y: point.y * CGFloat(image.height))) }; context.strokePath() }
        guard let output = context.makeImage(), let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw ImagingError.renderFailed }; CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 0.97] as CFDictionary); guard CGImageDestinationFinalize(destination) else { throw ImagingError.renderFailed }
    }
}
enum ImagingError: LocalizedError { case invalidImage, renderFailed; var errorDescription: String? { String(localized: "The image could not be rendered.") } }
