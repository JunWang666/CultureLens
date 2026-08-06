import Foundation

/// Parses / rewrites CultureLens inline citation URLs produced by ask prompts:
/// `https://culturelens.local/cite?citationMarker=9F742443&citationTitle=…&citationA11yValue=…&elementKey=…`
nonisolated enum CultureCiteURL {
  static let citationMarker = "9F742443"

  static func isCiteURL(_ url: URL) -> Bool {
    let host = url.host?.lowercased()
    return host == "culturelens.local"
      || url.absoluteString.lowercased().contains("culturelens.local/cite")
  }

  /// Resolves a knowledge-pack element key from a cite URL, falling back to
  /// name lookup in the loaded knowledge store.
  ///
  /// When `store` is provided, the key must exist in the pack; otherwise returns
  /// `nil` so callers do not navigate to a missing node.
  static func elementKey(from url: URL, store: KnowledgeStore? = .shared) -> String? {
    guard isCiteURL(url) else { return nil }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

    let resolved: String?
    if let key = firstValue(["elementKey", "citationKey"], in: items), !key.isEmpty {
      resolved = key
    } else if let marker = firstValue(["citationMarker"], in: items),
      marker != citationMarker,
      looksLikeElementKey(marker)
    {
      resolved = marker
    } else if let a11y = firstValue(["citationA11yValue"], in: items),
      let key = keyEmbedded(in: a11y)
    {
      resolved = key
    } else if let title = firstValue(["citationTitle"], in: items), !title.isEmpty {
      resolved = store?.elementKey(matchingName: title)
    } else {
      resolved = nil
    }

    return existingElementKey(resolved, store: store)
  }

  static func route(from url: URL, store: KnowledgeStore? = .shared) -> AppRoute? {
    elementKey(from: url, store: store).map { .knowledgeElement($0) }
  }

  /// Rewrites malformed model citations into the exact markdown form
  /// `SwiftStreamingMarkdown` expects, and strips leftover bare keys.
  ///
  /// Common model mistakes:
  /// - link text / `citationMarker` set to the element key instead of `9F742443`
  /// - unencoded spaces in `citationTitle` (breaks Markdown link parsing → raw URL leak)
  static func sanitizeInlineCitations(
    _ markdown: String,
    store: KnowledgeStore? = .shared
  ) -> String {
    var text = rewriteCiteMarkdownLinks(markdown, store: store)
    text = rewriteInlineCodeKeys(text, store: store)
    text = rewriteBareElementKeys(text, store: store)
    return text
  }

  // MARK: - Rewrite

  private static func rewriteCiteMarkdownLinks(
    _ markdown: String,
    store: KnowledgeStore?
  ) -> String {
    // Allow spaces inside the URL so broken model output still matches.
    let pattern = #/\[([^\]]*)\]\((https?:\/\/culturelens\.local\/cite\?[^)]*)\)/#
    var result = ""
    var cursor = markdown.startIndex

    for match in markdown.matches(of: pattern) {
      result += markdown[cursor..<match.range.lowerBound]
      let linkText = String(match.output.1)
      let destination = String(match.output.2)
      result += canonicalCiteMarkdown(
        linkText: linkText,
        destination: destination,
        store: store
      )
      cursor = match.range.upperBound
    }
    result += markdown[cursor...]
    return result
  }

  private static func rewriteInlineCodeKeys(
    _ markdown: String,
    store: KnowledgeStore?
  ) -> String {
    let pattern = #/`([a-z0-9]+(?:-[a-z0-9]+)+)`/#
    var result = ""
    var cursor = markdown.startIndex

    for match in markdown.matches(of: pattern) {
      result += markdown[cursor..<match.range.lowerBound]
      let key = String(match.output.1)
      if let cite = citationMarkdown(elementKey: key, titleHint: nil, store: store) {
        result += cite
      }
      cursor = match.range.upperBound
    }
    result += markdown[cursor...]
    return result
  }

  /// Turns leftover plain kebab-case keys into citation chips (or drops them
  /// if they appear inside an already-normalized cite URL).
  private static func rewriteBareElementKeys(
    _ markdown: String,
    store: KnowledgeStore?
  ) -> String {
    let pattern =
      #/(^|[\s，。；：、！？“”‘’（）()\[\]「」])([a-z0-9]+(?:-[a-z0-9]+){1,})(?=$|[\s，。；：、！？“”‘’（）()\[\]「」])/#
    var result = ""
    var cursor = markdown.startIndex

    for match in markdown.matches(of: pattern) {
      result += markdown[cursor..<match.range.lowerBound]
      result += String(match.output.1)
      let key = String(match.output.2)
      // Skip keys that are query values inside a cite URL we already wrote.
      let prefix = markdown[markdown.startIndex..<match.range.lowerBound]
      if prefix.hasSuffix("elementKey=") || prefix.hasSuffix("citationMarker=")
        || prefix.hasSuffix("citationKey=")
      {
        result += key
      } else if let cite = citationMarkdown(elementKey: key, titleHint: nil, store: store) {
        result += cite
      }
      cursor = match.range.upperBound
    }
    result += markdown[cursor...]
    return result
  }

  private static func canonicalCiteMarkdown(
    linkText: String,
    destination: String,
    store: KnowledgeStore?
  ) -> String {
    let params = parseQueryParameters(from: destination)
    var key =
      params["elementKey"]
      ?? params["citationKey"]
      ?? ""
    let markerParam = params["citationMarker"] ?? ""
    if key.isEmpty, looksLikeElementKey(markerParam), markerParam != citationMarker {
      key = markerParam
    }
    if key.isEmpty, looksLikeElementKey(linkText) {
      key = linkText
    }

    var title = (params["citationTitle"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty {
      title = displayName(for: key, store: store)
        ?? (looksLikeElementKey(linkText) ? "" : linkText)
    }
    if title.isEmpty {
      title = displayName(for: key, store: store) ?? (key.isEmpty ? String(localized: "来源") : key)
    }

    let resolvedKey = key.isEmpty ? linkText : key
    guard let existingKey = existingElementKey(resolvedKey, store: store) else {
      // Missing pack target: keep readable title, drop the navigable cite chip.
      return title
    }

    var a11y = (params["citationA11yValue"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if a11y.isEmpty || looksLikeElementKey(a11y) {
      a11y = title
    }

    return makeCiteMarkdown(
      elementKey: existingKey,
      title: title,
      a11y: a11y
    )
  }

  private static func citationMarkdown(
    elementKey: String,
    titleHint: String?,
    store: KnowledgeStore?
  ) -> String? {
    guard looksLikeElementKey(elementKey) else { return nil }
    guard let existingKey = existingElementKey(elementKey, store: store) else { return nil }
    let title =
      titleHint?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
      ?? displayName(for: existingKey, store: store)
      ?? existingKey
    return makeCiteMarkdown(elementKey: existingKey, title: title, a11y: title)
  }

  private static func makeCiteMarkdown(
    elementKey: String,
    title: String,
    a11y: String
  ) -> String {
    let encTitle = percentEncodeQueryValue(title)
    let encA11y = percentEncodeQueryValue(a11y)
    let encKey = percentEncodeQueryValue(elementKey)
    return
      "[\(citationMarker)](https://culturelens.local/cite?citationMarker=\(citationMarker)&citationTitle=\(encTitle)&citationA11yValue=\(encA11y)&elementKey=\(encKey))"
  }

  private static func displayName(for key: String, store: KnowledgeStore?) -> String? {
    guard !key.isEmpty else { return nil }
    return store?.element(key: key)?.name
  }

  /// When `store` is nil (unit tests), accept any non-empty key; otherwise require
  /// the element to exist in the loaded pack.
  private static func existingElementKey(
    _ key: String?,
    store: KnowledgeStore?
  ) -> String? {
    guard let key, !key.isEmpty else { return nil }
    guard let store else { return key }
    if store.element(key: key) != nil { return key }
    return nil
  }

  // MARK: - Helpers

  private static func parseQueryParameters(from destination: String) -> [String: String] {
    guard let question = destination.firstIndex(of: "?") else { return [:] }
    let query = destination[destination.index(after: question)...]
    var result: [String: String] = [:]
    for pair in query.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard let name = parts.first.map(String.init), !name.isEmpty else { continue }
      let rawValue = parts.count > 1 ? String(parts[1]) : ""
      result[name] = rawValue.removingPercentEncoding ?? rawValue
    }
    return result
  }

  private static func percentEncodeQueryValue(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

  private static func looksLikeElementKey(_ value: String) -> Bool {
    value.wholeMatch(of: #/[a-z0-9]+(?:-[a-z0-9]+)+/#) != nil
  }

  private static func firstValue(_ names: [String], in items: [URLQueryItem]) -> String? {
    for name in names {
      if let value = items.first(where: { $0.name == name })?.value?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      {
        return value
      }
    }
    return nil
  }

  /// Extracts `key` from `name（key）` / `name(key)`.
  private static func keyEmbedded(in text: String) -> String? {
    if let match = text.firstMatch(of: #/[（(]([^）)\s]+)[）)]\s*$/#) {
      let key = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
      return key.isEmpty ? nil : key
    }
    return nil
  }
}

private extension String {
  nonisolated var nonEmpty: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
