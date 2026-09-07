//
//  ColorAnalyzer.swift
//  voila
//
//  Extracts the dominant *clothing* colors from a photo on-device so Apple
//  Intelligence has real color information to comment on. Vision's classifier
//  only returns generic labels ("jacket", "denim") with no color, so this fills
//  that gap: it isolates the person from the background, samples their pixels,
//  names each color, and drops skin tones to leave the outfit's colors.
//

import CoreGraphics
import CoreImage
import ImageIO
import Vision

struct ColorAnalyzer {

    /// The dominant clothing colors in the photo, most prominent first (approximate).
    func dominantColors(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        let context = CIContext(options: nil)

        // Render an upright copy so it aligns with the person-segmentation mask.
        let upright = CIImage(cgImage: cgImage).oriented(orientation)
        guard let uprightImage = context.createCGImage(upright, from: upright.extent) else {
            return []
        }

        let mask = await personMask(for: uprightImage)
        return palette(for: uprightImage, mask: mask)
    }

    // MARK: - Person mask

    /// A grayscale mask (person = bright) so background pixels can be ignored, or `nil` if none found.
    private func personMask(for image: CGImage) async -> CGImage? {
        let request = GeneratePersonSegmentationRequest()
        guard let observation = try? await request.perform(on: image, orientation: .up) else {
            return nil
        }
        return try? observation.cgImage
    }

    // MARK: - Color tallying

    private func palette(for image: CGImage, mask: CGImage?) -> [String] {
        let n = 80
        guard let colorPixels = renderRGBA(image, size: n) else { return [] }
        let maskPixels = mask.flatMap { renderGray($0, size: n) }

        var tally: [String: Int] = [:]
        var counted = 0

        for i in 0..<(n * n) {
            // Skip near-transparent pixels.
            if colorPixels[i * 4 + 3] < 8 { continue }
            // Skip pixels outside the person (background), when a mask is available.
            if let maskPixels, maskPixels[i] < 128 { continue }

            let reference = nearestReference(
                r: Double(colorPixels[i * 4 + 0]),
                g: Double(colorPixels[i * 4 + 1]),
                b: Double(colorPixels[i * 4 + 2])
            )
            // Skin isn't part of the outfit — leave it out of the clothing palette.
            if reference.isSkin { continue }

            counted += 1
            tally[reference.name, default: 0] += 1
        }

        guard counted > 0 else { return [] }

        // Keep colors that make up a meaningful share of the outfit.
        return tally
            .filter { Double($0.value) / Double(counted) >= 0.08 }
            .sorted { $0.value > $1.value }
            .prefix(4)
            .map(\.key)
    }

    // MARK: - Bitmap rendering

    private func renderRGBA(_ image: CGImage, size n: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(
            data: &data,
            width: n, height: n,
            bitsPerComponent: 8,
            bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        return data
    }

    private func renderGray(_ image: CGImage, size n: Int) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: n * n)
        guard let ctx = CGContext(
            data: &data,
            width: n, height: n,
            bitsPerComponent: 8,
            bytesPerRow: n,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
        return data
    }

    // MARK: - Color naming

    private func nearestReference(r: Double, g: Double, b: Double) -> ReferenceColor {
        var best = Self.references[0]
        var bestDistance = Double.greatestFiniteMagnitude
        for reference in Self.references {
            let dr = reference.r - r, dg = reference.g - g, db = reference.b - b
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = reference
            }
        }
        return best
    }

    private struct ReferenceColor {
        let name: String
        let r: Double, g: Double, b: Double
        var isSkin = false
    }

    /// A curated palette of named colors plus a few skin tones (excluded from results).
    private static let references: [ReferenceColor] = [
        ReferenceColor(name: "black", r: 20, g: 20, b: 20),
        ReferenceColor(name: "charcoal", r: 60, g: 60, b: 65),
        ReferenceColor(name: "gray", r: 130, g: 130, b: 135),
        ReferenceColor(name: "light gray", r: 195, g: 195, b: 198),
        ReferenceColor(name: "white", r: 245, g: 245, b: 242),
        ReferenceColor(name: "cream", r: 240, g: 232, b: 210),
        ReferenceColor(name: "beige", r: 214, g: 196, b: 164),
        ReferenceColor(name: "tan", r: 200, g: 170, b: 120),
        ReferenceColor(name: "brown", r: 105, g: 72, b: 45),
        ReferenceColor(name: "khaki", r: 170, g: 158, b: 120),
        ReferenceColor(name: "olive", r: 110, g: 105, b: 60),
        ReferenceColor(name: "yellow", r: 225, g: 205, b: 80),
        ReferenceColor(name: "orange", r: 225, g: 130, b: 55),
        ReferenceColor(name: "red", r: 190, g: 45, b: 45),
        ReferenceColor(name: "maroon", r: 110, g: 35, b: 45),
        ReferenceColor(name: "pink", r: 232, g: 165, b: 185),
        ReferenceColor(name: "purple", r: 120, g: 65, b: 150),
        ReferenceColor(name: "navy", r: 30, g: 40, b: 80),
        ReferenceColor(name: "blue", r: 45, g: 85, b: 180),
        ReferenceColor(name: "light blue", r: 150, g: 190, b: 230),
        ReferenceColor(name: "denim blue", r: 75, g: 105, b: 145),
        ReferenceColor(name: "teal", r: 30, g: 125, b: 125),
        ReferenceColor(name: "green", r: 55, g: 130, b: 70),
        // Skin tones — detected so they can be excluded from the outfit palette.
        ReferenceColor(name: "skin", r: 255, g: 224, b: 196, isSkin: true),
        ReferenceColor(name: "skin", r: 241, g: 194, b: 150, isSkin: true),
        ReferenceColor(name: "skin", r: 224, g: 172, b: 105, isSkin: true),
        ReferenceColor(name: "skin", r: 198, g: 134, b: 66, isSkin: true),
        ReferenceColor(name: "skin", r: 141, g: 85, b: 50, isSkin: true),
    ]
}
