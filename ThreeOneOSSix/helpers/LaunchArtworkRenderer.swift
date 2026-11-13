import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Pure rendering helpers for launch-artwork replacement. A user photo is
/// aspect-fill rendered at each existing snapshot's pixel dimensions and
/// written as PNG (SpringBoard accepts same-name PNG replacement; the KTX
/// originals are only read for their dimensions).
enum LaunchArtworkRenderer {

    enum RenderError: Error, Equatable {
        case cannotCreateContext
        case cannotEncodePNG
    }

    /// Aspect-fill frame for `source` inside a `target`-sized viewport.
    /// Pure function, exercised directly by the harness.
    static func aspectFillRect(sourceWidth: Int, sourceHeight: Int,
                               targetWidth: Int, targetHeight: Int) -> CGRect {
        guard sourceWidth > 0, sourceHeight > 0, targetWidth > 0, targetHeight > 0 else {
            return CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        }
        let scale = max(CGFloat(targetWidth) / CGFloat(sourceWidth),
                        CGFloat(targetHeight) / CGFloat(sourceHeight))
        let width = CGFloat(sourceWidth) * scale
        let height = CGFloat(sourceHeight) * scale
        return CGRect(x: (CGFloat(targetWidth) - width) / 2,
                      y: (CGFloat(targetHeight) - height) / 2,
                      width: width, height: height)
    }

    /// Renders `source` aspect-fill into a `width x height` opaque image.
    static func render(_ source: CGImage, width: Int, height: Int) throws -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw RenderError.cannotCreateContext
        }
        // Black base so letterboxing (if rounding leaves hairlines) stays dark.
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let rect = aspectFillRect(sourceWidth: source.width, sourceHeight: source.height,
                                  targetWidth: width, targetHeight: height)
        context.interpolationQuality = .high
        context.draw(source, in: rect)
        guard let output = context.makeImage() else {
            throw RenderError.cannotCreateContext
        }
        return output
    }

    /// Encodes a CGImage as PNG bytes.
    static func pngData(_ image: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw RenderError.cannotEncodePNG
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), out.length > 0 else {
            throw RenderError.cannotEncodePNG
        }
        return out as Data
    }

    // MARK: - KTX dimension probe

    /// KTX 1.1: 12-byte identifier, then 8 UInt32 header fields before
    /// pixelWidth (offset 36) and pixelHeight (offset 40). Only trust the
    /// values when the magic matches and both dimensions are plausible.
    static func ktxDimensions(_ data: Data) -> (width: Int, height: Int)? {
        let magic = Data([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x31, 0x31, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.count >= 44, data.prefix(12) == magic else { return nil }
        func u32(at offset: Int) -> UInt32 {
            let bytes = data.subdata(in: offset..<(offset + 4))
            var value: UInt32 = 0
            _ = withUnsafeMutableBytes(of: &value) { bytes.copyBytes(to: $0) }
            return littleEndian(value)
        }
        let width = Int(u32(at: 36))
        let height = Int(u32(at: 40))
        guard width > 0, width <= 16_384, height > 0, height <= 16_384 else { return nil }
        return (width, height)
    }

    private static func littleEndian(_ value: UInt32) -> UInt32 {
        UInt32(littleEndian: value)
    }

    /// Dimensions of an existing snapshot file (PNG/JPEG via ImageIO, KTX via
    /// header probe). nil when the format is unreadable — caller skips it.
    static func dimensions(of data: Data) -> (width: Int, height: Int)? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = props[kCGImagePropertyPixelWidth] as? Int,
           let height = props[kCGImagePropertyPixelHeight] as? Int,
           width > 0, height > 0 {
            return (width, height)
        }
        return ktxDimensions(data)
    }
}
