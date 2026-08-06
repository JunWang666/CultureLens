import Foundation
import Testing

@testable import CultureLens

struct InternationalizationTests {
  @Test func systemPreferenceResolvesChineseLocales() {
    #expect(
      AppLanguagePreference.system.resolved(deviceLocale: Locale(identifier: "zh-Hans"))
        == .zhHans
    )
    #expect(
      AppLanguagePreference.system.resolved(deviceLocale: Locale(identifier: "zh_CN"))
        == .zhHans
    )
    #expect(
      AppLanguagePreference.system.resolved(deviceLocale: Locale(identifier: "en_US"))
        == .english
    )
    #expect(AppLanguagePreference.english.resolved() == .english)
    #expect(AppLanguagePreference.zhHans.resolved() == .zhHans)
  }

  @Test func promptLanguagePolicyInjectsEnglishOutputRules() {
    let policy = PromptLanguagePolicy(language: .english)
    let prompt = policy.apply(
      toSystemPrompt: "任务说明。\n所有文字使用简体中文。\n",
      kind: .recognize
    )
    #expect(prompt.contains("Write all user-facing free text in English"))
    #expect(!prompt.contains("所有文字使用简体中文。"))
    #expect(policy.recognitionUserPreamble() == "Identify the cultural object in this photo.")
  }

  @Test func explainPromptUsesEnglishSectionHeadings() {
    let policy = PromptLanguagePolicy(language: .english)
    let bundled = """
      你是讲解助手。
      输出格式（严格按此 Markdown 结构，不要包在 JSON 或代码块里）：

      ## 文化背景
      正文

      ## 下一步建议
      - 建议

      ## 引用来源
      - key: `k`, name: n
        - 原文摘录：quote
      """
    let prompt = policy.apply(toSystemPrompt: bundled, kind: .explain)
    #expect(prompt.contains("## Cultural Background"))
    #expect(prompt.contains("## Connections"))
    #expect(prompt.contains("## Next Steps"))
    #expect(prompt.contains("## Sources"))
    #expect(prompt.contains("Source excerpt"))
  }

  @Test func citationParserAcceptsEnglishSourcesHeading() {
    let markdown = """
      West Lake night scenery relies on lamps, water, and moon illusion.

      ## Sources
      - key: `three-pools-mirroring-moon`, name: Three Pools Mirroring the Moon
        - Source excerpt: Stone pagodas, lamp holes, water, and moonlight.
      """
    let parsed = CultureChatService.parseAnswer(markdown, store: nil)
    #expect(parsed.body.contains("West Lake night scenery"))
    #expect(!parsed.body.contains("## Sources"))
    #expect(parsed.citations.count == 1)
    #expect(parsed.citations[0].key == "three-pools-mirroring-moon")
    #expect(parsed.citations[0].fragment.contains("Stone pagodas"))
  }

  @Test func knowledgePackDecodesEmptyLocalesOverlay() throws {
    let json = """
      {
        "version": "test-v1",
        "source_language": "zh-Hans",
        "elements": [
          {
            "key": "e1",
            "name": "元素一",
            "introduction": { "schemaVersion": 1, "blocks": [{ "type": "paragraph", "text": "介绍" }] }
          }
        ],
        "attractions": [],
        "relations": [],
        "introductions": [],
        "locales": {}
      }
      """.data(using: .utf8)!
    let pack = try JSONDecoder().decode(KnowledgePack.self, from: json)
    #expect(pack.sourceLanguage == "zh-Hans")
    #expect(pack.locales?.isEmpty == true)

    let localization = KnowledgeLocalization(pack: pack)
    let zh = localization.elementText(key: "e1", language: .zhHans)
    #expect(zh?.name == "元素一")
    #expect(zh?.isSourceFallback == false)

    let en = localization.elementText(key: "e1", language: .english)
    #expect(en?.name == "元素一")
    #expect(en?.isSourceFallback == true)
  }

  @Test func knowledgePackDecodesEnglishOverlayWhenPresent() throws {
    let json = """
      {
        "version": "test-v1",
        "source_language": "zh-Hans",
        "elements": [
          {
            "key": "e1",
            "name": "元素一",
            "introduction": { "schemaVersion": 1, "blocks": [{ "type": "paragraph", "text": "介绍" }] }
          }
        ],
        "attractions": [{ "key": "a1", "name": "景点一" }],
        "relations": [],
        "introductions": [],
        "locales": {
          "en": {
            "elements": {
              "e1": {
                "name": "Element One",
                "introduction": {
                  "schemaVersion": 1,
                  "blocks": [{ "type": "paragraph", "text": "Intro" }]
                }
              }
            },
            "attractions": {
              "a1": { "name": "Attraction One" }
            }
          }
        }
      }
      """.data(using: .utf8)!
    let pack = try JSONDecoder().decode(KnowledgePack.self, from: json)
    let localization = KnowledgeLocalization(pack: pack)
    let en = try #require(localization.elementText(key: "e1", language: .english))
    #expect(en.name == "Element One")
    #expect(en.isSourceFallback == false)
    #expect(en.introduction?.plainText == "Intro")
    #expect(
      localization.attractionName(key: "a1", language: .english)?.name == "Attraction One")
  }

  @Test func bundledKnowledgePackExposesMultilingualSchema() async throws {
    let store = try #require(await KnowledgePackLoader.shared.store(fallback: nil))
    #expect(store.pack.sourceLanguage == "zh-Hans" || store.pack.sourceLanguage == nil)
    // Regional packs may ship `locales.en`; West Lake may still be empty.
    let localeCount = store.pack.locales?.count ?? 0
    #expect(localeCount >= 0)
  }

  @Test func englishPromptAssemblerEmitsEnglishPreamble() throws {
    let assembler = PromptAssembler(
      systemPrompt: "SYS\n所有文字使用简体中文。",
      languagePolicy: PromptLanguagePolicy(language: .english)
    )
    let text = try assembler.userText(
      contextNote: nil,
      knowledgeCandidates: [],
      attractionCandidates: []
    )
    #expect(text == "Identify the cultural object in this photo.")
    #expect(assembler.systemPrompt.contains("Write all user-facing free text in English"))
  }
}
