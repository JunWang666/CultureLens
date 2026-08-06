import Foundation
import Observation

/// Mutable in-memory document for the knowledge-pack editor.
@Observable
@MainActor
final class KnowledgePackDraft: Identifiable {
  let id: UUID
  var version: String
  var sourceLanguage: String
  var elements: [EditableElement]
  var attractions: [EditableAttraction]
  var relations: [EditableRelation]
  var introductions: [EditableIntroduction]
  var themes: [EditableTheme]
  var englishLocales: [EditableLocaleElement]
  var updatedAt: Date
  var displayName: String

  init(
    id: UUID = UUID(),
    version: String = "untitled-v1",
    sourceLanguage: String = "zh-Hans",
    elements: [EditableElement] = [],
    attractions: [EditableAttraction] = [],
    relations: [EditableRelation] = [],
    introductions: [EditableIntroduction] = [],
    themes: [EditableTheme] = [],
    englishLocales: [EditableLocaleElement] = [],
    updatedAt: Date = Date(),
    displayName: String? = nil
  ) {
    self.id = id
    self.version = version
    self.sourceLanguage = sourceLanguage
    self.elements = elements
    self.attractions = attractions
    self.relations = relations
    self.introductions = introductions
    self.themes = themes
    self.englishLocales = englishLocales
    self.updatedAt = updatedAt
    self.displayName = displayName ?? version
  }

  convenience init(
    pack: KnowledgePack,
    id: UUID = UUID(),
    displayName: String? = nil,
    updatedAt: Date = Date()
  ) {
    let stamped = pack.withStampedContentRoles()
    let attractionKeys = Set(stamped.attractions.map(\.key))
    self.init(
      id: id,
      version: stamped.version,
      sourceLanguage: stamped.sourceLanguage ?? "zh-Hans",
      elements: stamped.elements.map {
        EditableElement(
          from: $0,
          attractionKeys: attractionKeys
        )
      },
      attractions: stamped.attractions.map(EditableAttraction.init(from:)),
      relations: stamped.relations.map(EditableRelation.init(from:)),
      introductions: stamped.introductions.map(EditableIntroduction.init(from:)),
      themes: stamped.themes.map(EditableTheme.init(from:)),
      englishLocales: Self.englishLocales(from: stamped.locales?["en"]),
      updatedAt: updatedAt,
      displayName: displayName ?? stamped.version
    )
  }

  static func blank(displayName: String = "新资源包") -> KnowledgePackDraft {
    KnowledgePackDraft(
      version: "custom-pack-v1",
      displayName: displayName
    )
  }

  func markUpdated() {
    updatedAt = Date()
  }

  /// Keeps attractions in sync when an element is marked as 看点.
  func syncAttractionsFromElements() {
    let sightKeys = Set(
      elements.filter { $0.contentRole == .sight }.map(\.key)
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    )
    // Drop attractions whose keys are no longer sights.
    attractions.removeAll { !sightKeys.contains($0.key) }
    let existing = Set(attractions.map(\.key))
    for element in elements where element.contentRole == .sight && !existing.contains(element.key) {
      attractions.append(EditableAttraction(key: element.key, name: element.name))
    }
    // Refresh attraction names from elements.
    for index in attractions.indices {
      if let element = elements.first(where: { $0.key == attractions[index].key }) {
        attractions[index].name = element.name
      }
    }
  }

  func buildPack() -> KnowledgePack {
    syncAttractionsFromElements()
    var locales: [String: KnowledgePack.LocaleOverlay] = [:]
    if !englishLocales.isEmpty {
      var overlay = KnowledgePack.LocaleOverlay()
      for item in englishLocales where !item.key.isEmpty {
        let introText = item.introductionText.trimmingCharacters(in: .whitespacesAndNewlines)
        overlay.elements[item.key] = .init(
          name: item.name.isEmpty ? nil : item.name,
          introduction: introText.isEmpty ? nil : RichTextEditing.document(fromPlainText: introText)
        )
        if !item.name.isEmpty {
          overlay.attractions[item.key] = .init(name: item.name)
        }
      }
      if !overlay.elements.isEmpty || !overlay.attractions.isEmpty {
        locales["en"] = overlay
      }
    }
    return KnowledgePack(
      version: version.trimmingCharacters(in: .whitespacesAndNewlines),
      sourceLanguage: sourceLanguage.trimmingCharacters(in: .whitespacesAndNewlines),
      elements: elements.map { $0.asPackElement() },
      attractions: attractions.map { $0.asPackAttraction() },
      relations: relations.map { $0.asPackRelation() },
      introductions: introductions.map { $0.asPackIntroduction() },
      themes: themes.map { $0.asPackTheme() },
      locales: locales.isEmpty ? nil : locales
    ).withStampedContentRoles()
  }

