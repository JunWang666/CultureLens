import Combine
import SwiftUI
import SwiftStreamingMarkdown

struct AskCultureView: View {
  let object: CultureObject?
  var rationale: String = ""

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @StateObject private var model = AskCultureChatModel()
  @FocusState private var isComposerFocused: Bool

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
    .navigationTitle(isGeneralChat ? "文化问答" : (object?.canonicalName ?? "继续追问"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) {
        VStack(spacing: 2) {
          Text(isGeneralChat ? "文化问答" : (object?.canonicalName ?? "继续追问"))
            .font(.headline)
          Text("知识库约束 · 流式回答")
            .font(.caption2)
            .foregroundStyle(CultureTheme.inkSecondary)
        }
      }
    }
    .onAppear {
      model.configure(
        object: object,
        rationale: rationale,
        chatService: chatService,
        knowledgeProgressStore: knowledgeProgressStore
      )
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
        withAnimation(.easeOut(duration: 0.2)) {
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
          ? "回答会流式渲染，并尽量标注知识库引用来源。"
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

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
        Group {
          switch message.role {
          case .user:
            Text(message.text)
              .font(.body)
              .foregroundStyle(.white)
              .multilineTextAlignment(.leading)
          case .assistant:
            if let source = message.streamSource, message.isStreaming {
              StreamedMarkdownView(source: source, config: Self.markdownConfig)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          message.role == .user
            ? CultureTheme.cinnabar
            : CultureTheme.surface,
          in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
          if message.role == .assistant {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .stroke(CultureTheme.hairline, lineWidth: 1)
          }
        }

        if message.role == .assistant, !message.citations.isEmpty, !message.isStreaming {
          citationStrip(message.citations)
        }
      }

      if message.role == .assistant { Spacer(minLength: 36) }
    }
  }

  private func citationStrip(_ citations: [KnowledgeCitation]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("引用来源")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
      ForEach(citations.prefix(4)) { citation in
        Text("\(citation.name) · \(citation.key)")
          .font(.caption2.weight(.semibold))
        Text(citation.fragment)
          .font(.caption2)
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineLimit(3)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.antiqueGold.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
  }

  private var composer: some View {
    VStack(spacing: 0) {
      Divider().overlay(CultureTheme.hairline)
      HStack(alignment: .bottom, spacing: 10) {
        TextField(
          isGeneralChat ? "问一个文化问题" : "问一个关于它的问题",
          text: $model.draft,
          axis: .vertical
        )
        .focused($isComposerFocused)
        .lineLimit(1...5)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
          CultureTheme.surface,
          in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .disabled(chatService == nil || model.isSending)

        Button {
          Task { await model.send() }
        } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 32))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(
              model.canSend ? CultureTheme.cinnabar : CultureTheme.inkSecondary.opacity(0.35)
            )
        }
        .disabled(!model.canSend)
        .accessibilityLabel("发送")
      }
      .padding(.horizontal, CultureTheme.pagePadding)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
    }
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: true)
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

    errorMessage = nil
    isSending = true
    draft = ""

    let history = messages.map {
      ChatTurn(role: $0.role == .user ? .user : .assistant, content: $0.text)
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
        streamSource: source
      )
    )
    bumpScroll()

    do {
      var finalText = ""
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
        case .delta(let snapshot):
          finalText = snapshot
          source.yield(snapshot)
          updateAssistant(id: assistantID) { message in
            message.text = snapshot
          }
          bumpScroll()
        case .finished(_, let content):
          finalText = content
          source.yield(content)
          source.finish()
          updateAssistant(id: assistantID) { message in
            message.text = content
            message.isStreaming = false
            message.streamSource = nil
            message.citations = CultureChatService.extractCitations(from: content)
          }
          bumpScroll()
        }
      }

      if let object, let key = object.culturalElementKey {
        let current = knowledgeProgressStore.level(for: object.id)
        if current == nil || current == .contact {
          knowledgeProgressStore.setLevel(
            .understand,
            for: object.id,
            source: .ask,
            elementKey: key
          )
        }
      }
      _ = finalText
    } catch {
      source.finish()
      messages.removeAll { $0.id == assistantID && $0.text.isEmpty }
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
  var streamSource: GrowingMarkdownSource?
  var citations: [KnowledgeCitation]

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    isStreaming: Bool = false,
    streamSource: GrowingMarkdownSource? = nil,
    citations: [KnowledgeCitation] = []
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.isStreaming = isStreaming
    self.streamSource = streamSource
    self.citations = citations
  }

  static func == (lhs: AskChatMessage, rhs: AskChatMessage) -> Bool {
    lhs.id == rhs.id
      && lhs.role == rhs.role
      && lhs.text == rhs.text
      && lhs.isStreaming == rhs.isStreaming
      && lhs.citations == rhs.citations
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
