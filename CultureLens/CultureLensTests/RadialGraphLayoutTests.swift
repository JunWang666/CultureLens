import CoreGraphics
import Foundation
import Testing

@testable import CultureLens

/// Design 0007 验证: the shared radial layout kernel is deterministic and its
/// barycenter ordering keeps connected nodes angularly close (which is what
/// removes center-crossing long edges).
struct RadialGraphLayoutTests {

  private func makeNode(
    _ name: String,
    ring: Int,
    id: UUID = UUID()
  ) -> (RadialGraphLayout.Node, UUID) {
    (RadialGraphLayout.Node(id: id, ring: ring, name: name), id)
  }
  private func angle(of id: UUID, in layout: RadialGraphLayout, center: CGPoint) -> CGFloat {
    guard let point = layout.positions[id] else { return .nan }
    return atan2(point.y - center.y, point.x - center.x)
  }

  private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let delta = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
    return min(delta, 2 * .pi - delta)
  }

  @Test func layoutIsDeterministic() {
    let centerID = UUID()
    let nodesAndIDs = [
      makeNode("甲", ring: 1), makeNode("乙", ring: 1), makeNode("丙", ring: 2),
      makeNode("丁", ring: 2),
    ]
    let nodes = nodesAndIDs.map(\.0)
    let edges: [(UUID, UUID)] = [
      (centerID, nodesAndIDs[0].1),
      (centerID, nodesAndIDs[1].1),
      (nodesAndIDs[0].1, nodesAndIDs[2].1),
      (nodesAndIDs[1].1, nodesAndIDs[3].1),
    ]
    let metrics = RadialGraphLayout.Metrics(
      nodeSize: CGSize(width: 146, height: 86),
      initialRadius: 210,
      ringSpacing: 178,
      circumferenceSpacing: 170,
      margin: 100
    )
    let first = RadialGraphLayout(
      centerID: centerID, nodes: nodes, edges: edges, metrics: metrics
    )
    let second = RadialGraphLayout(
      centerID: centerID, nodes: nodes, edges: edges, metrics: metrics
    )
    #expect(first.positions == second.positions)
    #expect(first.size == second.size)
  }

  @Test func barycenterKeepsChildrenNearTheirParents() {
    let centerID = UUID()
    // Ring-2 names sort in the *opposite* order of their ring-1 parents, so
    // pure name ordering would scatter them; barycenter ordering must keep
    // each child angularly close to its parent.
    let parentNames = ["一", "二", "三", "四"]
    let parentIDs = parentNames.map { _ in UUID() }
    let childNames = ["z-child", "y-child", "x-child", "w-child"]
    let childIDs = childNames.map { _ in UUID() }

    var nodes: [RadialGraphLayout.Node] = []
    var edges: [(UUID, UUID)] = []
    for (index, name) in parentNames.enumerated() {
      nodes.append(RadialGraphLayout.Node(id: parentIDs[index], ring: 1, name: name))
      edges.append((centerID, parentIDs[index]))
    }
    // child i (alphabetically first) belongs to parent i (numerically first).
    for (index, name) in childNames.enumerated() {
      nodes.append(RadialGraphLayout.Node(id: childIDs[index], ring: 2, name: name))
      edges.append((parentIDs[index], childIDs[index]))
    }

    let layout = RadialGraphLayout(
      centerID: centerID,
      nodes: nodes,
      edges: edges,
      metrics: RadialGraphLayout.Metrics(
        nodeSize: CGSize(width: 146, height: 86),
        initialRadius: 210,
        ringSpacing: 178,
        circumferenceSpacing: 170,
        margin: 100
      )
    )
    let center = layout.positions[centerID] ?? .zero
    for index in parentIDs.indices {
      let distance = angularDistance(
        angle(of: parentIDs[index], in: layout, center: center),
        angle(of: childIDs[index], in: layout, center: center)
      )
      // Parent and child stay within a quarter circle of each other.
      #expect(distance < .pi / 2)
    }
  }

  @Test func directionBiasPullsAncestorsUp() {
    let centerID = UUID()
    let upID = UUID()
    let downID = UUID()
    let lateralID = UUID()
    let nodes = [
      RadialGraphLayout.Node(id: upID, ring: 1, name: "上"),
      RadialGraphLayout.Node(id: downID, ring: 1, name: "下"),
      RadialGraphLayout.Node(id: lateralID, ring: 1, name: "横"),
    ]
    let layout = RadialGraphLayout(
      centerID: centerID,
      nodes: nodes,
      edges: [(centerID, upID), (centerID, downID), (centerID, lateralID)],
      directionOf: [upID: .up, downID: .down, lateralID: .lateral],
      metrics: RadialGraphLayout.Metrics(
        nodeSize: CGSize(width: 146, height: 86),
        initialRadius: 210,
        ringSpacing: 178,
        circumferenceSpacing: 170,
        margin: 100,
        directionBiasWeight: 0.6
      )
    )
    let center = layout.positions[centerID] ?? .zero
    let upPoint = layout.positions[upID] ?? .zero
    let downPoint = layout.positions[downID] ?? .zero
    // 上行节点在中心上方，下行节点在下方。
    #expect(upPoint.y < center.y)
    #expect(downPoint.y > center.y)
  }

  @Test func userGraphEdgesCarryKindAndExplanation() {
    let store = KnowledgeStore(
      pack: KnowledgePack(
        version: "edge-test",
        elements: ["a", "b"].map {
          KnowledgePack.Element(
            key: $0,
            name: "节点 \($0)",
            introduction: RichTextDocument(schemaVersion: 1, blocks: [])
          )
        },
        attractions: [],
        relations: [
          KnowledgePack.Relation(
            elementKey: "a",
            relatedElementKey: "b",
            kind: "位于",
            explanation: "a 位于 b。"
          )
        ],
        introductions: []
      )
    )
    let snapshot = store.userKnowledgeGraph(
      centerID: DeterministicID.culturalElement("a"),
      joinedSeeds: []
    )
    #expect(snapshot.edges.count == 1)
    #expect(snapshot.edges.first?.kind == .locatedIn)
    #expect(snapshot.edges.first?.explanation == "a 位于 b。")
  }

  @Test func emptySnapshotHasZeroSize() {
    let layout = UserKnowledgeGraphLayout(
      snapshot: UserKnowledgeGraphSnapshot(
        centerID: nil,
        centerIDs: [],
        nodes: [],
        edges: [],
        maximumDepth: 3,
        isExpansionTruncated: false
      )
    )
    #expect(layout.positions.isEmpty)
    #expect(layout.size == .zero)
  }

  @Test func multiCenterLayoutIsDeterministicAndRadiatesAroundCenters() {
    let centerA = UUID()
    let centerB = UUID()
    let nodesAndIDs = [
      makeNode("甲", ring: 1), makeNode("乙", ring: 1), makeNode("丙", ring: 2),
    ]
    let nodes = nodesAndIDs.map(\.0)
    let edges: [(UUID, UUID)] = [
      (centerA, nodesAndIDs[0].1),
      (centerB, nodesAndIDs[1].1),
      (nodesAndIDs[0].1, nodesAndIDs[2].1),
    ]
    let metrics = RadialGraphLayout.Metrics(
      nodeSize: CGSize(width: 146, height: 86),
      initialRadius: 210,
      ringSpacing: 178,
      circumferenceSpacing: 170,
      margin: 100
    )
    let first = RadialGraphLayout(
      centerIDs: [centerA, centerB], nodes: nodes, edges: edges, metrics: metrics
    )
    let second = RadialGraphLayout(
      centerIDs: [centerA, centerB], nodes: nodes, edges: edges, metrics: metrics
    )
    #expect(first.positions == second.positions)
    #expect(first.size == second.size)

    let pointA = first.positions[centerA] ?? .zero
    let pointB = first.positions[centerB] ?? .zero
    // Two centers occupy distinct spots on the inner cluster circle.
    #expect(hypot(pointA.x - pointB.x, pointA.y - pointB.y) > 0)

    // Ring-1 nodes sit outside the center cluster.
    let middle = CGPoint(x: first.size.width / 2, y: first.size.height / 2)
    let clusterRadius = hypot(pointA.x - middle.x, pointA.y - middle.y)
    let ringOneRadius = hypot(
      (first.positions[nodesAndIDs[0].1] ?? .zero).x - middle.x,
      (first.positions[nodesAndIDs[0].1] ?? .zero).y - middle.y
    )
    #expect(ringOneRadius > clusterRadius)
  }
}
