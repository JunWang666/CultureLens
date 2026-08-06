import Foundation
import Testing
@testable import CultureLens

struct KnowledgePackEditorTests {
  @Test func richTextRoundTripPreservesParagraphsAndImages() {
    let text = """
      第一段介绍。

      ![湖面](https://cdn.example.com/lake.jpg)

      第三段延伸。
      """
    let document = RichTextEditing.document(fromPlainText: text)
    #expect(document.blocks.count == 3)
    #expect(document.blocks[0].type == "paragraph")
    #expect(document.blocks[1].type == "image")
    #expect(document.blocks[1].url == "https://cdn.example.com/lake.jpg")
    #expect(document.blocks[1].caption == "湖面")
    let plain = RichTextEditing.plainText(from: document)
    #expect(plain.contains("第一段介绍。"))
    #expect(plain.contains("![湖面](https://cdn.example.com/lake.jpg)"))
  }

  @Test func exporterWritesSidecarLayoutAndReloads() throws {
    let pack = samplePack()
    let bundle = try KnowledgePackExporter.makeExportBundle(for: pack, directoryName: "sample")
    #expect(bundle.files["knowledge-pack.json"] != nil)
    #expect(bundle.files["elements-sight.json"] != nil)
    #expect(bundle.files["elements-history.json"] != nil)
    #expect(bundle.files["introductions.json"] != nil)
    #expect(bundle.files["themes.json"] != nil)
    #expect(bundle.files["locales-en.json"] != nil)
    #expect(bundle.files["pack-manifest.json"] != nil)
    #expect(bundle.manifest.recordCounts.elements == 2)
    #expect(bundle.manifest.recordCounts.elementsSight == 1)
    #expect(bundle.manifest.recordCounts.elementsHistory == 1)

    let main = try JSONDecoder().decode(
      KnowledgePackMainSidecar.self,
      from: bundle.files["knowledge-pack.json"]!
    )
    #expect(main.version == "sample-v1")
    #expect(main.relations.count == 1)
    // Slim main JSON must not embed element arrays.
    let mainObject = try JSONSerialization.jsonObject(with: bundle.files["knowledge-pack.json"]!)
      as? [String: Any]
    #expect(mainObject?["elements"] == nil)

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("pack-export-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try KnowledgePackExporter.writeSidecars(bundle, to: directory)
    let reloaded = try KnowledgeStore.loadPack(
      fromBaseURL: directory.appendingPathComponent("knowledge-pack.json")
    )
    #expect(reloaded.version == "sample-v1")
    #expect(reloaded.elements.count == 2)
    #expect(reloaded.attractions.count == 1)
    #expect(reloaded.relations.count == 1)
    #expect(reloaded.introductions.count == 1)
    #expect(reloaded.themes.count == 1)
    #expect(reloaded.locales?["en"] != nil)
  }

  @Test func zipArchiveRoundTripsStoredBytes() throws {
    let pack = samplePack()
    let bundle = try KnowledgePackExporter.makeExportBundle(for: pack)
    let zip = try KnowledgePackExporter.zipData(for: bundle)
    #expect(zip.count > 64)
    // Local file header signature
    #expect(zip.starts(with: [0x50, 0x4b, 0x03, 0x04]))
  }

  @Test func validatorFlagsMissingAttractionElementAndUpwardCycle() {
    let emptyIntro = RichTextDocument(schemaVersion: 1, blocks: [
      .init(type: "paragraph", text: "说明")
    ])
    let pack = KnowledgePack(
      version: "bad-v1",
      elements: [
        KnowledgePack.Element(
          key: "a",
          name: "A",
          introduction: emptyIntro,
          conceptKind: ConceptKind.foundation.rawValue,
          contentRole: ContentRole.history.rawValue
        ),
        KnowledgePack.Element(
          key: "b",
          name: "B",
          introduction: emptyIntro,
          conceptKind: ConceptKind.history.rawValue,
          contentRole: ContentRole.history.rawValue
        ),
      ],
      attractions: [KnowledgePack.Attraction(key: "missing-spot", name: "缺失景点")],
      relations: [
        KnowledgePack.Relation(
          elementKey: "a",
          relatedElementKey: "b",
          kind: RelationKind.locatedIn.rawValue,
          explanation: "A 位于 B"
        ),
        KnowledgePack.Relation(
          elementKey: "b",
          relatedElementKey: "a",
          kind: RelationKind.expresses.rawValue,
          explanation: "B 体现 A"
        ),
      ],
      introductions: []
    )
    let issues = KnowledgePackValidator.validate(pack)
    #expect(issues.contains { $0.message.contains("missing-spot") })
    #expect(issues.contains { $0.message.contains("上行关系图存在环") })
    #expect(KnowledgePackValidator.hasErrors(pack))
  }

  @MainActor
  @Test func draftBuildPackSyncsSightAttractions() {
    let draft = KnowledgePackDraft.blank()
    draft.elements = [
      EditableElement(
        key: "tower",
        name: "塔",
        contentRole: .sight,
        conceptKind: .foundation,
        introductionText: "一座塔。"
      ),
      EditableElement(
        key: "dynasty",
        name: "朝代",
        contentRole: .history,
        conceptKind: .history,
        introductionText: "一个朝代。"
      ),
    ]
    let pack = draft.buildPack()
    #expect(pack.attractions.compactMap(\.key) == ["tower"])
    #expect(pack.attractions.first?.name == "塔")
    #expect(pack.elements.count == 2)
  }

  private func samplePack() -> KnowledgePack {
    let intro = RichTextDocument(
      schemaVersion: 1,
      blocks: [.init(type: "paragraph", text: "现场可见的遗存。")]
    )
    return KnowledgePack(
      version: "sample-v1",
      sourceLanguage: "zh-Hans",
      elements: [
        KnowledgePack.Element(
          key: "site-a",
          name: "遗址甲",
          introduction: intro,
          sources: [.init(title: "维基百科", publisher: "维基百科", url: "https://zh.wikipedia.org")],
          conceptKind: ConceptKind.foundation.rawValue,
          contentRole: ContentRole.sight.rawValue
        ),
        KnowledgePack.Element(
          key: "concept-b",
          name: "概念乙",
          introduction: intro,
          conceptKind: ConceptKind.aesthetics.rawValue,
          contentRole: ContentRole.history.rawValue
        ),
      ],
      attractions: [KnowledgePack.Attraction(key: "site-a", name: "遗址甲")],
      relations: [
        KnowledgePack.Relation(
          elementKey: "site-a",
          relatedElementKey: "concept-b",
          kind: RelationKind.expresses.rawValue,
          explanation: "遗址甲体现概念乙。"
        )
      ],
      introductions: [
        KnowledgePack.IntroductionRecord(
          key: "site-a-spot",
          name: "遗址甲现场",
          introduction: intro,
          culturalElementKey: "site-a",
          attractionKey: "site-a",
          latitude: 30.25,
          longitude: 120.15,
          coordinateSourceUrl: "https://zh.wikipedia.org"
        )
      ],
      themes: [
        KnowledgePack.Theme(
          key: "theme-1",
          name: "主题一",
          summary: "一条探索线",
          elementKeys: ["site-a", "concept-b"],
          minContacted: 1
        )
      ],
      locales: [
        "en": KnowledgePack.LocaleOverlay(
          elements: [
            "site-a": .init(
              name: "Site A",
              introduction: RichTextDocument(
                schemaVersion: 1,
                blocks: [.init(type: "paragraph", text: "A visible ruin.")]
              )
            )
          ],
          attractions: ["site-a": .init(name: "Site A")]
        )
      ]
    )
  }
}
