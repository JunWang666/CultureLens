import SwiftUI

struct ObjectDetailView: View {
    let object: CultureObject

    @State private var isBookmarked = false

    var body: some View {
        ZStack {
            CulturePageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ObjectArtwork(object: object, height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    identity
                    relationSection

                    NavigationLink(value: AppRoute.ask(object.id)) {
                        Label("继续追问这个对象", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.inkPrimary)
                    .controlSize(.large)

                    KnowledgeUnderstandingButton(
                        nodeID: object.id,
                        presentation: .fullWidth
                    )
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.vertical, 18)
            }
        }
        .navigationTitle(object.canonicalName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isBookmarked.toggle()
                } label: {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .accessibilityLabel(isBookmarked ? "取消收藏" : "收藏")

                KnowledgeUnderstandingButton(
                    nodeID: object.id,
                    presentation: .toolbar
                )

                ShareLink(item: "\(object.canonicalName)：\(object.summary)") {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享")
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已识别 · \(object.confidence, format: .percent.precision(.fractionLength(0)))", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            Text(object.canonicalName)
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)

            Text([object.category.rawValue, object.timePeriod, object.region].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(CultureTheme.inkSecondary)

            Text(object.summary)
                .font(.title3)
                .foregroundStyle(CultureTheme.inkPrimary)
                .lineSpacing(6)
        }
    }

    private var relationSection: some View {
        CultureRelationGraphView(object: object)
    }

}

#Preview {
    NavigationStack {
        ObjectDetailView(object: SampleCultureData.featured)
    }
    .environment(KnowledgeProgressStore())
}
