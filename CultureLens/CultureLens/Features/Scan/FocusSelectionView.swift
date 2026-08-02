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
    @Binding var selection: NormalizedImageRegion

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
/// opposite corners of the selection rectangle. This replaces the previous
/// move-the-box-plus-four-resize-handles interaction, which needed five
/// separate gesture recognizers and felt heavy/laggy to use.
struct FocusSelectionOverlay: View {
    let imageFrame: CGRect
    @Binding var region: NormalizedImageRegion

    private let minimumSize = 0.18
    private let cornerMarkLength: CGFloat = 18

    var body: some View {
        let selectionFrame = region
            .clamped(minimumSize: minimumSize)
            .rect(in: imageFrame)

        ZStack {
            Path { path in
                path.addRect(imageFrame)
                path.addRoundedRect(
                    in: selectionFrame,
                    cornerSize: CGSize(width: 16, height: 16)
                )
            }
            .fill(
                Color.black.opacity(0.55),
                style: FillStyle(eoFill: true)
            )
            .allowsHitTesting(false)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CultureTheme.antiqueGold, lineWidth: 2)
                .frame(
                    width: selectionFrame.width,
                    height: selectionFrame.height
                )
                .position(x: selectionFrame.midX, y: selectionFrame.midY)
                .allowsHitTesting(false)

            cornerMarks(in: selectionFrame)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .allowsHitTesting(false)

            // Transparent hit area covering the whole photo so the diagonal
            // drag can start from anywhere on it, not just inside the box.
            Color.white.opacity(0.001)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .contentShape(Rectangle())
                .position(x: imageFrame.midX, y: imageFrame.midY)
                .gesture(diagonalDragGesture)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前框选区域")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("在图片上从一角滑动到另一角，即可重新框选；如不便调整，可使用下方的直接发送")
    }

    private var accessibilityValue: String {
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

    /// Purely decorative corner brackets: they make the rectangle read as a
    /// selection box without being separate hit-testable handles. Drawn
    /// directly in the same absolute coordinate space as `selectionFrame`.
    private func cornerMarks(in frame: CGRect) -> Path {
        Path { path in
            let length = cornerMarkLength

            path.move(to: CGPoint(x: frame.minX, y: frame.minY + length))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.minX + length, y: frame.minY))

            path.move(to: CGPoint(x: frame.maxX - length, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.minY + length))

            path.move(to: CGPoint(x: frame.minX, y: frame.maxY - length))
            path.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.minX + length, y: frame.maxY))

            path.move(to: CGPoint(x: frame.maxX - length, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
            path.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY - length))
        }
    }
}

#Preview {
    CaptureReviewLayer(
        imageID: UUID(),
        imageData: SampleScanImage.jpegData(),
        imagePixelSize: CGSize(width: 1200, height: 1600),
        selection: .constant(.defaultFocus)
    )
}
