import ImageIO
import SwiftUI

/// Frozen capture preview with a draggable focus region. Embedded in
/// `ScanView` so capture review does not present a separate sheet.
struct CaptureReviewLayer: View {
    let imageData: Data
    let imagePixelSize: CGSize
    @Binding var selection: NormalizedImageRegion

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = aspectFitFrame(
                imageSize: imagePixelSize,
                in: CGRect(origin: .zero, size: proxy.size)
            )

            ZStack {
                Color.black

                decodedImage(data: imageData)
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)

                FocusSelectionOverlay(
                    imageFrame: imageFrame,
                    region: $selection
                )
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func decodedImage(data: Data) -> some View {
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Color.black
        }
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

struct FocusSelectionOverlay: View {
    enum Corner {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    let imageFrame: CGRect
    @Binding var region: NormalizedImageRegion

    @State private var moveStart: NormalizedImageRegion?
    @State private var resizeStart: NormalizedImageRegion?

    private let minimumSize = 0.18

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
                .fill(.white.opacity(0.001))
                .frame(
                    width: selectionFrame.width,
                    height: selectionFrame.height
                )
                .contentShape(Rectangle())
                .gesture(moveGesture)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(CultureTheme.antiqueGold, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                .position(x: selectionFrame.midX, y: selectionFrame.midY)

            handle(.topLeft, in: selectionFrame)
            handle(.topRight, in: selectionFrame)
            handle(.bottomLeft, in: selectionFrame)
            handle(.bottomRight, in: selectionFrame)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前框选区域")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("如不便调整，可使用下方的直接发送")
    }

    private var accessibilityValue: String {
        let focus = region.clamped(minimumSize: minimumSize)
        return "左侧 \(Int((focus.x * 100).rounded()))%，顶部 \(Int((focus.y * 100).rounded()))%，宽 \(Int((focus.width * 100).rounded()))%，高 \(Int((focus.height * 100).rounded()))%"
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                let start = moveStart
                    ?? region.clamped(minimumSize: minimumSize)
                if moveStart == nil {
                    moveStart = start
                }
                let dx = Double(value.translation.width / imageFrame.width)
                let dy = Double(value.translation.height / imageFrame.height)
                region = NormalizedImageRegion(
                    x: min(max(start.x + dx, 0), 1 - start.width),
                    y: min(max(start.y + dy, 0), 1 - start.height),
                    width: start.width,
                    height: start.height
                )
            }
            .onEnded { _ in
                moveStart = nil
            }
    }

    private func handle(
        _ corner: Corner,
        in selectionFrame: CGRect
    ) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 26, height: 26)

            Circle()
                .stroke(CultureTheme.cinnabar, lineWidth: 3)
                .frame(width: 26, height: 26)
                .allowsHitTesting(false)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .gesture(resizeGesture(corner))
        .position(position(for: corner, in: selectionFrame))
        .accessibilityHidden(true)
    }

    private func position(
        for corner: Corner,
        in frame: CGRect
    ) -> CGPoint {
        switch corner {
        case .topLeft:
            CGPoint(x: frame.minX, y: frame.minY)
        case .topRight:
            CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft:
            CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight:
            CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = resizeStart
                    ?? region.clamped(minimumSize: minimumSize)
                if resizeStart == nil {
                    resizeStart = start
                }
                let dx = Double(value.translation.width / imageFrame.width)
                let dy = Double(value.translation.height / imageFrame.height)
                region = resized(start, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in
                resizeStart = nil
            }
    }

    private func resized(
        _ start: NormalizedImageRegion,
        corner: Corner,
        dx: Double,
        dy: Double
    ) -> NormalizedImageRegion {
        var minX = start.x
        var minY = start.y
        var maxX = start.x + start.width
        var maxY = start.y + start.height

        switch corner {
        case .topLeft:
            minX = min(max(start.x + dx, 0), maxX - minimumSize)
            minY = min(max(start.y + dy, 0), maxY - minimumSize)
        case .topRight:
            maxX = max(min(start.x + start.width + dx, 1), minX + minimumSize)
            minY = min(max(start.y + dy, 0), maxY - minimumSize)
        case .bottomLeft:
            minX = min(max(start.x + dx, 0), maxX - minimumSize)
            maxY = max(min(start.y + start.height + dy, 1), minY + minimumSize)
        case .bottomRight:
            maxX = max(min(start.x + start.width + dx, 1), minX + minimumSize)
            maxY = max(min(start.y + start.height + dy, 1), minY + minimumSize)
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
        imageData: SampleScanImage.jpegData(),
        imagePixelSize: CGSize(width: 1200, height: 1600),
        selection: .constant(.defaultFocus)
    )
}
