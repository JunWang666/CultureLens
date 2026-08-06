import SwiftUI

/// Renders a rich text document block by block: paragraphs as text, image
/// blocks (R2-hosted or other public HTTPS URLs) with loading, failure, retry,
/// accessibility, and an optional caption.
struct RichTextBlocksView: View {
  let document: RichTextDocument
  var textFont: Font = .body
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
      AsyncImage(
        url: block.imageURL,
        transaction: Transaction(animation: .easeOut(duration: 0.2))
      ) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .accessibilityLabel(Text(caption ?? ""))
            .accessibilityHidden(caption == nil)
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
  }
}
