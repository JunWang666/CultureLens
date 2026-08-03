import Combine
import SwiftUI
import SwiftStreamingMarkdown
import UIKit

struct AskCultureView: View {
  let object: CultureObject?
  var rationale: String = ""

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @StateObject private var model = AskCultureChatModel()
  @FocusState private var isComposerFocused: Bool
  @State private var composerTextHeight: CGFloat = 36
  @State private var selectedCitationKey: String?

  private var isGeneralChat: Bool { object == nil }
  private let chatService = CultureChatService.live()

  var body: some View {
    ZStack {
      CulturePageBackground()

      VStack(spacing: 0) {
        messageList
        composer
      }
    }
    .cultureNavigationTitle(
      isGeneralChat ? "文化问答" : (object?.canonicalName ?? "继续追问"),
      subtitle: model.isSending
        ? (model.messages.last?.isThinking == true ? "正在思考…" : "正在流式回答…")
        : "知识库约束"
    )
    .onAppear {
      model.configure(
        object: object,
        rationale: rationale,
        chatService: chatService,
        knowledgeProgressStore: knowledgeProgressStore
      )
    }
    .environment(\.openURL, OpenURLAction { url in
      if let key = CultureCiteURL.elementKey(from: url) {
        selectedCitationKey = key
        return .handled
      }
      return .systemAction(url)
    })
    .navigationDestination(item: $selectedCitationKey) { key in
      if let concept = KnowledgeStore.shared?.cultureConcept(elementKey: key) {
        ConceptDetailView(concept: concept, elementKey: key)
      } else {
        ContentUnavailableView("知识节点暂不可用", systemImage: "externaldrive.badge.questionmark")
      }
    }
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if model.messages.isEmpty {
            emptyState
              .padding(.top, 8)
          }

          ForEach(model.messages) { message in
            chatBubble(message)
              .id(message.id)
          }

          if let errorMessage = model.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(CultureTheme.cinnabar)
              .padding(.horizontal, 4)
              .id("error")
          }

