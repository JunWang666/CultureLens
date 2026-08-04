import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case explore
    case scan
    case graph
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .explore: String(localized: "探索")
        case .scan: String(localized: "扫描")
        case .graph: String(localized: "图谱")
        case .profile: String(localized: "我的")
        }
    }

    var systemImage: String {
        switch self {
        case .explore: "sparkles"
        case .scan: "camera.viewfinder"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .profile: "map"
        }
    }
}
