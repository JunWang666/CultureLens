import SwiftUI

enum KnowledgeGraphMembershipButtonPresentation {
    case fullWidth
    case toolbar
}

struct KnowledgeGraphMembershipButton: View {
    let nodeID: UUID
    var elementKey: String? = nil
    let presentation: KnowledgeGraphMembershipButtonPresentation

    @Environment(KnowledgeProgressStore.self)
    private var progressStore

    private var currentLevel: KnowledgeLevel? {
        progressStore.level(for: nodeID, elementKey: elementKey)
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
                        elementKey: elementKey
                    )
                }
            } label: {
                if currentLevel == level {
                    Label(level.rawValue, systemImage: "checkmark")
                } else {
                    Text(level.rawValue)
                }
            }
        }
        if isInGraph {
            Divider()
            Button(role: .destructive) {
                withAnimation(.snappy) {
                    progressStore.remove(nodeID, elementKey: elementKey)
                }
            } label: {
                Label("移出文化图谱", systemImage: "minus.circle")
            }
        }
    }

    private var fullWidthTitle: String {
        if let currentLevel {
            return "图谱 · \(currentLevel.rawValue)"
        }
        return "加入文化图谱"
    }

    private var accessibilityLabel: String {
        if let currentLevel {
            return "文化图谱状态：\(currentLevel.rawValue)"
        }
        return "加入文化图谱"
    }
}