          Color.clear.frame(height: 8).id("bottom")
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: model.scrollTick) { _, _ in
        withAnimation(.easeOut(duration: 0.18)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isGeneralChat ? "从知识库问起" : "继续追问这个对象")
        .font(.cultureSerif(.title2))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(
        isGeneralChat
          ? "回答会流式渲染，引用整理成卡片展示。"
          : "围绕当前对象与图谱邻居提问；内容约束在知识库片段内。"
      )
      .font(.subheadline)
      .foregroundStyle(CultureTheme.inkSecondary)

      FlowSuggestionRow(suggestions: model.suggestions) { text in
        model.draft = text
        isComposerFocused = true
        Task { await model.send() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private func chatBubble(_ message: AskChatMessage) -> some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.role == .user { Spacer(minLength: 36) }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
        Group {
          switch message.role {
          case .user:
            Text(message.text)
              .font(.body)
              .foregroundStyle(.white)
              .multilineTextAlignment(.leading)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .background(
                CultureTheme.cinnabar,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
              )
          case .assistant:
            assistantContent(message)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                CultureTheme.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .stroke(CultureTheme.hairline, lineWidth: 1)
              }
          }
        }

        if message.role == .assistant, !message.citations.isEmpty, !message.isStreaming {
          KnowledgeCitationCardsView(citations: message.citations) { citation in
            selectedCitationKey = citation.key
          }
        }
      }

      if message.role == .assistant { Spacer(minLength: 36) }
    }
  }

  @ViewBuilder
  private func assistantContent(_ message: AskChatMessage) -> some View {
    if message.isStreaming, message.isThinking {
      ThinkingStatusView()
    } else if let source = message.streamSource, message.isStreaming {
      // Stable identity: do not recreate this view while tokens arrive.
      StreamedMarkdownView(source: source, config: Self.markdownConfig)
        .id("stream-\(message.id)")
    } else if !message.text.isEmpty {
      MarkdownView(text: message.text, config: Self.markdownConfig)
    } else {
      HStack(spacing: 8) {
        ProgressView()
        Text("正在组织回答…")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }
    }
  }

  /// ChatGPT-style pill composer: + | field | microphone | voice/send.
  private var composer: some View {
    VStack(spacing: 0) {
      HStack(alignment: .bottom, spacing: 8) {
        Button {
          isComposerFocused = true
          if model.draft.isEmpty, let first = model.suggestions.first {
            model.draft = first
          }
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(CultureTheme.inkPrimary)
            .frame(width: 34, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("快捷提问")

        ChatComposerTextView(
          text: $model.draft,
          isFocused: Binding(
            get: { isComposerFocused },
            set: { isComposerFocused = $0 }
          ),
          measuredHeight: $composerTextHeight,
          placeholder: isGeneralChat ? "询问 CultureLens" : "继续追问…",
          isEnabled: chatService != nil && !model.isSending,
          onSend: {
            Task { await model.send() }
          }
        )
        .frame(height: composerTextHeight)

        Button {
          isComposerFocused = true
        } label: {
          Image(systemName: "mic")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(CultureTheme.inkPrimary)
            .frame(width: 34, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chatService == nil || model.isSending)
        .accessibilityLabel("语音输入")
        .accessibilityHint("打开输入框后可使用系统听写")

        Button {
          if model.canSend {
            Task { await model.send() }
          } else {
            isComposerFocused = true
          }
        } label: {
          ZStack {
            Circle()
              .fill(Color(red: 0.02, green: 0.47, blue: 0.98))

            if model.canSend {
              Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
              ChatVoiceWaveformIcon()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
          }
          .frame(width: 36, height: 36)
          .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(chatService == nil || model.isSending)
        .accessibilityLabel(model.canSend ? "发送" : "语音对话")
      }
      .animation(.easeOut(duration: 0.16), value: model.canSend)
      .padding(.leading, 8)
      .padding(.trailing, 7)
      .padding(.vertical, 6)
      .background(
        CultureTheme.surface,
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(CultureTheme.inkPrimary.opacity(0.16), lineWidth: 1)
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 10)
    }
    .background(.ultraThinMaterial)
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: true)
  }
}

private struct ChatVoiceWaveformIcon: View {
  private let barHeights: [CGFloat] = [10, 17, 24, 17, 10]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
        Capsule()
          .fill(.white)
          .frame(width: 2.5, height: height)
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Model

@MainActor
final class AskCultureChatModel: ObservableObject {
  @Published var messages: [AskChatMessage] = []
  @Published var draft = ""
  @Published var isSending = false
  @Published var errorMessage: String?
  @Published var scrollTick = 0

  private var object: CultureObject?
  private var rationale = ""
  private var chatService: CultureChatService?
  private weak var knowledgeProgressStore: KnowledgeProgressStore?
  private var streamTask: Task<Void, Never>?

  var suggestions: [String] {
    if object == nil {
      return [
        "西湖十景是怎样被命名的？",
        "三潭映月和苏轼有什么关系？",
        "我已经了解的节点还能怎样串联？",
      ]
    }
    return [
      "它为什么会形成这样的结构？",
      "在不同地区有什么变化？",
      "我还能在哪里看到相似对象？",
    ]
  }

  var canSend: Bool {
    chatService != nil
      && !isSending
      && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func configure(
    object: CultureObject?,
    rationale: String,
    chatService: CultureChatService?,
    knowledgeProgressStore: KnowledgeProgressStore
  ) {
    self.object = object
    self.rationale = rationale
    self.chatService = chatService
    self.knowledgeProgressStore = knowledgeProgressStore
  }

  func send() async {
    guard let chatService, let knowledgeProgressStore else {
      errorMessage = "追问服务暂不可用。"
      return
    }
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard !isSending else { return }

    errorMessage = nil
    isSending = true
    draft = ""

    let history = messages.compactMap { message -> ChatTurn? in
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      return ChatTurn(
        role: message.role == .user ? .user : .assistant,
        content: text
      )
    }
    messages.append(AskChatMessage(role: .user, text: trimmed))
    bumpScroll()

    let source = GrowingMarkdownSource()
    let assistantID = UUID()
    messages.append(
      AskChatMessage(
        id: assistantID,
        role: .assistant,
        text: "",
        isStreaming: true,
        isThinking: false,
        streamSource: source
      )
    )
    bumpScroll()

    do {
      var lastScrollCount = 0
      var hasContent = false
      for try await event in chatService.streamAsk(
        object: object,
        rationale: rationale,
        userKnowledgeStates: knowledgeProgressStore.userKnowledgeStates(
          knowledgeStore: KnowledgeStore.shared
        ),
        history: history,
        question: trimmed
      ) {
        switch event {
        case .thinking:
          updateAssistant(id: assistantID) { message in
            message.isThinking = true
          }
          bumpScroll()
        case .delta(let snapshot):
          // Only push into the markdown source — mutating message.text
          // would recreate StreamedMarkdownView and kill the stream.
          if !hasContent {
            hasContent = true
            updateAssistant(id: assistantID) { message in
              message.isThinking = false
            }
          }
          let body = CultureChatService.displayBody(from: snapshot)
          source.yield(body.isEmpty ? snapshot : body)
          if snapshot.count - lastScrollCount > 24 {
            lastScrollCount = snapshot.count
            bumpScroll()
          }
        case .finished(_, let content):
          let parsed = CultureChatService.parseAnswer(content)
          source.yield(parsed.body)
          source.finish()
          updateAssistant(id: assistantID) { message in
            message.text = parsed.body
            message.isStreaming = false
            message.isThinking = false
            message.streamSource = nil
            message.citations = parsed.citations
          }
          bumpScroll()
        }
      }

      if let object, let key = object.culturalElementKey {
        let current = knowledgeProgressStore.level(for: object.id, elementKey: key)
        if current == nil || current == .contact {
          knowledgeProgressStore.setLevel(
            .understand,
            for: object.id,
            source: .ask,
            elementKey: key
          )
        }
      }
    } catch {
      source.finish()
      if let index = messages.firstIndex(where: { $0.id == assistantID }) {
        if messages[index].text.isEmpty {
          messages.remove(at: index)
        } else {
          messages[index].isStreaming = false
          messages[index].streamSource = nil
        }
      }
      errorMessage = error.localizedDescription
    }
    isSending = false
  }

  private func updateAssistant(id: UUID, mutate: (inout AskChatMessage) -> Void) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    mutate(&messages[index])
  }

  private func bumpScroll() {
    scrollTick &+= 1
  }
}

struct AskChatMessage: Identifiable, Equatable {
  enum Role: Equatable {
    case user
    case assistant
  }

  let id: UUID
  let role: Role
  var text: String
  var isStreaming: Bool
  var isThinking: Bool
  var streamSource: GrowingMarkdownSource?
  var citations: [KnowledgeCitation]

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    isStreaming: Bool = false,
    isThinking: Bool = false,
    streamSource: GrowingMarkdownSource? = nil,
    citations: [KnowledgeCitation] = []
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.isStreaming = isStreaming
    self.isThinking = isThinking
    self.streamSource = streamSource
    self.citations = citations
  }

  static func == (lhs: AskChatMessage, rhs: AskChatMessage) -> Bool {
    // Ignore text while streaming so token updates don't rebuild the bubble.
    lhs.id == rhs.id
      && lhs.role == rhs.role
      && lhs.isStreaming == rhs.isStreaming
      && lhs.isThinking == rhs.isThinking
      && (lhs.isStreaming || lhs.text == rhs.text)
      && lhs.citations == rhs.citations
      && (lhs.streamSource == nil) == (rhs.streamSource == nil)
  }
}

/// Animated “正在思考…” while the model streams reasoning_content.
private struct ThinkingStatusView: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.35, paused: false)) { context in
      let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4
      let dots = String(repeating: ".", count: phase)
      HStack(spacing: 10) {
        ThinkingPulseDots()
        Text("正在思考\(dots)")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
          .monospacedDigit()
          .animation(nil, value: phase)
      }
      .accessibilityLabel("正在思考")
    }
  }
}

