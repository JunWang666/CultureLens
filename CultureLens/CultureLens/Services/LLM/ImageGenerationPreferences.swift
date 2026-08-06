import Foundation
import SwiftUI

/// Opt-in Volcengine Seedream cover generation for cultural-review sharing.
/// Off by default — share cards prefer knowledge-pack introduction photos and
/// poster-style `ObjectArtwork` fallbacks unless the user enables this.
@Observable
@MainActor
final class ImageGenerationPreferenceStore {
  nonisolated static let enabledKey = "culturelens.imageGeneration.enabled"

  var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
    }
  }

  init(isEnabled: Bool = ImageGenerationPreferenceStore.loadEnabled()) {
    self.isEnabled = isEnabled
  }

  nonisolated static func loadEnabled() -> Bool {
    UserDefaults.standard.bool(forKey: enabledKey)
  }

  nonisolated static func currentEnabled() -> Bool {
    loadEnabled()
  }
}
