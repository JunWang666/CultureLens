import SwiftUI

/// Renders a rich text document block by block: paragraphs as text, image
/// blocks (R2-hosted or other public HTTPS URLs) with loading, failure, retry,
/// accessibility, optional caption, and tap-to-open system Quick Look preview.
struct RichTextBlocksView: View {
  let document: RichTextDocument
  var textFont: Font = CultureTypography.body(.body)
  var textColor: Color = CultureTheme.inkSecondary

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
        if let text = block.text, !text.isEmpty {
          Text(text)
            .font(textFont)
            .foregroundStyle(textColor)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if block.imageURL != nil {
          RemoteKnowledgeImageView(block: block)
        }
      }
    }
  }
}

private struct RemoteKnowledgeImageView: View {
  let block: RichTextDocument.Block

  @State private var retryID = 0
  @State private var isPreparingPreview = false
  @State private var previewItem: SystemImagePreviewItem?
  @State private var previewFileURLForCleanup: URL?
  @State private var previewErrorMessage: String?

  private var caption: String? {
    guard let caption = block.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
      !caption.isEmpty
    else {
      return nil
    }
    return caption
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedAsyncImage(
        url: block.imageURL,
        transaction: Transaction(animation: .easeOut(duration: 0.2))
      ) { phase in
        switch phase {
        case .success(let image):
          Button {
            Task { await openSystemPreview() }
          } label: {
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: .infinity)
              .overlay {
                if isPreparingPreview {
                  ZStack {
                    Color.black.opacity(0.28)
                    ProgressView()
                      .controlSize(.regular)
                      .tint(.white)
                  }
                }
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .disabled(isPreparingPreview || block.imageURL == nil)
          .transition(.opacity)
          .accessibilityLabel(Text(caption ?? String(localized: "图片")))
          .accessibilityHint(Text("点击全屏查看"))
          .accessibilityAddTraits(.isButton)
        case .failure:
          VStack(spacing: 12) {
            Image(systemName: "photo.badge.exclamationmark")
              .font(.title2)
            Text("图片加载失败")
              .font(.caption)
            Button("重试") {
              retryID += 1
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
          .foregroundStyle(CultureTheme.inkSecondary)
          .frame(maxWidth: .infinity, minHeight: 180)
          .accessibilityElement(children: .contain)
        case .empty:
          ProgressView()
            .controlSize(.regular)
            .frame(maxWidth: .infinity, minHeight: 180)
        @unknown default:
          EmptyView()
        }
      }
      .id(retryID)
      .frame(maxWidth: .infinity)
      .background(CultureTheme.surface)
      .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }

      if let caption {
        Text(caption)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background {
      SystemImageQuickLookPresenter(item: $previewItem)
    }
    .onChange(of: previewItem?.id) { _, newID in
      if newID == nil {
        cleanupPreviewFile()
      }
    }
    .alert(
      "无法准备图片",
      isPresented: Binding(
        get: { previewErrorMessage != nil },
        set: { if !$0 { previewErrorMessage = nil } }
      )
    ) {
      Button("好", role: .cancel) {
        previewErrorMessage = nil
      }
    } message: {
      Text(previewErrorMessage ?? "")
    }
  }

  @MainActor
  private func openSystemPreview() async {
    guard let remoteURL = block.imageURL, !isPreparingPreview else { return }
    isPreparingPreview = true
    defer { isPreparingPreview = false }

    do {
      let fileURL = try await SystemImagePreviewPreparer.prepareTemporaryFile(from: remoteURL)
      SystemImagePreviewPreparer.removeTemporaryFile(previewFileURLForCleanup)
      previewFileURLForCleanup = fileURL
      previewItem = SystemImagePreviewItem(fileURL: fileURL)
    } catch {
      previewErrorMessage = String(localized: "图片预览准备失败，请稍后重试。")
    }
  }

  private func cleanupPreviewFile() {
    let fileURL = previewFileURLForCleanup
    previewFileURLForCleanup = nil
    // Delay so Quick Look can finish its dismiss animation before the file vanishes.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      SystemImagePreviewPreparer.removeTemporaryFile(fileURL)
    }
  }
}
