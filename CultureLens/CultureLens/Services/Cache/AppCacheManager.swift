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

    do {
      try await TTSAudioCache.shared.clear()
    } catch {
      firstError = firstError ?? error
    }

    do {
      try await DidYouKnowQuizService.shared.clear()
    } catch {
      firstError = firstError ?? error
    }

    do {
      try await VisitTripShareCopyService.shared.clear()
    } catch {
      firstError = firstError ?? error
    }

    await KnowledgeTranslationService.shared.clearCache()

    if let firstError {
      throw firstError
    }
  }

  /// Sum of remote-image, TTS audio, quiz, share-copy, and translation caches that `clearAll` removes.
  static func usageBytes() async -> Int64 {
    let images = await RemoteImageCache.shared.diskUsageBytes()
    let tts = await TTSAudioCache.shared.diskUsageBytes()
    let quizzes = await DidYouKnowQuizService.shared.diskUsageBytes()
    let shareCopy = await VisitTripShareCopyService.shared.diskUsageBytes()
    let translations = await KnowledgeTranslationService.shared.diskUsageBytes()
    return images + tts + quizzes + shareCopy + translations
  }

  static func formattedUsage(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}
