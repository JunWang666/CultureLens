import Foundation
import Observation
import SwiftData

/// Persists cultural Q&A threads (general + object-scoped) via SwiftData.
@MainActor
@Observable
final class ChatHistoryStore {
  @ObservationIgnored private var modelContext: ModelContext?

  func configure(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  func conversations(objectID: UUID?) -> [ChatConversationRecord] {
    guard let modelContext else { return [] }
    let descriptor = FetchDescriptor<ChatConversationRecord>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    let all = (try? modelContext.fetch(descriptor)) ?? []
    return all.filter { record in
      if let objectID {
        return record.objectID == objectID
      }
      return record.objectID == nil
    }
  }

  func conversation(id: UUID) -> ChatConversationRecord? {
    guard let modelContext else { return nil }
    var descriptor = FetchDescriptor<ChatConversationRecord>(
      predicate: #Predicate { $0.conversationID == id }
    )
    descriptor.fetchLimit = 1
    return try? modelContext.fetch(descriptor).first
  }

  @discardableResult
  func upsert(
    conversationID: UUID,
    object: CultureObject?,
    messages: [PersistedChatMessage]
  ) -> ChatConversationRecord? {
    guard let modelContext else { return nil }
    let title = Self.makeTitle(from: messages, object: object)
    if let existing = conversation(id: conversationID) {
      existing.updatedAt = .now
      existing.title = title
      existing.messages = messages
      existing.objectID = object?.id
      existing.objectName = object?.canonicalName
      try? modelContext.save()
      return existing
    }

    let record = ChatConversationRecord(
      conversationID: conversationID,
      title: title,
      objectID: object?.id,
      objectName: object?.canonicalName,
      messagesData: (try? JSONEncoder().encode(messages)) ?? Data()
    )
    modelContext.insert(record)
    try? modelContext.save()
    return record
  }

  func delete(_ record: ChatConversationRecord) {
    guard let modelContext else { return }
    let imagePaths = record.messages.compactMap(\.imageRelativePath)
    modelContext.delete(record)
    try? modelContext.save()
    Task {
      await ChatMediaStore.shared.deleteAll(relativePaths: imagePaths)
    }
  }

  func delete(id: UUID) {
    guard let record = conversation(id: id) else { return }
    delete(record)
  }

  static func makeTitle(from messages: [PersistedChatMessage], object: CultureObject?) -> String {
    if let firstUser = messages.first(where: { $0.role == .user }) {
      let trimmed = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return String(trimmed.prefix(36))
      }
      if firstUser.imageRelativePath != nil {
        return object.map { "关于\($0.canonicalName)的图片提问" } ?? "图片提问"
      }
    }
    return object?.canonicalName ?? "文化问答"
  }
}
