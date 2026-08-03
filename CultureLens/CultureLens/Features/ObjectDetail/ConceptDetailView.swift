import SwiftUI

struct ConceptDetailView: View {
    let concept: CultureConcept

    var body: some View {
        ZStack {
            CulturePageBackground()

            SplitDetailLayout(topPadding: 32, bottomPadding: 32, contentMaxWidth: 680) { _ in
                Image(systemName: concept.kind.systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(CultureTheme.cinnabar)

                Text(concept.kind.rawValue)
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(CultureTheme.cinnabar)

                Text(concept.name)
                    .font(.cultureSerif(.largeTitle))
                    .foregroundStyle(CultureTheme.inkPrimary)

                Text(concept.summary)
                    .font(.title3)
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .lineSpacing(6)
            } trailing: { _ in
                if let detail = concept.distinctDetail {
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

                KnowledgeUnderstandingButton(
                    nodeID: concept.id,
                    presentation: .fullWidth
                )
            }
        }
        .navigationTitle(concept.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ConceptDetailView(concept: SampleCultureData.featured.concepts[0])
    }
    .environment(KnowledgeProgressStore())
}
