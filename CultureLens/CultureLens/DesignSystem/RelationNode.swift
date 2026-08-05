import SwiftUI

struct RelationNode: View {
    let concept: CultureConcept

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: concept.kind.systemImage)
                .font(.title3)
                .foregroundStyle(CultureTheme.cinnabar)
                .frame(width: 52, height: 52)
                .background(CultureTheme.canvas, in: Circle())
                .overlay {
                    Circle().stroke(CultureTheme.antiqueGold.opacity(0.6), lineWidth: 1)
                }

            Text(concept.kind.localizedTitle)
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)

            LocalizedPackText(
                source: concept.name,
                cacheNamespace: "element",
                cacheKey: KnowledgeStore.shared?.elementKey(for: concept.id)
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CultureTheme.inkPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
        }
        .frame(width: 112, height: 150)
        .padding(.vertical, 8)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("查看这个文化关系")
    }
}