  private static func englishLocales(
    from overlay: KnowledgePack.LocaleOverlay?
  ) -> [EditableLocaleElement] {
    guard let overlay else { return [] }
    let keys = Set(overlay.elements.keys).union(overlay.attractions.keys).sorted()
    return keys.map { key in
      let element = overlay.elements[key]
      let name = element?.name ?? overlay.attractions[key]?.name ?? ""
      let text = element?.introduction.map {
        RichTextEditing.plainText(from: $0)
      } ?? ""
      return EditableLocaleElement(key: key, name: name, introductionText: text)
    }
  }
}

// MARK: - Editable rows

struct EditableElement: Identifiable, Hashable, Sendable {
  var id: UUID
  var key: String
  var name: String
  var contentRole: ContentRole
  var conceptKind: ConceptKind
  var introductionText: String
  var sources: [EditableSource]

  init(
    id: UUID = UUID(),
    key: String = "",
    name: String = "",
    contentRole: ContentRole = .history,
    conceptKind: ConceptKind = .foundation,
    introductionText: String = "",
    sources: [EditableSource] = []
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.contentRole = contentRole
    self.conceptKind = conceptKind
    self.introductionText = introductionText
    self.sources = sources
  }

  init(from element: KnowledgePack.Element, attractionKeys: Set<String>) {
    self.init(
      key: element.key,
      name: element.name,
      contentRole: element.resolvedContentRole(attractionKeys: attractionKeys),
      conceptKind: ConceptKind(rawValue: element.conceptKind ?? "") ?? .foundation,
      introductionText: RichTextEditing.plainText(from: element.introduction),
      sources: element.sources.map(EditableSource.init(from:))
    )
  }

  func asPackElement() -> KnowledgePack.Element {
    KnowledgePack.Element(
      key: key.trimmingCharacters(in: .whitespacesAndNewlines),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      introduction: RichTextEditing.document(fromPlainText: introductionText),
      sources: sources.compactMap { $0.asPackSource() },
      conceptKind: conceptKind.rawValue,
      contentRole: contentRole.rawValue
    )
  }
}

struct EditableAttraction: Identifiable, Hashable, Sendable {
  var id: UUID
  var key: String
  var name: String

  init(id: UUID = UUID(), key: String, name: String) {
    self.id = id
    self.key = key
    self.name = name
  }

  init(from attraction: KnowledgePack.Attraction) {
    self.init(key: attraction.key, name: attraction.name)
  }

