import Foundation
import SwiftData

@Model
final class KnowledgeProgressRecord {
  @Attribute(.unique) var nodeID: UUID
  var levelRawValue: String
  var updatedAt: Date
  var sourceRawValue: String
  var elementKey: String?

  init(
    nodeID: UUID,
    level: KnowledgeLevel,
    updatedAt: Date = .now,
    source: KnowledgeProgressSource,
    elementKey: String? = nil
  ) {
    self.nodeID = nodeID
    self.levelRawValue = level.rawValue
    self.updatedAt = updatedAt
    self.sourceRawValue = source.rawValue
    self.elementKey = elementKey
  }

  var level: KnowledgeLevel {
    get { KnowledgeLevel(rawValue: levelRawValue) ?? .contact }
    set { levelRawValue = newValue.rawValue }
  }

  var source: KnowledgeProgressSource {
    get { KnowledgeProgressSource(rawValue: sourceRawValue) ?? .manual }
    set { sourceRawValue = newValue.rawValue }
  }
}
