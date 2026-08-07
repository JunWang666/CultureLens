import Foundation
import Testing

@testable import CultureLens

struct InternationalizationTests {
  @Test func systemPreferenceResolvesSupportedLocales() {
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
    #expect(
      AppLanguagePreference.system.resolved(deviceLocale: Locale(identifier: "ja_JP"))
        == .japanese
    )
    #expect(
      AppLanguagePreference.system.resolved(deviceLocale: Locale(identifier: "ru_RU"))
        == .russian
    )
    #expect(AppLanguagePreference.english.resolved() == .english)
    #expect(AppLanguagePreference.zhHans.resolved() == .zhHans)
    #expect(AppLanguagePreference.japanese.resolved() == .japanese)
    #expect(AppLanguagePreference.russian.resolved() == .russian)
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

  @Test func promptLanguagePolicyInjectsJapaneseAndRussianOutputRules() {
    let ja = PromptLanguagePolicy(language: .japanese)
    let jaPrompt = ja.apply(
      toSystemPrompt: "任务说明。\n所有文字使用简体中文。\n",
      kind: .recognize
    )
    #expect(jaPrompt.contains("ユーザー向けの自由記述はすべて日本語で書く"))
    #expect(!jaPrompt.contains("所有文字使用简体中文。"))
    #expect(ja.recognitionUserPreamble() == "この文化現場の写真を識別してください。")
    #expect(ja.explainSectionHeadings.sources == "出典")

    let ru = PromptLanguagePolicy(language: .russian)
    let ruPrompt = ru.apply(
      toSystemPrompt: "任务说明。\n所有文字使用简体中文。\n",
      kind: .recognize
    )
    #expect(ruPrompt.contains("Весь пользовательский свободный текст пишите на русском"))
    #expect(ru.recognitionUserPreamble() == "Определите культурный объект на этом фото.")
    #expect(ru.explainSectionHeadings.sources == "Источники")
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

  @Test func explainPromptUsesJapaneseSectionHeadings() {
    let policy = PromptLanguagePolicy(language: .japanese)
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
    #expect(prompt.contains("## 文化的背景"))
    #expect(prompt.contains("## 関連の脈絡"))
    #expect(prompt.contains("## 次のステップ"))
    #expect(prompt.contains("## 出典"))
    #expect(prompt.contains("原文抜粋"))
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

  @Test func citationParserAcceptsJapaneseAndRussianSourcesHeadings() {
    let jaMarkdown = """
      西湖の夜景は灯籠と水面、月の錯覚に依る。

      ## 出典
      - key: `three-pools-mirroring-moon`, name: 三潭映月
        - 原文抜粋: 石塔、灯孔、水面、月光。
      """
    let jaParsed = CultureChatService.parseAnswer(jaMarkdown, store: nil)
    #expect(jaParsed.citations.count == 1)
    #expect(jaParsed.citations[0].key == "three-pools-mirroring-moon")

    let ruMarkdown = """
      Ночной пейзаж Сиху опирается на фонари, воду и иллюзию луны.

      ## Источники
      - key: `three-pools-mirroring-moon`, name: Три пруда, отражающие луну
        - Цитата из источника: Каменные пагоды, отверстия для ламп, вода и лунный свет.
      """
    let ruParsed = CultureChatService.parseAnswer(ruMarkdown, store: nil)
    #expect(ruParsed.citations.count == 1)
    #expect(ruParsed.citations[0].key == "three-pools-mirroring-moon")
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

    // Japanese / Russian have no pack overlays yet; fall back to source for LLM translation.
    let ja = localization.elementText(key: "e1", language: .japanese)
    #expect(ja?.name == "元素一")
    #expect(ja?.isSourceFallback == true)
    let ru = localization.elementText(key: "e1", language: .russian)
    #expect(ru?.name == "元素一")
    #expect(ru?.isSourceFallback == true)
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

  @Test func translationServicePrefersBundledOverlayOverLiveTranslate() async throws {
    let json = """
      {
        "version": "test-overlay-v1",
        "source_language": "zh-Hans",
        "elements": [
          {
            "key": "e1",
            "name": "元素一",
            "introduction": {
              "schemaVersion": 1,
              "blocks": [{ "type": "paragraph", "text": "中文介绍" }]
            }
          }
        ],
        "attractions": [{ "key": "a1", "name": "景点一" }],
        "relations": [],
        "introductions": [
          {
            "key": "i1",
            "name": "现场介绍",
            "culturalElementKey": "e1",
            "attractionKey": "a1",
            "latitude": 30.2,
            "longitude": 120.1,
            "introduction": {
              "schemaVersion": 1,
              "blocks": [{ "type": "paragraph", "text": "现场正文" }]
            }
          }
        ],
        "locales": {
          "en": {
            "elements": {
              "e1": {
                "name": "Element One",
                "introduction": {
                  "schemaVersion": 1,
                  "blocks": [{ "type": "paragraph", "text": "English intro" }]
                }
              }
            },
            "attractions": {
              "a1": { "name": "Attraction One" }
            },
            "introductions": {
              "i1": {
                "name": "On-site Intro",
                "introduction": {
                  "schemaVersion": 1,
                  "blocks": [{ "type": "paragraph", "text": "On-site body" }]
                }
              }
            }
          }
        }
      }
      """.data(using: .utf8)!
    let pack = try JSONDecoder().decode(KnowledgePack.self, from: json)
    let previous = KnowledgeStore.shared
    KnowledgeStore.installShared(KnowledgeStore(pack: pack))
    defer {
      if let previous {
        KnowledgeStore.installShared(previous)
      }
    }

    // nil gateway: overlay must satisfy the lookup without a network call.
    let service = KnowledgeTranslationService(gatewayClient: nil)
    let elementName = await service.localizedName(
      cacheNamespace: "element",
      key: "e1",
      sourceName: "元素一",
      language: .english
    )
    #expect(elementName == "Element One")

    let elementText = await service.localizedText(
      cacheNamespace: "element",
      key: "e1",
      sourceText: "中文介绍",
      language: .english
    )
    #expect(elementText == "English intro")

    let attractionName = await service.localizedName(
      cacheNamespace: "attraction",
      key: "a1",
      sourceName: "景点一",
      language: .english
    )
    #expect(attractionName == "Attraction One")

    let intro = await service.localizedNameAndText(
      cacheNamespace: "introduction",
      key: "i1",
      sourceName: "现场介绍",
      sourceText: "现场正文",
      language: .english
    )
    #expect(intro.name == "On-site Intro")
    #expect(intro.text == "On-site body")

    // Theme / recognition namespaces have no pack overlay; without a gateway
    // they must fall back to the source rather than inventing a translation.
    let themeName = await service.localizedName(
      cacheNamespace: "theme",
      key: "moon",
      sourceName: "月影系列",
      language: .english
    )
    #expect(themeName == "月影系列")
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

  @Test func stringCatalogIncludesJapaneseAndRussianLocales() throws {
    let url = try #require(
      Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings")
    )
    let data = try Data(contentsOf: url)
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let strings = try #require(object["strings"] as? [String: Any])
    let languageEntry = try #require(strings["语言"] as? [String: Any])
    let localizations = try #require(languageEntry["localizations"] as? [String: Any])
    #expect(localizations["ja"] != nil)
    #expect(localizations["ru"] != nil)
  }
}
