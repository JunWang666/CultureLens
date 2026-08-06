import SwiftUI

/// Apple Intelligence–style "跑马灯": a rotating conic-gradient ring with a
/// soft, breathing halo. Drawn around the scanned photo while recognition is
/// running to signal that on-device AI work is in flight.
struct IntelligenceGlowBorder: View {
    var cornerRadius: CGFloat = 20
    var lineWidth: CGFloat = 8
    var glowBlur: CGFloat = 40
    /// Seconds for one full revolution of the gradient.
    var period: Double = 2.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var isPulsing = false

    private static let palette: [Color] = [
        Color(red: 0.15, green: 0.50, blue: 1.00), // electric blue
        Color(red: 0.55, green: 0.25, blue: 1.00), // vivid violet
        Color(red: 0.90, green: 0.15, blue: 0.95), // magenta
        Color(red: 1.00, green: 0.20, blue: 0.55), // hot pink
        Color(red: 1.00, green: 0.50, blue: 0.10), // vivid orange
        Color(red: 0.10, green: 0.85, blue: 1.00), // bright cyan
    ]

    /// Rotating the gradient's angles (instead of `rotationEffect` on the
    /// shape) keeps the ring aligned with the rounded rect even when the
    /// frame is not square.
    private var gradient: AngularGradient {
        AngularGradient(
            colors: Self.palette + [Self.palette[0]],
            center: .center,
            startAngle: .degrees(rotation),
            endAngle: .degrees(rotation + 360)
        )
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Wide outer halo bleeding far past the edge, brightness breathing.
            shape
                .stroke(gradient, lineWidth: lineWidth * 5)
                .blur(radius: glowBlur * 1.6)
                .opacity(isPulsing ? 1 : 0.55)

            // Mid halo keeping the glow saturated closer to the ring.
            shape
                .stroke(gradient, lineWidth: lineWidth * 2.2)
                .blur(radius: glowBlur * 0.55)
                .opacity(isPulsing ? 1 : 0.8)

            // Crisp inner ring riding on top of the halo.
            shape
                .strokeBorder(gradient, lineWidth: lineWidth)
        }
        // Additive blending keeps the marquee vivid even over bright photos.
        .blendMode(.plusLighter)
        .scaleEffect(isPulsing ? 1.045 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: period * 0.6).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.gray.opacity(0.3))
            .frame(width: 280, height: 380)
            .overlay {
                IntelligenceGlowBorder()
                    .padding(-12)
            }
    }
}
