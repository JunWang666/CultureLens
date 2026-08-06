import Foundation

/// Per-request short ID session for LLM prompts.
///
/// Elements and attractions are numbered independently from `"1"` so the two
/// fields never collide. Short IDs are valid only for a single LLM call;
/// responses must be mapped back via `resolveElement` / `resolveAttraction`
/// before entering the rest of the app.
nonisolated struct LLMIDSession: Sendable {
  private(set) var elementShortToUUID: [String: UUID] = [:]
  private(set) var attractionShortToUUID: [String: UUID] = [:]
  private var elementUUIDToShort: [UUID: String] = [:]
  private var attractionUUIDToShort: [UUID: String] = [:]

  init() {}

  /// Registers elements in order and returns short IDs `"1"…"N"`.
  @discardableResult
  mutating func registerElements(_ ids: [UUID]) -> [String] {
    var shorts: [String] = []
    shorts.reserveCapacity(ids.count)
    for id in ids {
      if let existing = elementUUIDToShort[id] {
        shorts.append(existing)
        continue
      }
      let short = String(elementShortToUUID.count + 1)
      precondition(short.count <= 2, "LLMIDSession element short ID overflow")
      elementShortToUUID[short] = id
      elementUUIDToShort[id] = short
      shorts.append(short)
    }
    return shorts
  }

  /// Registers attractions in order and returns short IDs `"1"…"N"`.
  @discardableResult
  mutating func registerAttractions(_ ids: [UUID]) -> [String] {
    var shorts: [String] = []
    shorts.reserveCapacity(ids.count)
    for id in ids {
      if let existing = attractionUUIDToShort[id] {
        shorts.append(existing)
        continue
      }
      let short = String(attractionShortToUUID.count + 1)
      precondition(short.count <= 2, "LLMIDSession attraction short ID overflow")
      attractionShortToUUID[short] = id
      attractionUUIDToShort[id] = short
      shorts.append(short)
    }
    return shorts
  }

  func shortID(forElement uuid: UUID) -> String? {
    elementUUIDToShort[uuid]
  }

  func shortID(forAttraction uuid: UUID) -> String? {
    attractionUUIDToShort[uuid]
  }

  /// Resolves a model-returned short ID (or empty) to a pack element UUID.
  func resolveElement(_ shortOrEmpty: String) -> UUID? {
    let trimmed = shortOrEmpty.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let uuid = elementShortToUUID[trimmed] { return uuid }
    // Tolerant: accept a raw UUID string if the model echoed one.
    if let uuid = UUID(uuidString: trimmed), elementUUIDToShort[uuid] != nil {
      return uuid
    }
    return nil
  }

  /// Resolves a model-returned short ID (or empty) to a pack attraction UUID.
  func resolveAttraction(_ shortOrEmpty: String) -> UUID? {
    let trimmed = shortOrEmpty.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let uuid = attractionShortToUUID[trimmed] { return uuid }
    if let uuid = UUID(uuidString: trimmed), attractionUUIDToShort[uuid] != nil {
      return uuid
    }
    return nil
  }

  /// Rewrites registered short element IDs in model markdown (cite URLs +
  /// citation lists) to pack UUID strings so the rest of the app never sees
  /// per-request short IDs.
  func remapElementShortIDs(in markdown: String) -> String {
    guard !elementShortToUUID.isEmpty else { return markdown }
    var text = markdown
    // Longer short IDs first so `"10"` is not partially matched as `"1"`.
    // Also require a non-hex boundary after the short id so a UUID that
    // happens to start with the same digits (e.g. `elementKey=2AD75…`) is
    // not re-matched by short `"2"`.
    for (short, uuid) in elementShortToUUID.sorted(by: { $0.key.count > $1.key.count }) {
      let uuidString = uuid.uuidString
      text = replaceShortID(
        in: text,
        pattern: "elementKey=\(NSRegularExpression.escapedPattern(for: short))",
        replacement: "elementKey=\(uuidString)"
      )
      text = replaceShortID(
        in: text,
        pattern: "key: `\(NSRegularExpression.escapedPattern(for: short))`",
        replacement: "key: `\(uuidString)`"
      )
      text = replaceShortID(
        in: text,
        pattern: "key: \(NSRegularExpression.escapedPattern(for: short)),",
        replacement: "key: \(uuidString),"
      )
    }
    return text
  }

  /// Replaces `pattern` only when not followed by a hex digit (avoids eating
  /// into an already-written UUID string).
  private func replaceShortID(in text: String, pattern: String, replacement: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern + #"(?![0-9A-Fa-f])"#) else {
      return text
    }
    let range = NSRange(text.startIndex..., in: text)
    return regex.stringByReplacingMatches(
      in: text,
      range: range,
      withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
    )
  }
}
