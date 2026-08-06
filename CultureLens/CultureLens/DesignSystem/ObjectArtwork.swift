import SwiftUI

/// Poster-style placeholder artwork for objects without a captured photo.
///
/// A flat diagonal color block (ink + cinnabar) with a fine gold seam and an
/// oversized silhouette icon — a deliberately bold "hero" moment, in contrast
/// to the otherwise quiet hairline/serif editorial system used elsewhere.
/// Which corner carries the ink block alternates per object so a grid of
/// cards reads with rhythm instead of repeating the same tile.
struct ObjectArtwork: View {
    let object: CultureObject
    var height: CGFloat = 210

    /// Deterministic per-object toggle for which color leads the field, so a
    /// grid of cards alternates rather than repeating the same tile.
    private var cinnabarDominant: Bool {
        object.id.uuidString.hashValue.magnitude.isMultiple(of: 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let seam = width * 0.4
            let fieldColor = cinnabarDominant ? CultureTheme.cinnabar : CultureTheme.inkPrimary
            let cornerColor = cinnabarDominant ? CultureTheme.inkPrimary : CultureTheme.cinnabar

            ZStack {
                fieldColor

                Path { path in
                    if cinnabarDominant {
                        path.move(to: .zero)
                        path.addLine(to: CGPoint(x: seam, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: height))
                    } else {
                        path.move(to: CGPoint(x: width, y: 0))
                        path.addLine(to: CGPoint(x: width - seam, y: 0))
                        path.addLine(to: CGPoint(x: width, y: height))
                    }
                    path.closeSubpath()
                }
                .fill(cornerColor)

                Path { path in
                    if cinnabarDominant {
                        path.move(to: CGPoint(x: seam, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: height))
                    } else {
                        path.move(to: CGPoint(x: width - seam, y: 0))
                        path.addLine(to: CGPoint(x: width, y: height))
                    }
                }
                .stroke(CultureTheme.antiqueGold.opacity(0.9), lineWidth: 1.5)

                Image(systemName: object.artworkSymbol)
                    .font(.system(size: height * 0.42, weight: .bold))
                    .foregroundStyle(CultureTheme.canvas)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                    .frame(
                        maxWidth: .infinity, maxHeight: .infinity,
                        alignment: cinnabarDominant ? .bottomTrailing : .bottomLeading
                    )
                    .padding(height * 0.12)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .accessibilityLabel("\(object.canonicalName)示意图")
    }
}

#Preview("对象示意图") {
    VStack(spacing: 16) {
        ObjectArtwork(object: .preview(name: "雷峰塔", symbol: "building.columns.fill"))
        HStack(spacing: 16) {
            ObjectArtwork(object: .preview(name: "青铜鼎", symbol: "seal.fill"), height: 132)
            ObjectArtwork(object: .preview(name: "摩崖石刻", symbol: "camera.macro"), height: 132)
        }
    }
    .padding()
    .background(CulturePageBackground())
}

extension CultureObject {
    fileprivate static func preview(name: String, symbol: String) -> CultureObject {
        CultureObject(
            id: UUID(),
            canonicalName: name,
            summary: "",
            category: .other,
            timePeriod: nil,
            region: nil,
            confidence: 1,
            artworkSymbol: symbol,
            concepts: [],
            relations: [],
            sources: []
        )
    }
}
