import SwiftUI

struct ConceptDetailView: View {
    let concept: CultureConcept

    var body: some View {
        ZStack {
            CulturePageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
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
                    }

                    if let detail = concept.distinctDetail {
                        Divider()

                        Text(detail)
                            .font(.body)
                            .foregroundStyle(CultureTheme.inkSecondary)
                            .lineSpacing(7)

                        Label("文化札记", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundStyle(CultureTheme.inkSecondary)
                    }

                    KnowledgeUnderstandingButton(
                        nodeID: concept.id,
                        presentation: .fullWidth
                    )
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.vertical, 32)
                .frame(maxWidth: 680, alignment: .leading)
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
