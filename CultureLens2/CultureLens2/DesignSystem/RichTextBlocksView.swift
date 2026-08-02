import SwiftUI

/// Renders a rich text document block by block: paragraphs as text, image
/// blocks (R2-hosted URLs) via `AsyncImage` with an optional caption.
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
        } else if let imageURL = block.imageURL {
          VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: imageURL) { phase in
              switch phase {
              case .success(let image):
                image
                  .resizable()
                  .scaledToFit()
              case .failure:
                Label("图片加载失败", systemImage: "photo")
                  .font(.caption)
                  .foregroundStyle(CultureTheme.inkSecondary)
                  .frame(maxWidth: .infinity, minHeight: 120)
              default:
                ProgressView()
                  .frame(maxWidth: .infinity, minHeight: 120)
              }
            }
            .background(CultureTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
            .overlay {
              RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
                .stroke(CultureTheme.hairline, lineWidth: 1)
            }

            if let caption = block.caption, !caption.isEmpty {
              Text(caption)
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)
            }
          }
        }
      }
    }
  }
}