private struct ThinkingPulseDots: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.28, paused: false)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          let wave = (sin(t * 5.2 + Double(index) * 0.85) + 1) / 2
          Circle()
            .fill(CultureTheme.cinnabar.opacity(0.35 + 0.55 * wave))
            .frame(width: 6, height: 6)
            .scaleEffect(0.75 + 0.45 * wave)
        }
      }
    }
  }
}

/// UIKit field so Return/发送 works with Chinese IME (confirm candidate ≠ send).
private struct ChatComposerTextView: UIViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  @Binding var measuredHeight: CGFloat
  var placeholder: String
  var isEnabled: Bool
  var onSend: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 2)
    view.textContainer.lineFragmentPadding = 0
    view.font = UIFont.preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.returnKeyType = .send
    view.enablesReturnKeyAutomatically = true
    view.autocorrectionType = .yes
    view.spellCheckingType = .no
    view.isScrollEnabled = false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    context.coordinator.placeholderLabel.text = placeholder
    context.coordinator.placeholderLabel.font = view.font
    context.coordinator.placeholderLabel.textColor = UIColor.placeholderText
    context.coordinator.placeholderLabel.numberOfLines = 1
    view.addSubview(context.coordinator.placeholderLabel)
    context.coordinator.placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      context.coordinator.placeholderLabel.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: 2
      ),
      context.coordinator.placeholderLabel.topAnchor.constraint(
        equalTo: view.topAnchor,
        constant: 6
      ),
      context.coordinator.placeholderLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -2
      ),
    ])
    context.coordinator.scheduleHeightUpdate(for: view)
    return view
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self
    if uiView.text != text {
      uiView.text = text
    }
    uiView.isEditable = isEnabled
    uiView.isUserInteractionEnabled = isEnabled
    context.coordinator.placeholderLabel.text = placeholder
    context.coordinator.placeholderLabel.isHidden = !text.isEmpty
    context.coordinator.syncFocus(uiView)
    context.coordinator.scheduleHeightUpdate(for: uiView)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: ChatComposerTextView
    let placeholderLabel = UILabel()

    init(_ parent: ChatComposerTextView) {
      self.parent = parent
    }

    func syncFocus(_ view: UITextView) {
      if parent.isFocused {
        if !view.isFirstResponder { view.becomeFirstResponder() }
      } else if view.isFirstResponder {
        view.resignFirstResponder()
      }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.isFocused = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.isFocused = false
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text ?? ""
      placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
      updateHeight(for: textView)
    }

    func scheduleHeightUpdate(for textView: UITextView) {
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView else { return }
        self.updateHeight(for: textView)
      }
    }

    private func updateHeight(for textView: UITextView) {
      guard textView.bounds.width > 0 else { return }
      textView.isScrollEnabled = false
      let contentHeight = textView.sizeThatFits(
        CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
      ).height
      let nextHeight = min(max(contentHeight, 36), 96)
      textView.isScrollEnabled = contentHeight > 96

      if abs(parent.measuredHeight - nextHeight) > 0.5 {
        parent.measuredHeight = nextHeight
      }
    }

    func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      // Return / 发送: send when not composing IME candidates.
      if text == "\n" {
        if textView.markedTextRange == nil {
          parent.onSend()
        }
        return false
      }
      return true
    }
  }
}

private struct FlowSuggestionRow: View {
  let suggestions: [String]
  let onTap: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(suggestions, id: \.self) { suggestion in
        Button {
          onTap(suggestion)
        } label: {
          Text(suggestion)
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              CultureTheme.canvas.opacity(0.7),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

#Preview("对象追问") {
  NavigationStack {
    AskCultureView(object: SampleCultureData.featured)
  }
  .environment(KnowledgeProgressStore())
}

#Preview("首页问答") {
  NavigationStack {
    AskCultureView(object: nil)
  }
  .environment(KnowledgeProgressStore())
}
