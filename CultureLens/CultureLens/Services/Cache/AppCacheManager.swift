import Foundation

/// Clears only reproducible network caches. Persisted explanations, user history,
/// saved chat media, imported tracks, knowledge progress, and knowledge packs remain intact.
nonisolated enum AppCacheManager {
  static func clearAll() async throws {
    var firstError: Error?

    do {
      try await RemoteImageCache.shared.clear()
    } catch {
      firstError = error
    }

    await KnowledgeTranslationService.shared.clearCache()

    if let firstError {
      throw firstError
    }
  }
}
