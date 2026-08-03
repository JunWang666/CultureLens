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
  static func conceptKind(key: String, name: String) -> ConceptKind {
    let normalizedKey = key.lowercased()
    if normalizedKey.contains("su-shi") || normalizedKey.contains("bai-juyi") {
      return .people
    }
    if normalizedKey.contains("song") || name.contains("朝") || name.contains("临安") {
      return .history
    }
    if normalizedKey.contains("garden") || normalizedKey.contains("landscape")
      || normalizedKey.contains("moon")
    {
      return .aesthetics
    }
    return .foundation
  }
}

/// A deterministic radial shortest-hop layout. It performs no iterative
/// simulation, so positions are stable and the cost is linear after grouping.
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
    let nodesByRing = Dictionary(grouping: snapshot.nodes.filter { $0.id != centerID }) {
      min(max($0.hop, 1), outerJoinedHop)
    }

    var radiusByRing: [Int: CGFloat] = [:]
    var previousRadius: CGFloat = 0
    for ring in nodesByRing.keys.sorted() {
      let count = CGFloat(nodesByRing[ring]?.count ?? 0)
      let radiusForCircumference = count * (Self.nodeSize.width + 24) / (2 * .pi)
      let minimumRadius = previousRadius == 0 ? 210 : previousRadius + 178
      let radius = max(minimumRadius, radiusForCircumference)
      radiusByRing[ring] = radius
      previousRadius = radius
    }

    let maximumRadius = max(radiusByRing.values.max() ?? 0, 210)
    let margin = max(Self.nodeSize.width, Self.nodeSize.height) / 2 + 36
    let center = CGPoint(x: maximumRadius + margin, y: maximumRadius + margin)
    var result: [UUID: CGPoint] = [centerID: center]

    for ring in nodesByRing.keys.sorted() {
      guard let nodes = nodesByRing[ring], !nodes.isEmpty else { continue }
      let orderedNodes = nodes.sorted {
        if $0.name != $1.name { return $0.name.localizedCompare($1.name) == .orderedAscending }
        return $0.id.uuidString < $1.id.uuidString
      }
      let angleStep = 2 * CGFloat.pi / CGFloat(orderedNodes.count)
      let startingAngle = -CGFloat.pi / 2 + (ring.isMultiple(of: 2) ? angleStep / 2 : 0)
      let radius = radiusByRing[ring] ?? 210
      for (index, node) in orderedNodes.enumerated() {
        let angle = startingAngle + CGFloat(index) * angleStep
        result[node.id] = CGPoint(
          x: center.x + cos(angle) * radius,
          y: center.y + sin(angle) * radius
        )
      }
    }

    positions = result
    size = CGSize(width: center.x * 2, height: center.y * 2)
  }
}
