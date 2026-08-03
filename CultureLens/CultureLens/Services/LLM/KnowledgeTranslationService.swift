import Foundation

/// On-demand translation of knowledge-pack text via `dynamic/chat` when a
/// locale overlay is missing. Results are cached in memory and UserDefaults.
nonisolated actor KnowledgeTranslationService {
  static let shared = KnowledgeTranslationService()

  private let gatewayClient: LLMGatewayClient?
  private var memoryCache: [String: CachedTranslation] = [:]
  private let defaultsKey = "culturelens.knowledgeTranslationCache.v1"

  struct CachedTranslation: Codable, Sendable {
    let name: String
    let plainText: String
    let language: String
  }

  init(gatewayClient: LLMGatewayClient? = try? LLMGatewayClient()) {
    self.gatewayClient = gatewayClient
    if let data = UserDefaults.standard.data(forKey: defaultsKey),
      let decoded = try? JSONDecoder().decode([String: CachedTranslation].self, from: data)
    {
      memoryCache = decoded
    }
  }

  /// Resolves display text for an element: pack overlay → cache → live translate.
  func localizedElement(
    key: String,
    sourceName: String,
    sourcePlainText: String,
    language: AppLanguage,
    localization: KnowledgeLocalization
  ) async -> LocalizedKnowledgeText {
    if let overlay = localization.elementText(key: key, language: language),
      !overlay.isSourceFallback || language.isKnowledgeSource
    {
      return overlay
    }

    if language.isKnowledgeSource {
      return LocalizedKnowledgeText(
        name: sourceName,
        introduction: localization.elementText(key: key, language: .knowledgeSource)?.introduction,
        isSourceFallback: false,
        language: .knowledgeSource
      )
    }

    let cacheKey = "element:\(language.rawValue):\(key)"
    if let cached = memoryCache[cacheKey] {
      return LocalizedKnowledgeText(
        name: cached.name,
        introduction: RichTextDocument.plain(cached.plainText),
        isSourceFallback: false,
        language: language
      )
    }

    guard let gatewayClient else {
      return LocalizedKnowledgeText(
        name: sourceName,
        introduction: localization.elementText(key: key, language: .knowledgeSource)?.introduction,
        isSourceFallback: true,
        language: .knowledgeSource
      )
    }

    do {
      let translated = try await translate(
        client: gatewayClient,
        name: sourceName,
        plainText: sourcePlainText,
        language: language
      )
      memoryCache[cacheKey] = translated
      persistCache()
      return LocalizedKnowledgeText(
        name: translated.name,
        introduction: RichTextDocument.plain(translated.plainText),
        isSourceFallback: false,
        language: language
      )
    } catch {
      return LocalizedKnowledgeText(
        name: sourceName,
        introduction: localization.elementText(key: key, language: .knowledgeSource)?.introduction,
        isSourceFallback: true,
        language: .knowledgeSource
      )
    }
  }

  func localizedName(
    cacheNamespace: String,
    key: String,
    sourceName: String,
    language: AppLanguage
  ) async -> String {
    if language.isKnowledgeSource { return sourceName }
    let cacheKey = "\(cacheNamespace):\(language.rawValue):\(key)"
    if let cached = memoryCache[cacheKey] {
      return cached.name
    }
    guard let gatewayClient else { return sourceName }
    do {
      let translated = try await translate(
        client: gatewayClient,
        name: sourceName,
        plainText: "",
        language: language
      )
      memoryCache[cacheKey] = translated
      persistCache()
      return translated.name
    } catch {
      return sourceName
    }
  }

  private func translate(
    client: LLMGatewayClient,
    name: String,
    plainText: String,
    language: AppLanguage
  ) async throws -> CachedTranslation {
    let system = """
      You are a precise translator for a cultural heritage knowledge base.
      Translate the given Chinese cultural text into \(language.promptLanguageName).
      Preserve proper nouns that are conventionally kept in Chinese romanization when appropriate.
      Return ONLY a JSON object with keys "name" and "text". No markdown fences.
      If the input text is empty, return "text" as an empty string.
      """
    let user = """
      name: \(name)
      text: \(plainText)
      """
    let (content, _) = try await client.completeText(systemPrompt: system, userText: user)
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let jsonSlice = Self.extractJSONObject(from: trimmed) ?? trimmed
    guard let data = jsonSlice.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let translatedName = object["name"] as? String
    else {
      // Soft fallback: treat whole reply as plain translation of the name.
      return CachedTranslation(
        name: trimmed.isEmpty ? name : trimmed,
        plainText: plainText,
        language: language.rawValue
      )
    }
    let translatedText = (object["text"] as? String) ?? plainText
    return CachedTranslation(
      name: translatedName.trimmingCharacters(in: .whitespacesAndNewlines),
      plainText: translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
      language: language.rawValue
    )
  }

  private func persistCache() {
    guard let data = try? JSONEncoder().encode(memoryCache) else { return }
    UserDefaults.standard.set(data, forKey: defaultsKey)
  }

  private static func extractJSONObject(from text: String) -> String? {
    guard let start = text.firstIndex(of: "{"),
      let end = text.lastIndex(of: "}")
    else { return nil }
    return String(text[start...end])
  }
}

extension RichTextDocument {
  /// Minimal single-paragraph document used for translated plain text.
  static func plain(_ text: String) -> RichTextDocument {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return RichTextDocument(schemaVersion: 1, blocks: [])
    }
    return RichTextDocument(
      schemaVersion: 1,
      blocks: [
        Block(type: "paragraph", text: trimmed, url: nil, caption: nil)
      ]
    )
  }
}
