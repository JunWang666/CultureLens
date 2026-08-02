import SwiftUI

enum KnowledgeUnderstandingButtonPresentation {
    case fullWidth
    case toolbar
}

struct KnowledgeUnderstandingButton: View {
    let nodeID: UUID
    let presentation: KnowledgeUnderstandingButtonPresentation

    @Environment(KnowledgeProgressStore.self)
    private var progressStore

    private var isUnderstood: Bool {
        progressStore.isUnderstood(nodeID)
    }

    var body: some View {
        switch presentation {
        case .fullWidth:
            Button(action: toggleUnderstanding) {
                Label(
                    isUnderstood ? "已了解" : "我已经了解",
                    systemImage: isUnderstood ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isUnderstood ? CultureTheme.antiqueGold : CultureTheme.inkPrimary)
            .controlSize(.large)
            .accessibilityLabel(accessibilityLabel)

        case .toolbar:
            Button(action: toggleUnderstanding) {
                Image(systemName: isUnderstood ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var accessibilityLabel: String {
        isUnderstood ? "取消已了解" : "标记为已了解"
    }

    private func toggleUnderstanding() {
        withAnimation(.snappy) {
            progressStore.toggleUnderstanding(nodeID)
        }
    }
}
