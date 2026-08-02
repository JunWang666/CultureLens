import ImageIO
import SwiftUI

struct DataImageView: View {
    let data: Data

    var body: some View {
        if
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                CultureTheme.inkPrimary
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
