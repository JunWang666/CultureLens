import SwiftData
import SwiftUI

/// 汇总所有被标记为“已了解”的知识节点，按类别分组展示。
struct UnderstoodGraphView: View {
    @Environment(KnowledgeProgressStore.self)
    private var progressStore

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    private var understoodConcepts: [CultureConcept] {
        // 与 AppRootView 的概念解析来源保持一致，保证条目可以跳转。
        let historyConcepts = records
            .compactMap { $0.historySnapshot?.result.object ?? $0.legacyResultSnapshot?.object }
            .flatMap(\.concepts)
        let sampleConcepts = SampleCultureData.objects.flatMap(\.concepts)

        var seen: Set<UUID> = []
        var result: [CultureConcept] = []
        for concept in historyConcepts + sampleConcepts
        where progressStore.isUnderstood(concept.id) && seen.insert(concept.id).inserted {
            result.append(concept)
        }
        return result
    }

    private var groupedConcepts: [(kind: ConceptKind, concepts: [CultureConcept])] {
        let groups = Dictionary(grouping: understoodConcepts, by: \.kind)
        return ConceptKind.allCases.compactMap { kind in
            guard let concepts = groups[kind], !concepts.isEmpty else { return nil }
            return (kind, concepts.sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if understoodConcepts.isEmpty {
                        emptyState
                    } else {
                        summary

                        ForEach(groupedConcepts, id: \.kind) { group in
                            section(for: group.kind, concepts: group.concepts)
                        }
                    }
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("图谱")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        Text("已了解 \(understoodConcepts.count) 个知识节点")
            .font(.cultureSerif(.title3))
            .foregroundStyle(CultureTheme.inkPrimary)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有已了解的知识点", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("在扫描结果或概念详情页点击“我已经了解”，知识点会汇总到这里。")
        }
        .frame(minHeight: 320)
    }

    private func section(for kind: ConceptKind, concepts: [CultureConcept]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(kind.rawValue, systemImage: kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            ForEach(concepts) { concept in
                NavigationLink(value: AppRoute.concept(concept.id)) {
                    conceptCard(concept)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("取消已了解", role: .destructive) {
                        progressStore.toggleUnderstanding(concept.id)
                    }
                }
            }
        }
    }

    private func conceptCard(_ concept: CultureConcept) -> some View {
        HStack(spacing: 14) {
            Image(systemName: concept.kind.systemImage)
                .font(.title3)
                .foregroundStyle(CultureTheme.antiqueGold)
                .frame(width: 48, height: 48)
                .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(concept.name)
                    .font(.headline)
                    .foregroundStyle(CultureTheme.inkPrimary)
                Text(concept.summary)
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开概念详情")
    }
}

#Preview {
    NavigationStack {
        UnderstoodGraphView()
    }
    .environment(KnowledgeProgressStore())
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
