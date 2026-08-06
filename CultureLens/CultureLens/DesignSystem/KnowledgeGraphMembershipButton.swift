import SwiftUI

enum KnowledgeGraphMembershipButtonPresentation {
    case fullWidth
    case toolbar
}

struct KnowledgeGraphMembershipButton: View {
    let nodeID: UUID
    var elementID: UUID? = nil
    let presentation: KnowledgeGraphMembershipButtonPresentation

    @Environment(KnowledgeProgressStore.self)
    private var progressStore

    private var currentLevel: KnowledgeLevel? {
        progressStore.level(for: nodeID, elementID: elementID)
    }

    private var isInGraph: Bool {
        currentLevel != nil
    }

    var body: some View {
        switch presentation {
        case .fullWidth:
            Menu {
                levelMenu
            } label: {
                Label(
                    fullWidthTitle,
                    systemImage: isInGraph
                        ? "checkmark.circle.fill"
                        : "point.3.connected.trianglepath.dotted"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isInGraph ? CultureTheme.antiqueGold : CultureTheme.inkPrimary)
            .controlSize(.large)
            .accessibilityLabel(accessibilityLabel)

        case .toolbar:
            Menu {
                levelMenu
            } label: {
                Image(
                    systemName: isInGraph
                        ? "checkmark.circle.fill"
                        : "point.3.connected.trianglepath.dotted"
                )
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var levelMenu: some View {
        ForEach(KnowledgeLevel.allCases, id: \.self) { level in
            Button {
                withAnimation(.snappy) {
                    progressStore.setLevel(
                        level,
                        for: nodeID,
                        source: .manual,
                        elementID: elementID
                    )
                }
            } label: {
                if currentLevel == level {
                    Label(level.displayName, systemImage: "checkmark")
                } else {
                    Text(level.displayName)
                }
            }
        }
        if isInGraph {
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) {
                    progressStore.remove(nodeID, elementID: elementID)
                }
            } label: {
                Label("移出文化图谱", systemImage: "minus.circle")
            }
        }
    }

    private var fullWidthTitle: LocalizedStringKey {
        if let currentLevel {
            switch currentLevel {
            case .contact: return "图谱 · 接触"
            case .understand: return "图谱 · 理解"
            case .master: return "图谱 · 掌握"
            }
        }
        return "加入文化图谱"
    }

    private var accessibilityLabel: LocalizedStringKey {
        if let currentLevel {
            switch currentLevel {
            case .contact: return "文化图谱状态：接触"
            case .understand: return "文化图谱状态：理解"
            case .master: return "文化图谱状态：掌握"
            }
        }
        return "加入文化图谱"
    }
}
