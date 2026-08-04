import SwiftUI

struct ConceptDetailView: View {
    let concept: CultureConcept
    var elementKey: String? = nil

    private var resolvedElementKey: String? {
        elementKey
            ?? KnowledgeStore.shared?.elementKey(for: concept.id)
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            SplitDetailLayout(topPadding: 32, bottomPadding: 32, contentMaxWidth: 680) { _ in
                Image(systemName: concept.kind.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(CultureTheme.cinnabar)

                Text(concept.kind.localizedTitle)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(CultureTheme.cinnabar)

                Text(concept.name)
                    .font(.cultureSerif(.largeTitle))
                    .foregroundStyle(CultureTheme.inkPrimary)

                LocalizedKnowledgeBlocksView(
                    elementKey: resolvedElementKey,
                    fallbackName: concept.name,
                    fallbackSummary: concept.summary
                )
            } trailing: { _ in
                if resolvedElementKey == nil, let detail = concept.distinctDetail {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(CultureTheme.inkSecondary)
                            .lineSpacing(7)

                        Label("文化札记", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(CultureTheme.inkSecondary)
                    }
                }

                KnowledgeGraphMembershipButton(
                    nodeID: concept.id,
                    elementKey: resolvedElementKey,
                    presentation: .fullWidth
                )
            }
        }
        .cultureNavigationTitle(concept.name)
    }
}

#Preview {
    NavigationStack {
        ConceptDetailView(concept: SampleCultureData.featured.concepts[0])
    }
    .environment(KnowledgeProgressStore())
    .environment(AppLanguageStore())
}
