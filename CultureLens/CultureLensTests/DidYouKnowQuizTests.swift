import Foundation
import Testing

@testable import CultureLens

struct DidYouKnowQuizTests {
  @Test func providerJSONIsTrimmedAndValidated() throws {
    let elementID = UUID()
    let quiz = try DidYouKnowQuizService.decodeProviderOutput(
      """
      ```json
      {
        "question": "  三潭印月的石塔如何参与月景营造？  ",
        "options": ["塔内点灯", "种植荷花", "悬挂铜铃"],
        "correct_index": 0,
        "explanation": "  塔内灯光从孔洞透出，与水中月影共同形成景观。  "
      }
      ```
      """,
      elementID: elementID,
      elementName: "三潭印月",
      language: .zhHans,
      modelIdentifier: "test"
    )

    #expect(quiz.question == "三潭印月的石塔如何参与月景营造？")
    #expect(quiz.options == ["塔内点灯", "种植荷花", "悬挂铜铃"])
    #expect(quiz.correctIndex == 0)
    #expect(quiz.explanation.hasPrefix("塔内灯光"))
  }

  @Test func providerJSONRejectsInvalidAnswerContract() {
    let elementID = UUID()
    let invalidPayloads = [
      #"{"question":"题目","options":["甲","乙"],"correct_index":0,"explanation":"解释"}"#,
      #"{"question":"题目","options":["甲","甲","丙"],"correct_index":0,"explanation":"解释"}"#,
      #"{"question":"题目","options":["甲","乙","丙"],"correct_index":3,"explanation":"解释"}"#,
      #"{"question":"","options":["甲","乙","丙"],"correct_index":0,"explanation":"解释"}"#,
    ]

    for payload in invalidPayloads {
      #expect(throws: DidYouKnowQuizError.self) {
        try DidYouKnowQuizService.decodeProviderOutput(
          payload,
          elementID: elementID,
          elementName: "节点",
          language: .zhHans,
          modelIdentifier: "test"
        )
      }
    }
  }

  @Test func repeatedRequestUsesDiskCache() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let counter = QuizGenerationCounter()
    let element = makeElement(text: "石塔设有五个圆孔，塔内点灯后与水中月影相映。")
    let service = DidYouKnowQuizService(
      gatewayClient: nil,
      directoryURL: directory,
      generator: { element, language in
        await counter.increment()
        return Self.quiz(element: element, language: language)
      }
    )

    let first = try await service.quiz(for: element, language: .zhHans)
    let second = try await service.quiz(for: element, language: .zhHans)
    let generationCount = await counter.value

    #expect(first == second)
    #expect(generationCount == 1)
    #expect(await service.diskUsageBytes() > 0)
  }

  @Test func languageAndKnowledgeTextSeparateCacheEntries() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let counter = QuizGenerationCounter()
    let element = makeElement(text: "第一版正文")
    let updatedElement = KnowledgePack.Element(
      id: element.id,
      key: element.key,
      name: element.name,
      introduction: .plain("第二版正文")
    )
    let service = DidYouKnowQuizService(
      gatewayClient: nil,
      directoryURL: directory,
      generator: { element, language in
        await counter.increment()
        return Self.quiz(element: element, language: language)
      }
    )

    _ = try await service.quiz(for: element, language: .zhHans)
    _ = try await service.quiz(for: element, language: .english)
    _ = try await service.quiz(for: updatedElement, language: .zhHans)
    let generationCount = await counter.value

    #expect(generationCount == 3)
    #expect(
      DidYouKnowQuizService.cacheKey(
        elementID: element.id,
        sourceText: "第一版正文",
        language: .zhHans
      )
        != DidYouKnowQuizService.cacheKey(
          elementID: element.id,
          sourceText: "第一版正文",
          language: .english
        )
    )
  }

  private static func quiz(
    element: KnowledgePack.Element,
    language: AppLanguage
  ) -> DidYouKnowQuiz {
    DidYouKnowQuiz(
      elementID: element.id,
      elementName: element.name,
      question: language == .zhHans ? "这是什么？" : "What is this?",
      options: language == .zhHans ? ["甲", "乙", "丙"] : ["A", "B", "C"],
      correctIndex: 0,
      explanation: language == .zhHans ? "来自正文。" : "Grounded in the source.",
      language: language,
      modelIdentifier: "test",
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  private func makeElement(text: String) -> KnowledgePack.Element {
    KnowledgePack.Element(
      id: UUID(),
      key: "quiz-element",
      name: "测试节点",
      introduction: .plain(text)
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: "CultureLensQuizTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }
}

private actor QuizGenerationCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}
