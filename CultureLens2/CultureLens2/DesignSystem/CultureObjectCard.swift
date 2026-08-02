import SwiftUI

struct CultureObjectCard: View {
    let object: CultureObject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ObjectArtwork(object: object, height: 132)

            VStack(alignment: .leading, spacing: 8) {
                Text(object.canonicalName)
                    .font(.cultureSerif(.title3))
                    .foregroundStyle(CultureTheme.inkPrimary)

                Text([object.timePeriod, object.region].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(CultureTheme.cinnabar)
                    .lineLimit(1)

                Text(object.summary)
                    .font(.subheadline)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .background(CultureTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开文化对象详情")
    }
}
