import ImageIO
import SwiftUI

/// Frozen capture preview with a draggable focus region. Embedded in
/// `ScanView` so capture review does not present a separate sheet.
struct CaptureReviewLayer: View {
    /// Stable identity for `imageData`. Lets `.task(id:)` re-decode only
    /// when the underlying photo actually changes, instead of comparing the
    /// (potentially large) `Data` buffer on every re-render.
    let imageID: UUID
    let imageData: Data
    let imagePixelSize: CGSize
    /// `nil` until the user draws a selection. The underlying image is never
    /// touched while the user is adjusting this — it's purely an overlay UI
    /// on top of the frozen preview. Only when the user taps a send button
    /// does `ScanCoordinator` actually redraw the photo with this region.
    @Binding var selection: NormalizedImageRegion?

    // Decoded once per `imageID` and cached, so dragging the focus region
    // does not re-decode the JPEG on every gesture update (this was the
    // source of the visible jank/stutter while adjusting the selection).
    @State private var decodedImage: Image?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = aspectFitFrame(
                imageSize: imagePixelSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                Color.black

                imageContent
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                FocusSelectionOverlay(
                    imageFrame: imageFrame,
                    region: $selection
                )
            }
        }
        .ignoresSafeArea()
        .task(id: imageID) {
            decodedImage = Self.decode(imageData)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let decodedImage {
            decodedImage
                .resizable()
                .scaledToFit()
        } else {
            Color.black
        }
    }

    private static func decode(_ data: Data) -> Image? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }
        return Image(decorative: image, scale: 1)
    }

    private func aspectFitFrame(
        imageSize: CGSize,
        in bounds: CGRect
    ) -> CGRect {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            bounds.width > 0,
            bounds.height > 0
        else {
            return bounds
        }

        let scale = min(
            bounds.width / imageSize.width,
            bounds.height / imageSize.height
        )
        let size = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// Lets the user pick the focus region by dragging one finger diagonally
/// across the photo: the drag's start and end points become the two
/// opposite corners of the selection rectangle. No box is shown until the
/// user draws one, and there is a single border (no separate handles or
/// decorative brackets), so the selection reads unambiguously.
struct FocusSelectionOverlay: View {
    let imageFrame: CGRect
    @Binding var region: NormalizedImageRegion?

    // Small enough that framing a tiny inscription or detail doesn't get
    // force-expanded to something much bigger than what was actually drawn
    // (that "snap" on release was reading as imprecise).
    private let minimumSize = 0.05
    private let cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            if let region {
                let selectionFrame = region
                    .clamped(minimumSize: minimumSize)
                    .rect(in: imageFrame)

                // Rendered as a single offscreen layer so repeated updates
                // while dragging are composited on the GPU instead of
                // re-rasterizing multiple Core Graphics shapes every frame.
                ZStack {
                    Path { path in
                        path.addRect(imageFrame)
                        path.addRoundedRect(
                            in: selectionFrame,
                            cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                        )
                    }
                    .fill(
                        Color.black.opacity(0.55),
                        style: FillStyle(eoFill: true)
                    )

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(CultureTheme.antiqueGold, lineWidth: 2)
                        .frame(
                            width: selectionFrame.width,
                            height: selectionFrame.height
                        )
                        .position(x: selectionFrame.midX, y: selectionFrame.midY)
                }
                .drawingGroup()
                .allowsHitTesting(false)
            } else {
                hint
            }

            // Transparent hit area covering the whole photo so the diagonal
            // drag can start from anywhere on it, not just inside the box.
            Color.white.opacity(0.001)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .contentShape(Rectangle())
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .gesture(diagonalDragGesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("框选区域")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("在图片上从一角滑动到另一角，即可框选；不框选则识别整张图片")
    }

    private var hint: some View {
        Text("在图片上画一条斜线即可框选，不选则识别整张图片")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.42), in: Capsule())
            .foregroundStyle(.white)
            .position(x: imageFrame.midX, y: imageFrame.minY + 28)
            .allowsHitTesting(false)
    }

    private var accessibilityValue: String {
        guard let region else { return "未框选，将识别整张图片" }
        let focus = region.clamped(minimumSize: minimumSize)
        return "左侧 \(Int((focus.x * 100).rounded()))%，顶部 \(Int((focus.y * 100).rounded()))%，宽 \(Int((focus.width * 100).rounded()))%，高 \(Int((focus.height * 100).rounded()))%"
    }

    /// A single drag across the image: the point where the finger goes down
    /// (`startLocation`, fixed for the whole gesture) and the point where it
    /// currently is (or lifts up) are treated as the two diagonal corners of
    /// the new selection rectangle.
    private var diagonalDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                region = rectangle(
                    from: normalizedPoint(value.startLocation),
                    to: normalizedPoint(value.location),
                    enforceMinimumSize: false
                )
            }
            .onEnded { value in
                region = rectangle(
                    from: normalizedPoint(value.startLocation),
                    to: normalizedPoint(value.location),
                    enforceMinimumSize: true
                )
            }
    }

    /// Converts a point in the overlay's local coordinate space (0 to
    /// `imageFrame.width`/`height`) into normalized image coordinates
    /// (0...1), clamped to the image bounds.
    private func normalizedPoint(_ point: CGPoint) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return .zero
        }
        return CGPoint(
            x: min(max(point.x / imageFrame.width, 0), 1),
            y: min(max(point.y / imageFrame.height, 0), 1)
        )
    }

    private func rectangle(
        from start: CGPoint,
        to end: CGPoint,
        enforceMinimumSize: Bool
    ) -> NormalizedImageRegion {
        var minX = min(start.x, end.x)
        var maxX = max(start.x, end.x)
        var minY = min(start.y, end.y)
        var maxY = max(start.y, end.y)

        if enforceMinimumSize {
            if maxX - minX < minimumSize {
                let center = (minX + maxX) / 2
                minX = center - minimumSize / 2
                maxX = center + minimumSize / 2
                if minX < 0 {
                    maxX -= minX
                    minX = 0
                } else if maxX > 1 {
                    minX -= maxX - 1
                    maxX = 1
                }
            }
            if maxY - minY < minimumSize {
                let center = (minY + maxY) / 2
                minY = center - minimumSize / 2
                maxY = center + minimumSize / 2
                if minY < 0 {
                    maxY -= minY
                    minY = 0
                } else if maxY > 1 {
                    minY -= maxY - 1
                    maxY = 1
                }
            }
        }

        return NormalizedImageRegion(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

#Preview {
    CaptureReviewLayer(
        imageID: UUID(),
        imageData: SampleScanImage.jpegData(),
        imagePixelSize: CGSize(width: 1200, height: 1600),
        selection: .constant(nil)
    )
}