  func asPackAttraction() -> KnowledgePack.Attraction {
    KnowledgePack.Attraction(
      key: key.trimmingCharacters(in: .whitespacesAndNewlines),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}

struct EditableRelation: Identifiable, Hashable, Sendable {
  var id: UUID
  var elementKey: String
  var relatedElementKey: String
  var kind: RelationKind
  var explanation: String

  init(
    id: UUID = UUID(),
    elementKey: String = "",
    relatedElementKey: String = "",
    kind: RelationKind = .explains,
    explanation: String = ""
  ) {
    self.id = id
    self.elementKey = elementKey
    self.relatedElementKey = relatedElementKey
    self.kind = kind
    self.explanation = explanation
  }

  init(from relation: KnowledgePack.Relation) {
    self.init(
      elementKey: relation.elementKey,
      relatedElementKey: relation.relatedElementKey,
      kind: RelationKind(rawValue: relation.kind ?? "") ?? .explains,
      explanation: relation.explanation ?? ""
    )
  }

  func asPackRelation() -> KnowledgePack.Relation {
    KnowledgePack.Relation(
      elementKey: elementKey.trimmingCharacters(in: .whitespacesAndNewlines),
      relatedElementKey: relatedElementKey.trimmingCharacters(in: .whitespacesAndNewlines),
      kind: kind.rawValue,
      explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }
}

struct EditableIntroduction: Identifiable, Hashable, Sendable {
  var id: UUID
  var key: String
  var name: String
  var culturalElementKey: String
  var attractionKey: String
  var latitude: String
  var longitude: String
  var coordinateSourceUrl: String
  var introductionText: String

  init(
    id: UUID = UUID(),
    key: String = "",
    name: String = "",
    culturalElementKey: String = "",
    attractionKey: String = "",
    latitude: String = "0",
    longitude: String = "0",
    coordinateSourceUrl: String = "",
    introductionText: String = ""
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.culturalElementKey = culturalElementKey
    self.attractionKey = attractionKey
    self.latitude = latitude
    self.longitude = longitude
    self.coordinateSourceUrl = coordinateSourceUrl
    self.introductionText = introductionText
  }

  init(from record: KnowledgePack.IntroductionRecord) {
    self.init(
      key: record.key,
      name: record.name,
      culturalElementKey: record.culturalElementKey,
      attractionKey: record.attractionKey,
      latitude: String(record.latitude),
      longitude: String(record.longitude),
      coordinateSourceUrl: record.coordinateSourceUrl ?? "",
      introductionText: RichTextEditing.plainText(from: record.introduction)
    )
  }

  func asPackIntroduction() -> KnowledgePack.IntroductionRecord {
    KnowledgePack.IntroductionRecord(
      key: key.trimmingCharacters(in: .whitespacesAndNewlines),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      introduction: RichTextEditing.document(fromPlainText: introductionText),
      culturalElementKey: culturalElementKey.trimmingCharacters(in: .whitespacesAndNewlines),
      attractionKey: attractionKey.trimmingCharacters(in: .whitespacesAndNewlines),
      latitude: Double(latitude) ?? 0,
      longitude: Double(longitude) ?? 0,
      coordinateSourceUrl: coordinateSourceUrl.isEmpty ? nil : coordinateSourceUrl
    )
  }
}

struct EditableTheme: Identifiable, Hashable, Sendable {
  var id: UUID
  var key: String
  var name: String
  var summary: String
  var elementKeysText: String
  var minContacted: Int

  init(
    id: UUID = UUID(),
    key: String = "",
    name: String = "",
    summary: String = "",
    elementKeysText: String = "",
    minContacted: Int = 1
  ) {
    self.id = id
    self.key = key
    self.name = name
    self.summary = summary
    self.elementKeysText = elementKeysText
    self.minContacted = minContacted
  }

  init(from theme: KnowledgePack.Theme) {
    self.init(
      key: theme.key,
      name: theme.name,
      summary: theme.summary,
      elementKeysText: theme.elementKeys.joined(separator: ", "),
      minContacted: theme.minContacted
    )
  }

  func asPackTheme() -> KnowledgePack.Theme {
    let keys = elementKeysText
      .split(whereSeparator: { $0 == "," || $0.isNewline })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return KnowledgePack.Theme(
      key: key.trimmingCharacters(in: .whitespacesAndNewlines),
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
      elementKeys: keys,
      minContacted: max(1, minContacted)
    )
  }
}

struct EditableSource: Identifiable, Hashable, Sendable {
  var id: UUID
  var title: String
  var publisher: String
  var url: String

  init(id: UUID = UUID(), title: String = "", publisher: String = "", url: String = "") {
    self.id = id
    self.title = title
    self.publisher = publisher
    self.url = url
  }

  init(from source: KnowledgePack.Source) {
    self.init(title: source.title, publisher: source.publisher, url: source.url ?? "")
  }

  func asPackSource() -> KnowledgePack.Source? {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let publisher = publisher.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty || !publisher.isEmpty || !url.isEmpty else { return nil }
    return KnowledgePack.Source(
      title: title.isEmpty ? publisher : title,
      publisher: publisher.isEmpty ? title : publisher,
      url: url.isEmpty ? nil : url
    )
  }
}

struct EditableLocaleElement: Identifiable, Hashable, Sendable {
  var id: UUID
  var key: String
  var name: String
  var introductionText: String

  init(id: UUID = UUID(), key: String, name: String, introductionText: String) {
    self.id = id
    self.key = key
    self.name = name
    self.introductionText = introductionText
  }
}

// MARK: - Rich text helpers for the editor

enum RichTextEditing {
  /// Paragraphs separated by blank lines; lines starting with `![](` become image blocks.
  nonisolated static func document(fromPlainText text: String) -> RichTextDocument {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return RichTextDocument(schemaVersion: 1, blocks: [])
    }
    var blocks: [RichTextDocument.Block] = []
    let paragraphs = trimmed.components(separatedBy: "\n\n")
    for paragraph in paragraphs {
      let line = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else { continue }
      if let image = parseImageMarkdown(line) {
        blocks.append(image)
      } else {
        blocks.append(.init(type: "paragraph", text: line))
      }
    }
    return RichTextDocument(schemaVersion: 1, blocks: blocks)
  }

  nonisolated static func plainText(from document: RichTextDocument) -> String {
    document.blocks.compactMap { block -> String? in
      switch block.type {
      case "image":
        guard let url = block.url, !url.isEmpty else { return nil }
        if let caption = block.caption, !caption.isEmpty {
          return "![\(caption)](\(url))"
        }
        return "![](\(url))"
      default:
        return block.text
      }
    }
    .joined(separator: "\n\n")
  }

  nonisolated private static func parseImageMarkdown(_ line: String) -> RichTextDocument.Block? {
    // ![caption](https://...)
    guard line.hasPrefix("!["), let closeBracket = line.firstIndex(of: "]"),
      line[line.index(after: closeBracket)...].hasPrefix("("),
      line.hasSuffix(")")
    else { return nil }
    let captionStart = line.index(line.startIndex, offsetBy: 2)
    let caption = String(line[captionStart..<closeBracket])
    let urlStart = line.index(closeBracket, offsetBy: 2)
    let urlEnd = line.index(before: line.endIndex)
    let url = String(line[urlStart..<urlEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    guard url.hasPrefix("https://") else { return nil }
    return .init(
      type: "image",
      url: url,
      caption: caption.isEmpty ? nil : caption
    )
  }
}
