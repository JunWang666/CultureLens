import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case explore
    case chat
    case scan
    case graph
    /// Scan footprint map + timeline (split from former Profile).
    case history
    case review
    case settings
    /// Compact-only overflow container for secondary tabs.
    case more

    var id: Self { self }

    /// Tabs always shown in the tab bar.
    static let primaryTabs: [AppTab] = [.explore, .chat, .scan, .graph]

    /// Former「我的」features; shown individually on regular width.
    static let secondaryTabs: [AppTab] = [.history, .review, .settings]

    /// Entries for the system View menu (excludes the compact「更多」shell).
    static var menuTabs: [AppTab] { primaryTabs + secondaryTabs }

    var title: String {
        switch self {
        case .explore: String(localized: "探索")
        case .chat: String(localized: "文化问答")
        case .scan: String(localized: "扫描")
        case .graph: String(localized: "图谱")
        case .history: String(localized: "足迹")
        case .review: String(localized: "文化回顾")
        case .settings: String(localized: "设置")
        case .more: String(localized: "更多")
        }
    }

    var systemImage: String {
        switch self {
        case .explore: "sparkles"
        case .chat: "bubble.left.and.bubble.right"
        case .scan: "camera.viewfinder"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .history: "map"
        case .review: "book.pages"
        case .settings: "gearshape"
        case .more: "ellipsis"
        }
    }

    /// ⌘1… in the system View menu on iPad / Mac.
    var keyboardShortcutKey: KeyEquivalent? {
        switch self {
        case .explore: "1"
        case .chat: "2"
        case .scan: "3"
        case .graph: "4"
        case .history: "5"
        case .review: "6"
        case .settings: "7"
        case .more: nil
        }
    }
}

private struct SelectedAppTabKey: FocusedValueKey {
    typealias Value = Binding<AppTab>
}

extension FocusedValues {
    var selectedAppTab: Binding<AppTab>? {
        get { self[SelectedAppTabKey.self] }
        set { self[SelectedAppTabKey.self] = newValue }
    }
}

/// Puts root tabs into the system View menu (iPadOS 26 menu bar / Mac).
struct AppTabCommands: Commands {
    @FocusedBinding(\.selectedAppTab) private var selectedTab

    var body: some Commands {
        SidebarCommands()
        CommandGroup(after: .sidebar) {
            ForEach(AppTab.menuTabs) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    if selectedTab == tab {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
                .modifier(OptionalKeyboardShortcut(tab.keyboardShortcutKey))
                .disabled(selectedTab == nil)
            }
        }
    }
}

private struct OptionalKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent?

    init(_ key: KeyEquivalent?) {
        self.key = key
    }

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}
