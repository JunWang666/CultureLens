import Foundation
import Testing

@testable import CultureLens

struct KnowledgePackResourceTests {
  @Test func snapshotMapsDecodedPackMetadata() {
    let empty = RichTextDocument(schemaVersion: 1, blocks: [])
    let pack = KnowledgePack(
      version: "culturelens-v1",
      elements: [
        KnowledgePack.Element(key: "one", name: "一", introduction: empty),
        KnowledgePack.Element(key: "two", name: "二", introduction: empty),
      ],
      attractions: [KnowledgePack.Attraction(key: "one", name: "一")],
      relations: [KnowledgePack.Relation(elementKey: "one", relatedElementKey: "two")],
      introductions: [],
      themes: []
    )

    let resource = KnowledgePackResource(
      directory: .unified,
      delivery: .onDemand,
      availability: .available,
      pack: pack
    )

    #expect(resource.id == "KnowledgePack")
    #expect(resource.version == "culturelens-v1")
    #expect(resource.elementCount == 2)
    #expect(resource.attractionCount == 1)
    #expect(resource.relationCount == 1)
    #expect(resource.availability == .available)
  }

  @Test func shippedPackUsesKnowledgeBaseTag() {
    let tags = KnowledgePackDirectory.allCases.map(\.odrTag)
    #expect(tags == ["knowledge-base"])
  }
}
