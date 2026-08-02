import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Data {
  nonisolated func ownedCopy() -> Data {
    withUnsafeBytes { bytes in
      Data(bytes)
    }
  }
}

enum ImagePreprocessorError: LocalizedError {
  case unreadableImage
  case encodingFailed

  var errorDescription: String? {
    switch self {
    case .unreadableImage:
      "无法读取所选图片。"
    case .encodingFailed:
      "无法准备识别图片。"
    }
  }
}

nonisolated struct NormalizedImageRegion: Codable, Hashable, Sendable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  nonisolated static let defaultFocus = NormalizedImageRegion(
    x: 0.15,
    y: 0.15,
    width: 0.70,
    height: 0.70
  )

  nonisolated func clamped(
    minimumSize: Double = 0.01
  ) -> NormalizedImageRegion {
    let minimum = min(max(minimumSize, 0), 1)
    let clampedWidth = min(max(width, minimum), 1)
    let clampedHeight = min(max(height, minimum), 1)
    return NormalizedImageRegion(
      x: min(max(x, 0), 1 - clampedWidth),
      y: min(max(y, 0), 1 - clampedHeight),
      width: clampedWidth,
      height: clampedHeight
    )
  }

  nonisolated func rect(in bounds: CGRect) -> CGRect {
    let region = clamped()
    return CGRect(
      x: bounds.minX + bounds.width * region.x,
      y: bounds.minY + bounds.height * region.y,
      width: bounds.width * region.width,
      height: bounds.height * region.height
    )
  }
}

enum ImagePreprocessor {
  nonisolated static let maximumPixelSize = 1_600
  nonisolated static let jpegQuality = 0.82

  nonisolated static func normalizedJPEG(from sourceData: Data) throws -> Data {
    guard
      let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
      )
    else {
      throw ImagePreprocessorError.unreadableImage
    }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw ImagePreprocessorError.encodingFailed
    }

    CGImageDestinationAddImage(
      destination,
      image,
      [
        kCGImageDestinationLossyCompressionQuality: jpegQuality
      ] as CFDictionary
    )

    guard CGImageDestinationFinalize(destination) else {
      throw ImagePreprocessorError.encodingFailed
    }

    return Data(bytes: output.bytes, count: output.length)
  }

  nonisolated static func annotatedJPEG(
    from normalizedJPEGData: Data,
    region: NormalizedImageRegion
  ) throws -> Data {
    guard
      let source = CGImageSourceCreateWithData(normalizedJPEGData as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      throw ImagePreprocessorError.unreadableImage
    }

    let pixelBounds = CGRect(
      x: 0,
      y: 0,
      width: image.width,
      height: image.height
    )
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
      )
    else {
      throw ImagePreprocessorError.encodingFailed
    }

    context.interpolationQuality = .high
    context.draw(image, in: pixelBounds)

    let focus = region.clamped(minimumSize: 0.05)
    let shortEdge = min(pixelBounds.width, pixelBounds.height)
    let outerLineWidth = max(8, shortEdge * 0.012)
    let innerLineWidth = max(5, shortEdge * 0.007)
    let inset = outerLineWidth / 2
    let focusRect = CGRect(
      x: pixelBounds.width * focus.x,
      y: pixelBounds.height * (1 - focus.y - focus.height),
      width: pixelBounds.width * focus.width,
      height: pixelBounds.height * focus.height
    )
    .insetBy(dx: inset, dy: inset)
    .intersection(pixelBounds.insetBy(dx: inset, dy: inset))

    guard
      let annotationColor = CGColor(
        colorSpace: colorSpace,
        components: [0.78, 0.396, 0.243, 1]
      )
    else {
      throw ImagePreprocessorError.encodingFailed
    }
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.96))
    context.setLineWidth(outerLineWidth)
    context.stroke(focusRect)
    context.setStrokeColor(annotationColor)
    context.setLineWidth(innerLineWidth)
    context.stroke(focusRect)

    guard let annotatedImage = context.makeImage() else {
      throw ImagePreprocessorError.encodingFailed
    }
    return try encodedJPEG(from: annotatedImage)
  }

  nonisolated static func pixelSize(of imageData: Data) throws -> CGSize {
    guard
      let source = CGImageSourceCreateWithData(imageData as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(
        source,
        0,
        nil
      ) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
      throw ImagePreprocessorError.unreadableImage
    }

    return CGSize(
      width: width.doubleValue,
      height: height.doubleValue
    )
  }

  private nonisolated static func encodedJPEG(from image: CGImage) throws -> Data {
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw ImagePreprocessorError.encodingFailed
    }

    CGImageDestinationAddImage(
      destination,
      image,
      [
        kCGImageDestinationLossyCompressionQuality: jpegQuality
      ] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      throw ImagePreprocessorError.encodingFailed
    }
    return Data(bytes: output.bytes, count: output.length)
  }
}
