import CoreGraphics
import Foundation

/// Metadata retained for joined nodes that are not present in the active
/// knowledge pack (for example an unresolved scan or old pack version).
nonisolated struct UserKnowledgeGraphSeed: Hashable {
  let id: UUID
  let name: String
  let summary: String

  init(id: UUID, name: String, summary: String) {
    self.id = id
    self.name = name
    self.summary = summary
  }
}

nonisolated struct UserKnowledgeGraphNode: Identifiable, Hashable {
  let id: UUID
  let elementKey: String?
  let name: String
  let summary: String
  let kind: ConceptKind
  let hop: Int
  let isJoined: Bool
}

nonisolated struct UserKnowledgeGraphEdge: Identifiable, Hashable {
  let id: UUID
  let sourceID: UUID
  let targetID: UUID
  /// Pack relation type; nil for untyped legacy edges.
  let kind: RelationKind?
  /// Human-readable edge gloss from the pack, when present.
  let explanation: String?

  init(
    id: UUID,
    sourceID: UUID,
    targetID: UUID,
    kind: RelationKind? = nil,
    explanation: String? = nil
  ) {
    self.id = id
    self.sourceID = sourceID
    self.targetID = targetID
    self.kind = kind
    self.explanation = explanation
  }
}

nonisolated struct UserKnowledgeGraphSnapshot: Hashable {
  let centerID: UUID?
  let nodes: [UserKnowledgeGraphNode]
  let edges: [UserKnowledgeGraphEdge]
  let maximumDepth: Int
  let isExpansionTruncated: Bool

  var joinedCount: Int {
    nodes.lazy.filter(\.isJoined).count
  }
}

/// Shared presentation rules for knowledge-pack elements. Recognition results
/// and the global graph use the same classification and text mapping.
nonisolated enum CulturalElementPresentation {
  /// Maps an optional pack `conceptKind` string to `ConceptKind`.
  /// Unknown or missing values fall back to `.foundation` for older packs.
  static func conceptKind(_ raw: String?) -> ConceptKind {
    guard let raw, let kind = ConceptKind(rawValue: raw) else {
      return .foundation
    }
    return kind
  }
}

/// A deterministic radial shortest-hop layout backed by the shared
/// `RadialGraphLayout` kernel (barycenter ordering + abstraction direction
/// bias), so the Graph tab renders with the same quality as the object graph.
nonisolated struct UserKnowledgeGraphLayout {
  static let nodeSize = CGSize(width: 146, height: 86)

  let positions: [UUID: CGPoint]
  let size: CGSize

  init(snapshot: UserKnowledgeGraphSnapshot) {
    guard let centerID = snapshot.centerID, !snapshot.nodes.isEmpty else {
      positions = [:]
      size = .zero
      return
    }

    let outerJoinedHop = snapshot.maximumDepth + 1
    let nodes = snapshot.nodes
      .filter { $0.id != centerID }
      .map {
        RadialGraphLayout.Node(
          id: $0.id,
          ring: min(max($0.hop, 1), outerJoinedHop),
          name: $0.name
        )
      }

    // Direction bias: infer each node's semantic direction from the typed
    // edge connecting it to the lowest-hop neighbor it touches.
    let hopByID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0.hop) })
    var directionOf: [UUID: AbstractionDirection] = [:]
    for node in snapshot.nodes where node.id != centerID {
      let nodeHop = hopByID[node.id] ?? 0
      let candidates = snapshot.edges
        .filter { edge in
          guard edge.kind != nil else { return false }
          let otherID: UUID
          if edge.sourceID == node.id {
            otherID = edge.targetID
          } else if edge.targetID == node.id {
            otherID = edge.sourceID
          } else {
            return false
          }
          return (hopByID[otherID] ?? .max) < nodeHop
        }
        .sorted { ($0.id.uuidString) < ($1.id.uuidString) }
      guard let edge = candidates.first, let kind = edge.kind else { continue }
      let direction = kind.abstractionDirection
      if edge.sourceID == node.id {
        // node → parent: invert the axis.
        switch direction {
        case .up: directionOf[node.id] = .down
        case .down: directionOf[node.id] = .up
        default: directionOf[node.id] = direction
        }
      } else {
        directionOf[node.id] = direction
      }
    }

    let layout = RadialGraphLayout(
      centerID: centerID,
      nodes: nodes,
      edges: snapshot.edges.map { ($0.sourceID, $0.targetID) },
      directionOf: directionOf,
      metrics: RadialGraphLayout.Metrics(
        nodeSize: Self.nodeSize,
        initialRadius: 210,
        ringSpacing: 178,
        circumferenceSpacing: Self.nodeSize.width + 24,
        margin: max(Self.nodeSize.width, Self.nodeSize.height) / 2 + 36,
        directionBiasWeight: 0.45
      )
    )
    positions = layout.positions
    size = layout.size
  }
}
