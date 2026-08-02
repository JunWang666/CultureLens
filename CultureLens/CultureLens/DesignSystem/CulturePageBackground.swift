import SwiftUI

struct CulturePageBackground: View {
    var body: some View {
        ZStack {
            CultureTheme.canvas

            Circle()
                .fill(CultureTheme.antiqueGold.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 45)
                .offset(x: 140, y: -260)

            Circle()
                .fill(CultureTheme.cinnabar.opacity(0.05))
                .frame(width: 240, height: 240)
                .blur(radius: 55)
                .offset(x: -160, y: 300)
        }
        .ignoresSafeArea()
    }
}
