import Foundation

/// One persisted cultural Q&A thread (general or object-scoped).
nonisolated struct ChatConversationRecord: Codable, Hashable, Sendable, Identifiable {
  var id: UUID { conversationID }

  var conversationID: UUID
  var createdAt: Date
  var updatedAt: Date
  /// Derived from the first user message (or a fixed fallback).
  var title: String
  /// `nil` = general home chat; otherwise object-scoped follow-up.
  var objectID: UUID?
  var objectName: String?
  var messages: [PersistedChatMessage]

  init(
    conversationID: UUID = UUID(),
    createdAt: Date = .now,
    updatedAt: Date = .now,
    title: String,
    objectID: UUID? = nil,
    objectName: String? = nil,
    messages: [PersistedChatMessage] = []
  ) {
    self.conversationID = conversationID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.title = title
    self.objectID = objectID
    self.objectName = objectName
    self.messages = messages
  }

  var previewText: String {
    let lastUser = messages.last(where: { $0.role == .user })
    if let text = lastUser?.text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
      return text
    }
    if lastUser?.imageRelativePath != nil {
      return String(localized: "（附图片）")
    }
    return title
  }
}

nonisolated struct PersistedChatMessage: Codable, Hashable, Sendable, Identifiable {
  enum Role: String, Codable, Sendable {
    case user
    case assistant
  }

  let id: UUID
  let role: Role
  var text: String
  var imageRelativePath: String?
  var citations: [PersistedKnowledgeCitation]
  let createdAt: Date

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    imageRelativePath: String? = nil,
    citations: [PersistedKnowledgeCitation] = [],
    createdAt: Date = .now
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.imageRelativePath = imageRelativePath
    self.citations = citations
    self.createdAt = createdAt
  }

  enum CodingKeys: String, CodingKey {
    case id
    case role
    case text
    case imageRelativePath
    case citations
    case createdAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    role = try container.decode(Role.self, forKey: .role)
    text = try container.decode(String.self, forKey: .text)
    imageRelativePath = try container.decodeIfPresent(String.self, forKey: .imageRelativePath)
    // Older rows predate citations — default to empty rather than failing decode.
    citations = try container.decodeIfPresent([PersistedKnowledgeCitation].self, forKey: .citations) ?? []
    createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
  }
}

nonisolated struct PersistedKnowledgeCitation: Codable, Hashable, Sendable {
  let key: String
  let name: String
  let fragment: String

  enum CodingKeys: String, CodingKey {
    case key, name, fragment
  }

  init(key: String, name: String, fragment: String) {
    self.key = Self.normalizedKey(key)
    self.name = name
    self.fragment = fragment
  }

  init(_ citation: KnowledgeCitation) {
    self.key = Self.normalizedKey(citation.key)
    self.name = citation.name
    self.fragment = citation.fragment
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    key = Self.normalizedKey(try container.decode(String.self, forKey: .key))
    name = try container.decode(String.self, forKey: .name)
    fragment = try container.decode(String.self, forKey: .fragment)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(key, forKey: .key)
    try container.encode(name, forKey: .name)
    try container.encode(fragment, forKey: .fragment)
  }

  var asKnowledgeCitation: KnowledgeCitation {
    KnowledgeCitation(key: key, name: name, fragment: fragment)
  }

  /// Legacy kebab slugs become UUIDv5 strings so display/navigation can use IDs.
  private static func normalizedKey(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }
    if UUID(uuidString: trimmed) != nil { return trimmed }
    if DeterministicID.looksLikeLegacyElementSlug(trimmed) {
      return DeterministicID.culturalElement(trimmed).uuidString
    }
    return trimmed
  }
}
