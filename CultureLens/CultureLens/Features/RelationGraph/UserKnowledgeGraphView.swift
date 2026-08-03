import SwiftData
import SwiftUI

/// The user's real knowledge graph: all joined nodes plus three shortest-hop
/// layers from a user-selectable center in the bundled knowledge pack.
struct UserKnowledgeGraphView: View {
    @Environment(KnowledgeProgressStore.self)
    private var progressStore
    @Environment(ScanSessionStore.self)
    private var sessionStore

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    @State private var knowledgeStore: KnowledgeStore?
    @State private var selectedCenterID: UUID?
    @State private var renderState: RenderState?
    @State private var didAttemptLoad = false

    private struct RenderState {
        let snapshot: UserKnowledgeGraphSnapshot
        let layout: UserKnowledgeGraphLayout
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            if progressStore.graphNodeIDs.isEmpty {
                emptyState
            } else if let renderState {
                graphContent(renderState)
            } else if didAttemptLoad {
                ContentUnavailableView(
                    "知识图谱暂不可用",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("知识包没有成功载入，请稍后再试。")
                )
            } else {
                ProgressView("正在生成文化图谱…")
            }
        }
        .navigationTitle("图谱")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard knowledgeStore == nil else { return }
            knowledgeStore = await KnowledgePackLoader.shared.store()
            didAttemptLoad = true
            rebuildGraph()
        }
        .onChange(of: progressStore.graphNodeIDs) {
            rebuildGraph()
        }
        .onChange(of: records.map(\.recordID)) {
            rebuildGraph()
        }
        .onChange(of: sessionStore.sessionIDs) {
            rebuildGraph()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("文化图谱还是空的", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("在对象或知识详情页点击“加入文化图谱”，这里会显示已加入节点，并从中心向外展开三层关系。")
        }
        .padding(CultureTheme.pagePadding)
    }

    private func graphContent(_ state: RenderState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            graphHeader(state.snapshot)
            graphViewport(state)
            graphLegend(state.snapshot)
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func graphHeader(_ snapshot: UserKnowledgeGraphSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("我的文化图谱")
                    .font(.cultureSerif(.title2))
                    .foregroundStyle(CultureTheme.inkPrimary)
                Text("已加入 \(progressStore.graphNodeIDs.count) 个 · 展示 \(snapshot.nodes.count) 个 · 向外 3 层")
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }

            Spacer(minLength: 8)

            centerMenu(snapshot)
        }
    }

    private func centerMenu(_ snapshot: UserKnowledgeGraphSnapshot) -> some View {
        Menu {
            let joinedNodes = snapshot.nodes.filter(\.isJoined)
            let discoveredNodes = snapshot.nodes.filter { !$0.isJoined }

            if !joinedNodes.isEmpty {
                Section("已加入") {
                    centerButtons(for: joinedNodes, centerID: snapshot.centerID)
                }
            }
            if !discoveredNodes.isEmpty {
                Section("三层关系") {
                    centerButtons(for: discoveredNodes, centerID: snapshot.centerID)
                }
            }
        } label: {
            Label("选择中心", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .accessibilityHint("选择一个节点作为三层关系展开的中心")
    }

    @ViewBuilder
    private func centerButtons(
        for nodes: [UserKnowledgeGraphNode],
        centerID: UUID?
    ) -> some View {
        ForEach(nodes.sorted(by: nodeNameOrder)) { node in
            Button {
                selectCenter(node.id)
            } label: {
                if node.id == centerID {
                    Label(node.name, systemImage: "scope")
                } else {
                    Text(node.name)
                }
            }
        }
    }

    private func graphViewport(_ state: RenderState) -> some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    edgeCanvas(state)

                    ForEach(state.snapshot.nodes) { node in
                        graphNodeLink(node, centerID: state.snapshot.centerID)
                            .id(node.id)
                            .position(state.layout.positions[node.id] ?? .zero)
                    }
                }
                .frame(width: state.layout.size.width, height: state.layout.size.height)
                .padding(18)
            }
            .onAppear {
                scrollToCenter(state.snapshot.centerID, proxy: proxy)
            }
            .onChange(of: state.snapshot.centerID) {
                scrollToCenter(state.snapshot.centerID, proxy: proxy)
            }
        }
        .frame(maxHeight: .infinity)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("以可选择节点为中心的三层文化知识图谱")
    }

    private func edgeCanvas(_ state: RenderState) -> some View {
        Canvas { context, _ in
            for edge in state.snapshot.edges {
                guard
                    let source = state.layout.positions[edge.sourceID],
                    let target = state.layout.positions[edge.targetID]
                else { continue }

                var path = Path()
                path.move(to: source)
                path.addLine(to: target)
                let touchesCenter = edge.sourceID == state.snapshot.centerID
                    || edge.targetID == state.snapshot.centerID
                context.stroke(
                    path,
                    with: .color(
                        touchesCenter
                            ? CultureTheme.cinnabar.opacity(0.66)
                            : CultureTheme.inkSecondary.opacity(0.28)
                    ),
                    style: StrokeStyle(
                        lineWidth: touchesCenter ? 2 : 1.2,
                        lineCap: .round
                    )
                )
            }
        }
        .frame(width: state.layout.size.width, height: state.layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func graphNodeLink(
        _ node: UserKnowledgeGraphNode,
        centerID: UUID?
    ) -> some View {
        if let route = route(for: node) {
            NavigationLink(value: route) {
                graphNode(node, isCenter: node.id == centerID)
            }
            .buttonStyle(.plain)
            .contextMenu {
                graphNodeActions(node)
            }
        } else {
            graphNode(node, isCenter: node.id == centerID)
                .contextMenu {
                    graphNodeActions(node)
                }
        }
    }

    private func graphNode(
        _ node: UserKnowledgeGraphNode,
        isCenter: Bool
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: isCenter ? "scope" : node.kind.systemImage)
                Text(nodeCaption(node, isCenter: isCenter))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCenter ? CultureTheme.antiqueGold : nodeAccent(node))

            Text(node.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCenter ? Color.white : CultureTheme.inkPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(
            width: UserKnowledgeGraphLayout.nodeSize.width,
            height: UserKnowledgeGraphLayout.nodeSize.height
        )
        .background(
            isCenter ? CultureTheme.inkPrimary : CultureTheme.canvas,
            in: RoundedRectangle(cornerRadius: 19)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(nodeAccent(node), lineWidth: node.isJoined || isCenter ? 2 : 1)
        }
        .shadow(color: .black.opacity(isCenter ? 0.13 : 0.04), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 19))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name)，\(nodeCaption(node, isCenter: isCenter))")
        .accessibilityHint(route(for: node) == nil ? "长按可设为中心" : "打开详情；长按可设为中心")
    }

    @ViewBuilder
    private func graphNodeActions(_ node: UserKnowledgeGraphNode) -> some View {
        Button {
            selectCenter(node.id)
        } label: {
            Label("设为中心", systemImage: "scope")
        }

        Menu {
            ForEach(KnowledgeLevel.allCases, id: \.self) { level in
                Button {
                    withAnimation(.snappy) {
                        progressStore.setLevel(
                            level,
                            for: node.id,
                            source: .manual,
                            elementKey: node.elementKey
                        )
                    }
                } label: {
                    if progressStore.level(for: node.id) == level {
                        Label(level.rawValue, systemImage: "checkmark")
                    } else {
                        Text(level.rawValue)
                    }
                }
            }
            if node.isJoined {
                Divider()
                Button(role: .destructive) {
                    withAnimation(.snappy) {
                        progressStore.remove(node.id)
                    }
                } label: {
                    Label("移出文化图谱", systemImage: "minus.circle")
                }
            }
        } label: {
            Label(
                node.isJoined ? "调整掌握程度" : "加入文化图谱",
                systemImage: node.isJoined ? "slider.horizontal.3" : "plus.circle"
            )
        }
    }

    private func graphLegend(_ snapshot: UserKnowledgeGraphSnapshot) -> some View {
        HStack(spacing: 14) {
            legendItem("中心", color: CultureTheme.cinnabar)
            legendItem("已加入", color: CultureTheme.antiqueGold)
            legendItem("关系节点", color: CultureTheme.inkSecondary)
            Spacer(minLength: 4)
            Label("拖动画布", systemImage: "hand.draw")
        }
        .font(.caption2)
        .foregroundStyle(CultureTheme.inkSecondary)
        .overlay(alignment: .topLeading) {
            if snapshot.isExpansionTruncated {
                Text("关系节点较多，已限制本次展开数量")
                    .font(.caption2)
                    .foregroundStyle(CultureTheme.cinnabar)
                    .offset(y: -22)
            }
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
        }
    }

    private func nodeCaption(_ node: UserKnowledgeGraphNode, isCenter: Bool) -> String {
        if isCenter { return "当前中心" }
        if let level = progressStore.level(for: node.id) {
            return level.rawValue
        }
        return "\(node.hop) 跳"
    }

    private func nodeAccent(_ node: UserKnowledgeGraphNode) -> Color {
        if node.isJoined { return CultureTheme.antiqueGold }
        switch node.hop {
        case 1: return CultureTheme.cinnabar
        case 2: return CultureTheme.antiqueGold
        default: return CultureTheme.inkSecondary
        }
    }

    private func route(for node: UserKnowledgeGraphNode) -> AppRoute? {
        if let elementKey = node.elementKey {
            return .knowledgeElement(elementKey)
        }
        if object(id: node.id) != nil {
            return .object(node.id)
        }
        if concept(id: node.id) != nil {
            return .concept(node.id)
        }
        return nil
    }

    private func selectCenter(_ id: UUID) {
        selectedCenterID = id
        rebuildGraph()
    }

    private func rebuildGraph() {
        guard let knowledgeStore else {
            renderState = nil
            return
        }
        guard !progressStore.graphNodeIDs.isEmpty else {
            selectedCenterID = nil
            renderState = nil
            return
        }

        let snapshot = knowledgeStore.userKnowledgeGraph(
            centerID: selectedCenterID,
            joinedSeeds: joinedSeeds
        )
        selectedCenterID = snapshot.centerID
        renderState = RenderState(
            snapshot: snapshot,
            layout: UserKnowledgeGraphLayout(snapshot: snapshot)
        )
    }

    private var joinedSeeds: [UserKnowledgeGraphSeed] {
        progressStore.graphNodeIDs.map { id in
            if let object = object(id: id) {
                return UserKnowledgeGraphSeed(
                    id: id,
                    name: object.canonicalName,
                    summary: object.summary
                )
            }
            if let concept = concept(id: id) {
                return UserKnowledgeGraphSeed(
                    id: id,
                    name: concept.name,
                    summary: concept.summary
                )
            }
            return UserKnowledgeGraphSeed(
                id: id,
                name: "已加入的文化节点",
                summary: "该节点来自旧记录或其他版本的知识包。"
            )
        }
    }

    private func object(id: UUID) -> CultureObject? {
        if let sessionObject = sessionStore.object(id: id) {
            return sessionObject
        }
        for record in records {
            if let savedObject = record.savedObject, savedObject.id == id {
                return savedObject
            }
        }
        return SampleCultureData.object(id: id)
    }

    private func concept(id: UUID) -> CultureConcept? {
        if let sessionConcept = sessionStore.concept(id: id) {
            return sessionConcept
        }
        for record in records {
            let savedObject = record.historySnapshot?.result.object
                ?? record.legacyResultSnapshot?.object
            if let savedConcept = savedObject?.concepts.first(where: { $0.id == id }) {
                return savedConcept
            }
        }
        return SampleCultureData.concept(id: id)
    }

    private func scrollToCenter(_ id: UUID?, proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func nodeNameOrder(
        _ lhs: UserKnowledgeGraphNode,
        _ rhs: UserKnowledgeGraphNode
    ) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

#Preview {
    NavigationStack {
        UserKnowledgeGraphView()
    }
    .environment(KnowledgeProgressStore())
    .environment(ScanSessionStore())
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
