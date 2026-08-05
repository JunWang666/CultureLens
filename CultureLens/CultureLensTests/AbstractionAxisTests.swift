import Foundation
import Testing

@testable import CultureLens

/// Design 0006 阶段 1: directed abstraction-axis traversal over the bundled
/// West Lake pack. These tests pin the concrete facts the design verified by
/// hand (e.g. 三潭印月 can climb to 宋代山水审美 without any content work).
struct AbstractionAxisTests {

  private func loadBundledStore() throws -> KnowledgeStore {
    try KnowledgeStore.load(bundle: Bundle(for: KnowledgeProgressStore.self))
  }

  @Test func relationKindDirectionTable() {
    #expect(RelationKind.locatedIn.abstractionDirection == .up)
    #expect(RelationKind.expresses.abstractionDirection == .up)
    #expect(RelationKind.influencedBy.abstractionDirection == .up)
    #expect(RelationKind.governedBy.abstractionDirection == .up)
    #expect(RelationKind.explains.abstractionDirection == .up)
    #expect(RelationKind.emergedIn.abstractionDirection == .up)
    #expect(RelationKind.composedOf.abstractionDirection == .down)
    #expect(RelationKind.similarTo.abstractionDirection == .lateral)
    #expect(RelationKind.usedFor.abstractionDirection == .lateral)
    #expect(RelationKind.symbolizes.abstractionDirection == .lateral)
    #expect(RelationKind.madeWith.abstractionDirection == .lateral)
    #expect(RelationKind.prerequisiteFor.abstractionDirection == .prerequisite)
  }

  @Test func emergedInIsExcludedFromAuditedUpward() {
    #expect(RelationKind.emergedIn.isAuditedUpward == false)
    #expect(RelationKind.locatedIn.isAuditedUpward)
    #expect(RelationKind.expresses.isAuditedUpward)
    #expect(RelationKind.influencedBy.isAuditedUpward)
    #expect(RelationKind.explains.isAuditedUpward)
    #expect(RelationKind.composedOf.isAuditedUpward == false)
  }

  @Test func threePoolsAncestorsReachSongLandscapeAesthetics() throws {
    let store = try loadBundledStore()
    let levels = store.ancestors(key: "three-pools-mirroring-moon")
    let keyByLevel = Dictionary(
      levels.map { ($0.level, $0.elements.map(\.key)) },
      uniquingKeysWith: { first, _ in first }
    )
    // Design 0006 实测路径:
    // 三潭印月 › 西湖文化景观 › 南宋临安与西湖十景 › 宋代山水审美
    #expect(keyByLevel[1]?.contains("west-lake-cultural-landscape") == true)
    #expect(keyByLevel[2]?.contains("southern-song-linan") == true)
    #expect(keyByLevel[3]?.contains("song-landscape-aesthetics") == true)
  }

  @Test func ancestorsAreDeterministic() throws {
    let store = try loadBundledStore()
    let first = store.ancestors(key: "three-pools-mirroring-moon")
    let second = store.ancestors(key: "three-pools-mirroring-moon")
    #expect(first == second)
  }

  @Test func backbonePriorityOrdersLocatedInFirst() throws {
    let store = try loadBundledStore()
    let levels = store.ancestors(key: "three-pools-mirroring-moon")
    for level in levels {
      let priorities = level.elements.map {
        $0.kind?.abstractionBackbonePriority ?? .max
      }
      #expect(priorities == priorities.sorted())
    }
  }

  @Test func siblingsShareAnUpwardParent() throws {
    let store = try loadBundledStore()
    let siblings = store.siblings(key: "three-pools-mirroring-moon")
    // 苏堤春晓 shares the 南宋西湖十景体系 parent (组成 reverse) with 三潭印月.
    #expect(siblings.contains("su-causeway-spring-dawn"))
  }

  @Test func missingPrerequisitesClosure() throws {
    let store = try loadBundledStore()
    // Pack edge: three-pools-round-openings --理解前先懂--> three-pools-light-mechanism
    let missing = store.missingPrerequisites(
      key: "three-pools-light-mechanism",
      known: []
    )
    #expect(missing.map(\.key) == ["three-pools-round-openings"])
    #expect(missing.first?.excerpt.isEmpty == false)

    let known = store.missingPrerequisites(
      key: "three-pools-light-mechanism",
      known: ["three-pools-round-openings"]
    )
    #expect(known.isEmpty)
  }

