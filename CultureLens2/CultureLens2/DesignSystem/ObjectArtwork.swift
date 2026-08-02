import SwiftUI

struct ObjectArtwork: View {
    let object: CultureObject
    var height: CGFloat = 210

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    CultureTheme.inkPrimary,
                    CultureTheme.inkPrimary.opacity(0.78),
                    CultureTheme.cinnabar.opacity(0.72),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(CultureTheme.antiqueGold.opacity(0.7), lineWidth: 1)
                .frame(width: height * 0.66, height: height * 0.66)

            Circle()
                .stroke(CultureTheme.antiqueGold.opacity(0.25), lineWidth: 1)
                .frame(width: height * 0.9, height: height * 0.9)

            Image(systemName: object.artworkSymbol)
                .font(.system(size: height * 0.28, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityLabel("\(object.canonicalName)示意图")
    }
}
