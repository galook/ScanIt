import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit
import PencilKit

struct PageRenderer: @unchecked Sendable {
    static let shared = PageRenderer()
    private let context = CIContext(options: [.cacheIntermediates: false])

    func renderOffMain(page: ScanPage, documentDirectory: URL, maximumPixelSize: Int? = nil) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try render(page: page, documentDirectory: documentDirectory, maximumPixelSize: maximumPixelSize)
        }.value
    }

    func render(page: ScanPage, documentDirectory: URL, maximumPixelSize: Int? = nil) throws -> CGImage {
        let revision = page.revisions.first { $0.id == page.activeRevisionID } ?? page.revisions[0]
        guard let source = CGImageSourceCreateWithURL(revision.source.resolving(in: documentDirectory) as CFURL, nil) else { throw ImagingError.invalidImage }
        let image: CGImage?
        if let maximumPixelSize {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { throw ImagingError.invalidImage }
        var result = CIImage(cgImage: image)
        if let crop = revision.editState.crop {
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = result
            filter.topLeft = point(crop.topLeft, in: result.extent)
            filter.topRight = point(crop.topRight, in: result.extent)
            filter.bottomLeft = point(crop.bottomLeft, in: result.extent)
            filter.bottomRight = point(crop.bottomRight, in: result.extent)
            result = filter.outputImage ?? result
        }
        if revision.editState.adjustments.contrast != 1 || revision.editState.adjustments.brightness != 0 || revision.editState.adjustments.saturation != 1 { let filter = CIFilter.colorControls(); filter.inputImage = result; filter.contrast = Float(revision.editState.adjustments.contrast); filter.brightness = Float(revision.editState.adjustments.brightness); filter.saturation = Float(revision.editState.adjustments.saturation); result = filter.outputImage ?? result }
        switch revision.editState.filter {
        case .original: break
        case .auto:
            let filter = CIFilter.colorControls(); filter.inputImage = result; filter.contrast = 1.12; filter.saturation = 0.9; result = filter.outputImage ?? result
        case .color:
            let filter = CIFilter.colorControls(); filter.inputImage = result; filter.contrast = 1.04; filter.saturation = 1.08; result = filter.outputImage ?? result
        case .grayscale, .blackWhite:
            let filter = CIFilter.colorControls(); filter.inputImage = result; filter.saturation = 0; filter.contrast = revision.editState.filter == .blackWhite ? 1.8 : 1; result = filter.outputImage ?? result
        case .shadows:
            let filter = CIFilter.highlightShadowAdjust(); filter.inputImage = result; filter.shadowAmount = 1.1; filter.highlightAmount = 0.85; result = filter.outputImage ?? result
        }
        if revision.editState.rotation != 0 {
            result = result.transformed(by: CGAffineTransform(rotationAngle: revision.editState.rotation * .pi / 180))
            result = result.transformed(by: CGAffineTransform(translationX: -result.extent.minX, y: -result.extent.minY))
        }
        guard let output = context.createCGImage(result, from: result.extent) else { throw ImagingError.renderFailed }
        return try composite(revision.editState.annotations, over: output, directory: documentDirectory)
    }

    private func point(_ normalized: CGPoint, in extent: CGRect) -> CGPoint { CGPoint(x: normalized.x * extent.width, y: normalized.y * extent.height) }

    private func composite(_ annotations: [PageAnnotation], over image: CGImage, directory: URL) throws -> CGImage {
        guard !annotations.isEmpty else { return image }
        guard let output = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImagingError.renderFailed }
        let canvas = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        output.draw(image, in: canvas)
        for annotation in annotations {
            let assetURL = annotation.asset.resolving(in: directory)
            let mark: CGImage?
            if annotation.kind == .signature,
               let data = try? Data(contentsOf: assetURL),
               let drawing = try? PKDrawing(data: data),
               !drawing.bounds.isEmpty {
                let desiredWidth = CGFloat(image.width) * annotation.scale
                let rasterScale = max(1, desiredWidth / max(1, drawing.bounds.width))
                mark = drawing.image(from: drawing.bounds, scale: rasterScale).cgImage
            } else if let source = CGImageSourceCreateWithURL(assetURL as CFURL, nil) {
                mark = CGImageSourceCreateImageAtIndex(source, 0, nil)
            } else {
                mark = nil
            }
            guard let mark else { continue }
            let desiredWidth = CGFloat(image.width) * annotation.scale
            let aspect = CGFloat(mark.height) / CGFloat(mark.width)
            let rect = CGRect(x: -desiredWidth / 2, y: -(desiredWidth * aspect) / 2, width: desiredWidth, height: desiredWidth * aspect)
            output.saveGState()
            // SwiftUI uses a top-left origin while this bitmap context uses a bottom-left origin.
            output.translateBy(x: annotation.center.x * canvas.width, y: (1 - annotation.center.y) * canvas.height)
            output.rotate(by: annotation.rotation)
            output.draw(mark, in: rect)
            output.restoreGState()
        }
        guard let result = output.makeImage() else { throw ImagingError.renderFailed }
        return result
    }
}