  @Test func cyclesKeepEarliestLevel() {
    let store = makeDirectedGraphStore(
      keys: ["a", "b", "c"],
      edges: [
        ("a", "b", "位于"),
        ("b", "c", "位于"),
        ("c", "a", "位于"), // cycle back to the root
      ]
    )
    let levels = store.ancestors(key: "a")
    #expect(levels.count == 2)
    #expect(levels[0].elements.map(\.key) == ["b"])
    #expect(levels[1].elements.map(\.key) == ["c"])
    // Root is never re-listed as its own ancestor, and results repeat exactly.
    #expect(levels.flatMap(\.elements).map(\.key).contains("a") == false)
    #expect(levels == store.ancestors(key: "a"))
  }

  @Test func composedOfReverseCountsAsUpward() {
    let store = makeDirectedGraphStore(
      keys: ["part", "whole"],
      edges: [("whole", "part", "组成")]
    )
    #expect(store.upward(key: "part").map(\.key) == ["whole"])
    #expect(store.downward(key: "whole").map(\.key) == ["part"])
  }

  @Test func emergedInRequiresOptIn() {
    let store = makeDirectedGraphStore(
      keys: ["x", "y"],
      edges: [("x", "y", "产生于")]
    )
    #expect(store.upward(key: "x").isEmpty)
    #expect(store.upward(key: "x", includeUnaudited: true).map(\.key) == ["y"])
  }

  @Test func untypedEdgesNeverEnterTheAxis() {
    let store = makeDirectedGraphStore(
      keys: ["x", "y"],
      edges: [("x", "y", nil)]
    )
    #expect(store.upward(key: "x").isEmpty)
    #expect(store.downward(key: "x").isEmpty)
    #expect(store.lateral(key: "x").isEmpty)
    #expect(store.ancestors(key: "x").isEmpty)
  }

  @Test func edgesByKindMatchBothDirections() {
    let store = makeDirectedGraphStore(
      keys: ["a", "b", "c", "d"],
      edges: [
        ("a", "b", "位于"), // outgoing from a
        ("c", "a", "位于"), // incoming to a
        ("a", "d", "相似于"), // different kind, excluded
      ]
    )
    let edges = store.edges(key: "a", kinds: [.locatedIn])
    #expect(edges.map(\.key) == ["b", "c"])
    #expect(edges.allSatisfy { $0.kind == .locatedIn })
    #expect(store.edges(key: "a", kinds: [.similarTo]).map(\.key) == ["d"])
    #expect(store.edges(key: "a", kinds: [.usedFor]).isEmpty)
    #expect(store.edges(key: "missing", kinds: [.locatedIn]).isEmpty)
  }

  @Test func edgesByKindDeduplicatesReverseDuplicates() {
    let store = makeDirectedGraphStore(
      keys: ["a", "b"],
      edges: [
        ("a", "b", "相似于"),
        ("b", "a", "相似于"), // same pair, reverse direction
      ]
    )
    #expect(store.edges(key: "a", kinds: [.similarTo]).map(\.key) == ["b"])
  }

  @Test func relationDimensionsCoverThreePoolsFromBundledPack() throws {
    let store = try loadBundledStore()
    let key = "three-pools-mirroring-moon"
    // 历史时期
    #expect(store.edges(key: key, kinds: [.emergedIn]).map(\.key).contains("northern-song-three-pools"))
    // 地域文化
    #expect(store.edges(key: key, kinds: [.locatedIn]).map(\.key).contains("west-lake-cultural-landscape"))
    // 使用功能
    #expect(store.edges(key: key, kinds: [.usedFor]).isEmpty == false)
    // 审美观念
    let aesthetics = store.edges(key: key, kinds: [.expresses, .symbolizes, .influencedBy])
    #expect(aesthetics.isEmpty == false)
    #expect(
      aesthetics.allSatisfy { edge in
        edge.kind == .expresses || edge.kind == .symbolizes || edge.kind == .influencedBy
      }
    )
    // 相似对象
    #expect(store.edges(key: key, kinds: [.similarTo]).map(\.key).contains("leifeng-pagoda-and-evening-glow"))
  }
}

private func makeDirectedGraphStore(
  keys: [String],
  edges: [(String, String, String?)]
) -> KnowledgeStore {
  let emptyIntroduction = RichTextDocument(schemaVersion: 1, blocks: [])
  return KnowledgeStore(
    pack: KnowledgePack(
      version: "axis-test",
      elements: keys.map {
        KnowledgePack.Element(
          key: $0,
          name: "节点 \($0)",
          introduction: emptyIntroduction
        )
      },
      attractions: [],
      relations: edges.map {
        KnowledgePack.Relation(
          elementKey: $0.0,
          relatedElementKey: $0.1,
          kind: $0.2
        )
      },
      introductions: []
    )
  )
}
