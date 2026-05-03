//
//  UIImage+JPEGEncoding.swift
//  Spot
//
//  JPEG is opaque; encoding UIImage bitmaps that still carry an alpha format
//  triggers ImageIO warnings (e.g. writeImageAtIndex opaque + AlphaPremulLast)
//  and wastes space. Flatten to an opaque bitmap before jpegData.
//

import UIKit

extension UIImage {
    /// Draws into an opaque bitmap (sRGB) so JPEG encoding does not retain alpha.
    func spot_flattenedOpaqueForJPEG() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// JPEG data suitable for uploads and drafts; avoids alpha-channel overhead.
    func spot_jpegDataOpaque(compressionQuality: CGFloat) -> Data? {
        autoreleasepool {
            spot_flattenedOpaqueForJPEG().jpegData(compressionQuality: compressionQuality)
        }
    }
}
