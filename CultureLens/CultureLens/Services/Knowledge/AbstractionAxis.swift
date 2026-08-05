import Foundation

/// Direction of a typed relation along the abstraction axis
/// (design 0006, 关系抽象方向表). `up` means the relation source is the more
/// specific end and the target the more abstract one; `prerequisite` lives on
/// its own axis, independent of abstraction.
nonisolated enum AbstractionDirection: String, Hashable, Sendable {
  case up
  case down
  case lateral
  case prerequisite
}

extension RelationKind {
  /// Static direction classification; does not change the pack schema.
  nonisolated var abstractionDirection: AbstractionDirection {
    switch self {
    case .locatedIn, .expresses, .influencedBy, .governedBy, .explains, .emergedIn:
      .up
    case .composedOf:
      .down
    case .similarTo, .usedFor, .symbolizes, .madeWith:
      .lateral
    case .prerequisiteFor:
      .prerequisite
    }
  }

  /// `产生于` is semantically upward, but the pack contains audited reversed
  /// edges (design 0006 已确认的数据缺陷), so the default upward traversal
  /// excludes it until the data audit lands.
  nonisolated var isAuditedUpward: Bool {
    switch self {
    case .locatedIn, .expresses, .influencedBy, .governedBy, .explains:
      true
    default:
      false
    }
  }

  /// Ordering priority when several ancestors share a level; the lowest value
  /// becomes the ladder backbone (位于 > 体现 > 受到影响 > 解释).
  nonisolated var abstractionBackbonePriority: Int {
    switch self {
    case .locatedIn: 0
    case .expresses: 1
    case .influencedBy: 2
    case .explains: 3
    case .governedBy: 4
    case .emergedIn: 5
    default: 6
    }
  }
}

/// A typed directed edge endpoint used by the abstraction-axis traversal.
/// `key` is always the *other* endpoint relative to the queried node.
nonisolated struct DirectedRelationEdge: Hashable, Sendable {
  let key: String
  let kind: RelationKind?
  let explanation: String?
}

/// One ancestor on the abstraction ladder: the element plus the typed edge
/// that led to it from the previous level.
nonisolated struct AbstractionAncestor: Hashable, Sendable {
  let key: String
  let name: String
  let kind: RelationKind?
  let explanation: String?
}

/// Ancestors that share a BFS depth from the ladder root.
nonisolated struct AbstractionLevel: Hashable, Sendable {
  let level: Int
  let elements: [AbstractionAncestor]
}

/// One missing prerequisite in dependency order (nearest first), carrying a
/// plain-text excerpt for the explanation prompt.
nonisolated struct MissingPrerequisite: Hashable, Sendable {
  let key: String
  let name: String
  let excerpt: String
}
