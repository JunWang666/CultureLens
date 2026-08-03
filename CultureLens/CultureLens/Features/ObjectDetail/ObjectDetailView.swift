import SwiftUI

struct ObjectDetailView: View {
    let object: CultureObject

    private var introductionDocument: RichTextDocument? {
        if let key = object.culturalElementKey {
            return KnowledgeStore.shared?.introductionDocument(elementKey: key)
        }
        return KnowledgeStore.shared?.introductionDocument(nodeID: object.id)
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            SplitDetailLayout(topPadding: 18, bottomPadding: 18) { isWide in
                // 分栏布局下对象名提到左栏顶部
                if isWide {
                    Text(object.canonicalName)
                        .font(.cultureSerif(.largeTitle))
                        .foregroundStyle(CultureTheme.inkPrimary)
                }

                ObjectArtwork(object: object, height: isWide ? 340 : 280)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                identity(showTitle: !isWide)
            } trailing: { _ in
                relationSection

                NavigationLink(value: AppRoute.ask(object.id)) {
                    Label("继续追问这个对象", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CultureTheme.inkPrimary)
                .controlSize(.large)

                KnowledgeGraphMembershipButton(
                    nodeID: object.id,
                    elementKey: object.culturalElementKey,
                    presentation: .fullWidth
                )
            }
        }
        .cultureNavigationTitle(object.canonicalName)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                KnowledgeGraphMembershipButton(
                    nodeID: object.id,
                    elementKey: object.culturalElementKey,
                    presentation: .toolbar
                )

                ShareCultureCardButton(object: object, label: .icon)
            }
        }
    }

    private func identity(showTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已识别 · \(object.confidence, format: .percent.precision(.fractionLength(0)))", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            // 单列布局下对象名显示在这里；分栏时已提到左栏顶部
            if showTitle {
                Text(object.canonicalName)
                    .font(.cultureSerif(.largeTitle))
                    .foregroundStyle(CultureTheme.inkPrimary)
            }

            Text([object.category.rawValue, object.timePeriod, object.region].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(CultureTheme.inkSecondary)

            if let introductionDocument, !introductionDocument.blocks.isEmpty {
                RichTextBlocksView(
                    document: introductionDocument,
                    textFont: .title3,
                    textColor: CultureTheme.inkPrimary
                )
            } else {
                Text(object.summary)
                    .font(.title3)
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .lineSpacing(6)
            }
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
