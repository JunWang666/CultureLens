import CryptoKit
import Foundation

/// Stable filenames and request keys for caches without exposing full URLs or prompts on disk.
nonisolated enum CacheKeyDigest {
  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data)
      .map { String(format: "%02x", $0) }
      .joined()
  }

  static func sha256(_ value: String) -> String {
    sha256(Data(value.utf8))
  }
}
