import Foundation

/// View-facing snapshot of the shipped remote-image ODR pack.
nonisolated struct ImagePackResource: Identifiable, Sendable, Equatable {
  enum Delivery: Sendable, Equatable {
    case onDemand
  }

  enum Availability: Sendable, Equatable {
    case available
    case notDownloaded
    case unavailable
  }

  var id: String { ImagePackLoader.odrTag }

  let delivery: Delivery
  let availability: Availability
  let imageCount: Int
}

/// Maps public R2 image URLs onto files inside `Resources/images/`.
enum ImagePackPathMapping {
  static let host = "culturelens.goudaijun.top"
  static let pathPrefix = "/images/"

  /// Returns `(subdirectory, resourceName, ext)` for a hosted knowledge image URL.
  static func resourceComponents(for url: URL) -> (subdirectory: String, name: String, ext: String)? {
    guard let host = url.host?.lowercased(),
      host == Self.host || host.hasSuffix(".\(Self.host)")
    else { return nil }

    var path = url.path
    if path.hasPrefix(pathPrefix) {
      path = String(path.dropFirst(pathPrefix.count))
    } else if path.hasPrefix("images/") {
      path = String(path.dropFirst("images/".count))
    } else {
      return nil
    }

    let parts = path.split(separator: "/").map(String.init)
    guard parts.count >= 2 else { return nil }
    let filename = parts.last!
    let subdirectory = parts.dropLast().joined(separator: "/")
    guard let dot = filename.lastIndex(of: "."), dot > filename.startIndex else { return nil }
    let name = String(filename[..<dot])
    let ext = String(filename[filename.index(after: dot)...])
    guard !name.isEmpty, !ext.isEmpty, !subdirectory.isEmpty else { return nil }
    return (subdirectory, name, ext)
  }
}
