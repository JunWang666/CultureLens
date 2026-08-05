import CoreGraphics
import Foundation

/// Shared deterministic radial layout for both graph surfaces
/// (`CultureRelationGraphView` and `UserKnowledgeGraphView`).
///
/// Nodes sit on concentric rings by hop from the center. Within a ring, nodes
/// are ordered by the average angle of their already-placed neighbors
/// (barycenter ordering) followed by a fixed number of median sweeps, which
/// removes most center-crossing long edges without any iterative simulation.
/// Ties always fall back to `(name, id)`, so identical inputs produce
/// identical layouts.
///
/// An optional per-node `AbstractionDirection` bias (design 0006/0007 阶段 4)
/// pulls nodes toward their semantic region: ancestors up, descendants down,
/// lateral relations to the sides.
nonisolated struct RadialGraphLayout {
  struct Node: Hashable {
    let id: UUID
    /// Ring index; the center is ring 0 and must not appear here.
    let ring: Int
    let name: String

    init(id: UUID, ring: Int, name: String) {
      self.id = id
      self.ring = ring
      self.name = name
    }
  }

  struct Metrics {
    var nodeSize: CGSize
    /// Ring 1 minimum radius.
    var initialRadius: CGFloat
    /// Minimum radius growth per ring.
    var ringSpacing: CGFloat
    /// Circumference allocation per node (drives radius for crowded rings).
    var circumferenceSpacing: CGFloat
    /// Ellipse stretch applied to the unit ring; 1 keeps a circle.
    var horizontalStretch: CGFloat
    var verticalStretch: CGFloat
    /// Canvas margin around the outermost ring.
    var margin: CGFloat
    /// How strongly the abstraction-direction bias pulls the angular order
    /// (0 disables the bias, 1 snaps to the semantic region).
    var directionBiasWeight: CGFloat

    init(
      nodeSize: CGSize,
      initialRadius: CGFloat,
      ringSpacing: CGFloat,
      circumferenceSpacing: CGFloat,
      horizontalStretch: CGFloat = 1,
      verticalStretch: CGFloat = 1,
      margin: CGFloat,
      directionBiasWeight: CGFloat = 0
    ) {
      self.nodeSize = nodeSize
      self.initialRadius = initialRadius
      self.ringSpacing = ringSpacing
      self.circumferenceSpacing = circumferenceSpacing
      self.horizontalStretch = horizontalStretch
      self.verticalStretch = verticalStretch
      self.margin = margin
      self.directionBiasWeight = directionBiasWeight
    }
  }

  let positions: [UUID: CGPoint]
  let size: CGSize

  init(
    centerID: UUID,
    nodes: [Node],
    edges: [(UUID, UUID)],
    directionOf: [UUID: AbstractionDirection] = [:],
    metrics: Metrics
  ) {
    guard !nodes.isEmpty else {
      positions = [centerID: CGPoint(x: metrics.margin, y: metrics.margin)]
      size = CGSize(width: metrics.margin * 2, height: metrics.margin * 2)
      return
    }

    let nodesByRing = Dictionary(grouping: nodes, by: \.ring)
    let orderedRings = nodesByRing.keys.sorted()

    var radiusByRing: [Int: CGFloat] = [:]
    var previousRadius: CGFloat = 0
    for ring in orderedRings {
      let count = CGFloat(nodesByRing[ring]?.count ?? 0)
      let circumferenceRadius = count * metrics.circumferenceSpacing / (2 * .pi)
      let minimumRadius =
        previousRadius == 0 ? metrics.initialRadius : previousRadius + metrics.ringSpacing
      let radius = max(minimumRadius, circumferenceRadius)
      radiusByRing[ring] = radius
      previousRadius = radius
    }

    let maximumRadius = max(radiusByRing.values.max() ?? metrics.initialRadius, metrics.initialRadius)
    let center = CGPoint(
      x: maximumRadius * metrics.horizontalStretch + metrics.margin,
      y: maximumRadius * metrics.verticalStretch + metrics.margin
    )

    var adjacency: [UUID: Set<UUID>] = [:]
    for edge in edges {
      adjacency[edge.0, default: []].insert(edge.1)
      adjacency[edge.1, default: []].insert(edge.0)
    }

    // Ring 0: the center participates in barycenters but has no fixed angle;
    // use straight up so ring-1 nodes connected only to the center stay
    // deterministic through the (name, id) tie-break.
    var angleByID: [UUID: CGFloat] = [centerID: -.pi / 2]

    func barycenterAngle(of node: Node) -> CGFloat? {
      var sumX: CGFloat = 0
      var sumY: CGFloat = 0
      for neighbor in adjacency[node.id, default: []] {
        guard let angle = angleByID[neighbor] else { continue }
        sumX += cos(angle)
        sumY += sin(angle)
      }
      guard sumX != 0 || sumY != 0 else { return nil }
      return atan2(sumY, sumX)
    }

    func biasedAngle(of node: Node, barycenter: CGFloat?) -> CGFloat {
      let base = barycenter ?? -.pi / 2
      guard
        metrics.directionBiasWeight > 0,
        let direction = directionOf[node.id],
        let target = Self.directionTargetAngle(direction, near: base)
      else { return base }
      let delta = (target - base).truncatingRemainder(dividingBy: 2 * .pi)
      let wrapped = delta > .pi ? delta - 2 * .pi : (delta < -.pi ? delta + 2 * .pi : delta)
      return base + wrapped * metrics.directionBiasWeight
    }

    func placeRing(_ ring: Int) {
      guard let ringNodes = nodesByRing[ring], !ringNodes.isEmpty else { return }
      let ordered = ringNodes.sorted { lhs, rhs in
        let lhsAngle = biasedAngle(of: lhs, barycenter: barycenterAngle(of: lhs))
        let rhsAngle = biasedAngle(of: rhs, barycenter: barycenterAngle(of: rhs))
        if lhsAngle != rhsAngle { return lhsAngle < rhsAngle }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      let angleStep = 2 * CGFloat.pi / CGFloat(ordered.count)
      let startingAngle = -CGFloat.pi / 2 + (ring.isMultiple(of: 2) ? angleStep / 2 : 0)
      for (index, node) in ordered.enumerated() {
        angleByID[node.id] = startingAngle + angleStep * CGFloat(index)
      }
    }

    for ring in orderedRings {
      placeRing(ring)
    }
    // Median sweeps: re-order each ring against the fully placed graph.
    for _ in 0..<2 {
      for ring in orderedRings {
        placeRing(ring)
      }
    }

    var result: [UUID: CGPoint] = [centerID: center]
    for node in nodes {
      guard let angle = angleByID[node.id] else { continue }
      let radius = radiusByRing[node.ring] ?? metrics.initialRadius
      result[node.id] = CGPoint(
        x: center.x + cos(angle) * radius * metrics.horizontalStretch,
        y: center.y + sin(angle) * radius * metrics.verticalStretch
      )
    }

    positions = result
    size = CGSize(width: center.x * 2, height: center.y * 2)
  }

  /// Semantic region for a direction: up → 12 o'clock, down → 6 o'clock,
  /// lateral → whichever side (3 or 9 o'clock) is closer to `base`.
  private static func directionTargetAngle(
    _ direction: AbstractionDirection,
    near base: CGFloat
  ) -> CGFloat? {
    switch direction {
    case .up:
      return -.pi / 2
    case .down:
      return .pi / 2
    case .lateral:
      let cosine = cos(base)
      return cosine >= 0 ? 0 : .pi
    case .prerequisite:
      return nil
    }
  }
}
