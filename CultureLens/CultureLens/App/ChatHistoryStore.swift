import Foundation
import Observation

/// Persists cultural Q&A threads (general + object-scoped) as JSON on disk.
///
/// Chat history intentionally does **not** use SwiftData: mixing
/// `ChatConversationRecord` into the shared history store caused uncatchable
/// `SIGABRT` on both `fetch` and `save` after the model was added.
@MainActor
@Observable
final class ChatHistoryStore {
  private var records: [ChatConversationRecord] = []
  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let encoder: JSONEncoder
  @ObservationIgnored private let decoder: JSONDecoder

  init(fileManager: FileManager = .default) {
    let appSupport =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ))
      ?? fileManager.temporaryDirectory
    let directory = appSupport
      .appending(path: "CultureLens", directoryHint: .isDirectory)
      .appending(path: "ChatHistory", directoryHint: .isDirectory)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    fileURL = directory.appending(path: "conversations.json")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.decoder = decoder

    records = Self.loadRecords(from: fileURL, decoder: decoder)
  }

  func conversations(objectID: UUID?) -> [ChatConversationRecord] {
    records
      .filter { record in
        if let objectID {
          return record.objectID == objectID
        }
        return record.objectID == nil
      }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  func conversation(id: UUID) -> ChatConversationRecord? {
    records.first { $0.conversationID == id }
  }

  @discardableResult
  func upsert(
    conversationID: UUID,
    object: CultureObject?,
    messages: [PersistedChatMessage]
  ) throws -> ChatConversationRecord {
    let title = Self.makeTitle(from: messages, object: object)
    let record: ChatConversationRecord
    if let index = records.firstIndex(where: { $0.conversationID == conversationID }) {
      var updated = records[index]
      updated.updatedAt = .now
      updated.title = title
      updated.messages = messages
      updated.objectID = object?.id
      updated.objectName = object?.canonicalName
      records[index] = updated
      record = updated
    } else {
      record = ChatConversationRecord(
        conversationID: conversationID,
        title: title,
        objectID: object?.id,
        objectName: object?.canonicalName,
        messages: messages
      )
      records.append(record)
    }
    try persist()
    return record
  }

  func delete(_ record: ChatConversationRecord) {
    let imagePaths = record.messages.compactMap(\.imageRelativePath)
    records.removeAll { $0.conversationID == record.conversationID }
    try? persist()
    Task {
      await ChatMediaStore.shared.deleteAll(relativePaths: imagePaths)
    }
  }

  func delete(id: UUID) {
    guard let record = conversation(id: id) else { return }
    delete(record)
  }

  nonisolated static func makeTitle(from messages: [PersistedChatMessage], object: CultureObject?) -> String {
    if let firstUser = messages.first(where: { $0.role == .user }) {
      let trimmed = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty {
        return String(trimmed.prefix(36))
      }
      if firstUser.imageRelativePath != nil {
        return object.map { String(localized: "关于\($0.canonicalName)的图片提问") }
          ?? String(localized: "图片提问")
      }
    }
    return object?.canonicalName ?? String(localized: "文化问答")
  }

  private func persist() throws {
    do {
      let data = try encoder.encode(records)
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      throw ChatHistoryStoreError.saveFailed(error)
    }
  }

  private static func loadRecords(from url: URL, decoder: JSONDecoder) -> [ChatConversationRecord] {
    guard
      FileManager.default.fileExists(atPath: url.path),
      let data = try? Data(contentsOf: url),
      !data.isEmpty
    else { return [] }
    return (try? decoder.decode([ChatConversationRecord].self, from: data)) ?? []
  }
}

enum ChatHistoryStoreError: LocalizedError {
  case saveFailed(Error)

  var errorDescription: String? {
    switch self {
    case .saveFailed(let error):
      String(localized: "对话写入失败：\(error.localizedDescription)")
    }
  }
}
