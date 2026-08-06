import SwiftUI

struct DidYouKnowQuizSection: View {
  let elements: [KnowledgePack.Element]

  @Environment(AppLanguageStore.self) private var languageStore
  @State private var quizOffset = 0
  @State private var retryID = UUID()
  @State private var state: LoadState = .idle
  @State private var selectedIndex: Int?

  private let service: DidYouKnowQuizService

  init(
    elements: [KnowledgePack.Element],
    service: DidYouKnowQuizService = .shared
  ) {
    self.elements = elements
    self.service = service
  }

  private var orderedElements: [KnowledgePack.Element] {
    elements.sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
  }

  private var currentElement: KnowledgePack.Element? {
    let ordered = orderedElements
    guard !ordered.isEmpty else { return nil }
    return ordered[(dailyStartIndex(in: ordered) + quizOffset) % ordered.count]
  }

  private var loadID: String {
    "\(currentElement?.id.uuidString ?? "empty")|\(languageStore.language.rawValue)|\(retryID)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeader
      content
    }
    .task(id: loadID) {
      await loadQuiz()
    }
    .accessibilityIdentifier("explore.didYouKnow")
  }

  private var sectionHeader: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      MagazineSectionHeader(
        eyebrow: "DID YOU KNOW",
        "你知道吗？",
        subtitle: "从遇见过的文化里，看看你还记得多少"
      )

      Spacer(minLength: 8)

      if orderedElements.count > 1 {
        Button {
          selectedIndex = nil
          state = .loading
          quizOffset = (quizOffset + 1) % orderedElements.count
        } label: {
          Label("换一题", systemImage: "shuffle")
            .font(.caption.weight(.semibold))
        }
        .tint(CultureTheme.cinnabar)
        .accessibilityIdentifier("explore.didYouKnow.next")
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch state {
    case .idle, .loading:
      loadingView
    case .empty:
      emptyView
    case .loaded(let quiz):
      quizView(quiz)
    case .failed(let message):
      failedView(message)
    }
  }

  private var loadingView: some View {
    VStack(alignment: .leading, spacing: 10) {
      SkeletonLine(height: 13, widthFraction: 0.34)
      SkeletonLine(height: 22, widthFraction: 0.92)
      SkeletonLine(height: 22, widthFraction: 0.68)
      SkeletonLine(height: 44, widthFraction: 1)
      SkeletonLine(height: 44, widthFraction: 1)
      SkeletonLine(height: 44, widthFraction: 1)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("正在准备文化问题")
  }

  private var emptyView: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "questionmark.bubble")
        .foregroundStyle(CultureTheme.cinnabar)
        .frame(width: 24)
      Text("先去认识一个文化节点，回来我再考考你。")
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private func failedView(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("暂时出不了题", systemImage: "wifi.exclamationmark")
        .font(CultureTypography.title(.headline))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(message)
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
      Button("重试") {
        retryID = UUID()
      }
      .buttonStyle(.bordered)
      .tint(CultureTheme.cinnabar)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func quizView(_ quiz: DidYouKnowQuiz) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sourceLink(for: quiz)
        .padding(.bottom, 12)

      Text(quiz.question)
        .font(CultureTypography.title(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 16)

      ForEach(quiz.options.indices, id: \.self) { index in
        if index > 0 { EditorialRule() }
        answerButton(index: index, quiz: quiz)
      }

      if let selectedIndex {
        EditorialRule()
          .padding(.top, 4)
        answerExplanation(quiz: quiz, selectedIndex: selectedIndex)
          .padding(.top, 14)
      }
    }
  }

  private func sourceLink(for quiz: DidYouKnowQuiz) -> some View {
    NavigationLink(value: AppRoute.knowledgeElement(quiz.elementID)) {
      HStack(spacing: 7) {
        Text("来自你遇到过的节点")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
        Text(verbatim: "·")
          .foregroundStyle(CultureTheme.hairline)
        LocalizedPackText(
          source: quiz.elementName,
          cacheNamespace: "didYouKnow.elementName",
          cacheKey: quiz.elementID.uuidString
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.cinnabar)
        .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.bold))
          .foregroundStyle(CultureTheme.cinnabar)
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("打开这个文化节点的详情")
  }

  private func answerButton(index: Int, quiz: DidYouKnowQuiz) -> some View {
    let isAnswered = selectedIndex != nil
    let isSelected = selectedIndex == index
    let isCorrect = quiz.correctIndex == index

    return Button {
      guard selectedIndex == nil else { return }
      withAnimation(.easeOut(duration: 0.2)) {
        selectedIndex = index
      }
    } label: {
      HStack(alignment: .center, spacing: 12) {
        Text(optionLetter(index))
          .font(.caption.monospaced().weight(.bold))
          .foregroundStyle(
            optionAccent(isAnswered: isAnswered, isSelected: isSelected, isCorrect: isCorrect)
          )
          .frame(width: 28, height: 28)
          .overlay {
            Circle()
              .stroke(
                optionAccent(
                  isAnswered: isAnswered,
                  isSelected: isSelected,
                  isCorrect: isCorrect
                ).opacity(0.55),
                lineWidth: 1
              )
          }

        Text(quiz.options[index])
          .font(CultureTypography.body(.body))
          .foregroundStyle(CultureTheme.inkPrimary)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)

        Spacer(minLength: 8)

        if isAnswered, isCorrect {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(CultureTheme.cinnabar)
        } else if isSelected {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(CultureTheme.inkSecondary)
        }
      }
      .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("选项 \(optionLetter(index))，\(quiz.options[index])")
    .accessibilityValue(
      answerAccessibilityValue(
        isAnswered: isAnswered,
        isSelected: isSelected,
        isCorrect: isCorrect
      ))
  }

  private func answerExplanation(
    quiz: DidYouKnowQuiz,
    selectedIndex: Int
  ) -> some View {
    let isCorrect = selectedIndex == quiz.correctIndex
    return VStack(alignment: .leading, spacing: 8) {
      Label(
        isCorrect ? "答对了" : "再认识一下",
        systemImage: isCorrect ? "checkmark.seal.fill" : "book.pages"
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(isCorrect ? CultureTheme.cinnabar : CultureTheme.inkPrimary)

      Text(quiz.explanation)
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .transition(.opacity.combined(with: .move(edge: .top)))
    .accessibilityElement(children: .combine)
  }

  @MainActor
  private func loadQuiz() async {
    guard let element = currentElement else {
      state = .empty
      selectedIndex = nil
      return
    }

    state = .loading
    selectedIndex = nil
    do {
      let quiz = try await service.quiz(for: element, language: languageStore.language)
      guard !Task.isCancelled, quiz.elementID == currentElement?.id else { return }
      state = .loaded(quiz)
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      state = .failed(error.localizedDescription)
    }
  }

  private func dailyStartIndex(in ordered: [KnowledgePack.Element]) -> Int {
    guard !ordered.isEmpty else { return 0 }
    let day = Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0
    let identitySeed = ordered.reduce(0) { partial, element in
      element.id.uuidString.utf8.reduce(partial) { ($0 + Int($1)) % ordered.count }
    }
    return (day + identitySeed) % ordered.count
  }

  private func optionLetter(_ index: Int) -> String {
    ["A", "B", "C"][index]
  }

  private func optionAccent(
    isAnswered: Bool,
    isSelected: Bool,
    isCorrect: Bool
  ) -> Color {
    if isAnswered, isCorrect { return CultureTheme.cinnabar }
    if isSelected { return CultureTheme.inkSecondary }
    return CultureTheme.antiqueGold
  }

  private func answerAccessibilityValue(
    isAnswered: Bool,
    isSelected: Bool,
    isCorrect: Bool
  ) -> String {
    guard isAnswered else { return String(localized: "未选择") }
    if isCorrect { return String(localized: "正确答案") }
    if isSelected { return String(localized: "你的答案，不正确") }
    return String(localized: "未选择")
  }

  private enum LoadState {
    case idle
    case loading
    case empty
    case loaded(DidYouKnowQuiz)
    case failed(String)
  }
}
