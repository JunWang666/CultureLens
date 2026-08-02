import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case explore
    case scan
    case graph
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .explore: "探索"
        case .scan: "扫描"
        case .graph: "图谱"
        case .profile: "我的"
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
