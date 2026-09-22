import Foundation
import CoreGraphics

enum PDFCoordinateMapper {
    static func map(_ bounds: CGRect, through edits: PageEditState) -> CGRect? {
        var rect = bounds.standardized
        if let crop = edits.crop {
            let xs = [crop.topLeft.x, crop.topRight.x, crop.bottomLeft.x, crop.bottomRight.x]
            let ys = [crop.topLeft.y, crop.topRight.y, crop.bottomLeft.y, crop.bottomRight.y]
            let cropRect = CGRect(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 1) - (xs.min() ?? 0), height: (ys.max() ?? 1) - (ys.min() ?? 0))
            guard let intersection = rect.intersection(cropRect).nonEmpty else { return nil }
            rect = CGRect(x: (intersection.minX - cropRect.minX) / cropRect.width, y: (intersection.minY - cropRect.minY) / cropRect.height, width: intersection.width / cropRect.width, height: intersection.height / cropRect.height)
        }
        let rotation = ((Int(edits.rotation.rounded()) % 360) + 360) % 360
        switch rotation {
        case 90: return CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case 180: return CGRect(x: 1 - rect.maxX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        case 270: return CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
        default: return rect
        }
    }
}

private extension CGRect { var nonEmpty: CGRect? { isNull || isEmpty ? nil : self } }
