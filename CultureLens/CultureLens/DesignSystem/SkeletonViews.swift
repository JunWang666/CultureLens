import SwiftUI

/// A highlight that sweeps left-to-right across the view forever, used to
/// signal content that is still loading. The sweep is clipped to `shape`
/// rather than masked by the content, so translucent fills stay visible.
/// Honors Reduce Motion.
private struct ShimmerModifier<S: InsettableShape>: ViewModifier {
  var shape: S
  var isActive: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var phase: CGFloat = -1

  private var animating: Bool {
    isActive && !reduceMotion
  }

  func body(content: Content) -> some View {
    content
      .overlay {
        if animating {
          GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
              colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.55),
                Color.white.opacity(0),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
            .frame(width: width)
            .offset(x: phase * width)
          }
          .clipShape(shape)
        }
      }
      .onAppear {
        guard animating else { return }
        phase = -1
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
          phase = 1
        }
      }
  }
}

extension View {
  /// Overlays an animated shimmering highlight clipped to `shape`.
  func shimmering<S: InsettableShape>(in shape: S, active: Bool = true) -> some View {
    modifier(ShimmerModifier(shape: shape, isActive: active))
  }
}

/// A single shimmering placeholder line, pill-shaped.
struct SkeletonLine: View {
  var height: CGFloat = 14
  var widthFraction: CGFloat = 1.0

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
  }

  var body: some View {
    shape
      .fill(CultureTheme.inkPrimary.opacity(0.10))
      .frame(height: height)
      .frame(maxWidth: .infinity, alignment: .leading)
      .shimmering(in: shape)
      .scaleEffect(x: widthFraction, y: 1, anchor: .leading)
  }
}

/// A paragraph-shaped cluster of shimmering lines shown while text loads.
struct SkeletonTextBlock: View {
  var widthFractions: [CGFloat] = [1.0, 1.0, 0.9, 0.62]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(widthFractions.enumerated()), id: \.offset) { _, fraction in
        SkeletonLine(widthFraction: fraction)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
