import SwiftUI

struct EditorialHeader: View {
    let eyebrow: String?
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(CultureTheme.cinnabar)
            }

            Text(title)
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)

            Text(message)
                .font(.body)
                .foregroundStyle(CultureTheme.inkSecondary)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
