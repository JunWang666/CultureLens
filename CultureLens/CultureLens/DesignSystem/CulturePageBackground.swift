import SwiftUI

struct CulturePageBackground: View {
    var body: some View {
        ZStack {
            CultureTheme.canvas

            // 极淡的纸纹颗粒，替代原来的氛围光斑——杂志是纸，不是灯。
            PaperGrain.image
                .resizable(resizingMode: .tile)
                .opacity(0.05)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// 运行时生成一次 120×120 的灰点噪点图，平铺当纸纹。
private enum PaperGrain {
    static let image: Image = {
        let side: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let uiImage = renderer.image { context in
            for _ in 0..<700 {
                let x = CGFloat.random(in: 0..<side)
                let y = CGFloat.random(in: 0..<side)
                let white = CGFloat.random(in: 0.25...0.85)
                UIColor(white: white, alpha: 0.6).setFill()
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return Image(uiImage: uiImage)
    }()
}
