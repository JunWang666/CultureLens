import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SampleScanImage {
    nonisolated static func jpegData() -> Data {
        let width = 1_200
        let height = 900
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Data()
        }

        context.setFillColor(
            CGColor(red: 0.08, green: 0.16, blue: 0.23, alpha: 1)
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(
            CGColor(red: 0.70, green: 0.42, blue: 0.25, alpha: 1)
        )
        for level in 0..<5 {
            let inset = CGFloat(level * 75)
            context.fill(
                CGRect(
                    x: 150 + inset,
                    y: 180 + CGFloat(level * 70),
                    width: 900 - inset * 2,
                    height: 58
                )
            )
        }

        context.setStrokeColor(
            CGColor(red: 0.74, green: 0.60, blue: 0.34, alpha: 1)
        )
        context.setLineWidth(10)
        context.stroke(CGRect(x: 110, y: 120, width: 980, height: 650))

        guard let image = context.makeImage() else { return Data() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return Data()
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return Data(bytes: output.bytes, count: output.length)
    }
}
