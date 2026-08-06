import ImageIO
import SwiftUI

private enum CaptureReviewCoordinateSpace {
    static let name = "capture-review"
}

/// Geometry shared by the visible selection and its gesture mapping. Gesture
/// locations are expressed in the full capture-review coordinate space, while
/// normalized regions are relative to the aspect-fitted image only.
nonisolated enum FocusSelectionGeometry {
    static let minimumScreenLength: CGFloat = 16

    static func aspectFitFrame(
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

    static func normalizedPoint(
        _ point: CGPoint,
        in imageFrame: CGRect
    ) -> CGPoint {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return .zero
        }
        return CGPoint(
            x: min(max((point.x - imageFrame.minX) / imageFrame.width, 0), 1),
            y: min(max((point.y - imageFrame.minY) / imageFrame.height, 0), 1)
        )
    }

    static func region(
        from start: CGPoint,
        to end: CGPoint,
        in imageFrame: CGRect,
        enforceMinimumSize: Bool
    ) -> NormalizedImageRegion {
        let normalizedStart = normalizedPoint(start, in: imageFrame)
        let normalizedEnd = normalizedPoint(end, in: imageFrame)
        var minX = min(normalizedStart.x, normalizedEnd.x)
        var maxX = max(normalizedStart.x, normalizedEnd.x)
        var minY = min(normalizedStart.y, normalizedEnd.y)
        var maxY = max(normalizedStart.y, normalizedEnd.y)

        if enforceMinimumSize {
            let minimumWidth = min(minimumScreenLength / imageFrame.width, 1)
            let minimumHeight = min(minimumScreenLength / imageFrame.height, 1)
            (minX, maxX) = expandedRange(
                min: minX,
                max: maxX,
                minimumLength: minimumWidth
            )
            (minY, maxY) = expandedRange(
                min: minY,
                max: maxY,
                minimumLength: minimumHeight
            )
        }

        return NormalizedImageRegion(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    private static func expandedRange(
        min: CGFloat,
        max: CGFloat,
        minimumLength: CGFloat
    ) -> (CGFloat, CGFloat) {
        guard max - min < minimumLength else { return (min, max) }

        let center = (min + max) / 2
        var lower = center - minimumLength / 2
        var upper = center + minimumLength / 2
        if lower < 0 {
            upper -= lower
            lower = 0
        } else if upper > 1 {
            lower -= upper - 1
            upper = 1
        }
        return (lower, upper)
    }
}

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
    /// While recognition is in flight the focus UI steps aside and an
    /// animated glow marquee wraps the photo instead.
    var isRecognizing: Bool = false

    // Decoded once per `imageID` and cached, so dragging the focus region
    // does not re-decode the JPEG on every gesture update (this was the
    // source of the visible jank/stutter while adjusting the selection).
    @State private var decodedImage: Image?

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = FocusSelectionGeometry.aspectFitFrame(
                imageSize: imagePixelSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                Color.black

                imageContent
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .overlay {
                        if isRecognizing {
                            IntelligenceGlowBorder(cornerRadius: 22)
                                .padding(-14)
                                .transition(.opacity.combined(with: .scale(scale: 1.06)))
                        }
                    }

                if !isRecognizing {
                    FocusSelectionOverlay(
                        imageFrame: imageFrame,
                        region: $selection
                    )
                }
            }
            .coordinateSpace(name: CaptureReviewCoordinateSpace.name)
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
}

/// Lets the user pick the focus region by dragging one finger diagonally
/// across the photo: the drag's start and end points become the two
/// opposite corners of the selection rectangle. No box is shown until the
/// user draws one, and there is a single border (no separate handles or
/// decorative brackets), so the selection reads unambiguously.
struct FocusSelectionOverlay: View {
    let imageFrame: CGRect
    @Binding var region: NormalizedImageRegion?

    private let cornerRadius: CGFloat = 6
    private let edgeTouchPadding: CGFloat = 12

    var body: some View {
        ZStack {
            if let region {
                let selectionFrame = region.clamped().rect(in: imageFrame)

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

            // Slightly overscan the transparent hit area so a finger landing
            // on the visible image edge still starts a drag. Named-space
            // mapping below clamps that small overscan back to the image.
            Color.white.opacity(0.001)
                .frame(
                    width: imageFrame.width + edgeTouchPadding * 2,
                    height: imageFrame.height + edgeTouchPadding * 2
                )
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

    private var accessibilityValue: LocalizedStringKey {
        guard let region else { return "未框选，将识别整张图片" }
        let focus = region.clamped()
        return "左侧 \(Int((focus.x * 100).rounded()))%，顶部 \(Int((focus.y * 100).rounded()))%，宽 \(Int((focus.width * 100).rounded()))%，高 \(Int((focus.height * 100).rounded()))%"
    }

    /// A single drag across the image: the point where the finger goes down
    /// (`startLocation`, fixed for the whole gesture) and the point where it
    /// currently is (or lifts up) are treated as the two diagonal corners of
    /// the new selection rectangle.
    private var diagonalDragGesture: some Gesture {
        DragGesture(
            minimumDistance: 4,
            coordinateSpace: .named(CaptureReviewCoordinateSpace.name)
        )
            .onChanged { value in
                region = FocusSelectionGeometry.region(
                    from: value.startLocation,
                    to: value.location,
                    in: imageFrame,
                    enforceMinimumSize: false
                )
            }
            .onEnded { value in
                region = FocusSelectionGeometry.region(
                    from: value.startLocation,
                    to: value.location,
                    in: imageFrame,
                    enforceMinimumSize: true
                )
            }
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
