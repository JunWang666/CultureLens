import SwiftUI

/// Review hub: chronological scan timeline + clustered visit trips.
struct ReviewHomeView: View {
    var showsBackButton: Bool = true
    var startScan: (() -> Void)?

    private enum Mode: String, CaseIterable, Identifiable {
        case timeline = "时间线足迹"
        case trips = "文化回顾"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .timeline: "clock.arrow.circlepath"
            case .trips: "book.pages"
            }
        }
    }

    @State private var mode: Mode = .timeline

    var body: some View {
        ZStack {
            CulturePageBackground()

            Group {
                switch mode {
                case .timeline:
                    ScanTimelineView(startScan: startScan)
                case .trips:
                    VisitTripListView(showsBackButton: false, embedsInReviewHub: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .cultureNavigationTitle("回顾", showsBackButton: showsBackButton)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("回顾方式", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Label(LocalizedStringKey(item.rawValue), systemImage: item.systemImage)
                            .tag(item)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("回顾方式")
                .accessibilityValue(LocalizedStringKey(mode.rawValue))
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReviewHomeView(showsBackButton: false)
    }
}
