import SwiftData
import SwiftUI

/// The user's real knowledge graph: all joined nodes plus shortest-hop layers
/// from a user-selectable center in the bundled knowledge pack.
/// Presented edge-to-edge like `CultureRelationGraphView` fullscreen, sharing
/// the same radial layout kernel, edge geometry, semantic-family legend, and
/// zoom controls (design 0007).
struct UserKnowledgeGraphView: View {
    @Environment(KnowledgeProgressStore.self)
    private var progressStore
    @Environment(ScanSessionStore.self)
    private var sessionStore

    /// Popover content lives outside the NavigationStack, so detail
    /// navigation from the node preview goes through this closure instead of
    /// a `NavigationLink` (which is a no-op inside a popover).
    var onNavigate: ((AppRoute) -> Void)? = nil

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    @State private var knowledgeStore: KnowledgeStore?
    /// User-picked expansion centers; empty means "every joined node" (the
    /// store resolves the default set on each rebuild).
    @State private var selectedCenterIDs: Set<UUID> = []
    @State private var renderState: RenderState?
    @State private var didAttemptLoad = false

    @State private var displayMode: DisplayMode = .graph
    @State private var zoomScale: CGFloat = 1
    @State private var fittedZoomScale: CGFloat = 1
    @State private var centerRequest = 0

    @State private var searchText = ""
    @State private var kindFilter: ConceptKind?
    @State private var levelFilter: KnowledgeLevel?
    @State private var hiddenFamilies: Set<RelationSemanticFamily> = []
    @State private var selectedNodeID: UUID?
    /// Missing prerequisites of the current center (design 0007 阶段 4):
    /// rendered with a warning accent so users see what to learn first.
    @State private var missingPrerequisiteIDs: Set<UUID> = []
    @State private var isCenterPickerPresented = false
    @State private var expansionLimit = Self.defaultExpansionLimit
    @State private var rebuildTask: Task<Void, Never>?

    private static let defaultExpansionLimit = 24
    private static let expansionStep = 24
    private static let maximumExpansionLimit = 120

    private struct RenderState {
        let snapshot: UserKnowledgeGraphSnapshot
        let layout: UserKnowledgeGraphLayout
    }

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case graph = "图谱"
        case list = "列表"
        var id: Self { self }
    }

    var body: some View {
        ZStack {
            CulturePageBackground()
                .ignoresSafeArea()

            Group {
                if progressStore.graphNodeIDs.isEmpty {
                    emptyState
                } else if let renderState {
                    if displayMode == .graph {
                        graphViewport(renderState)
                    } else {
                        nodeList(renderState.snapshot)
                    }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            if let renderState, !progressStore.graphNodeIDs.isEmpty, displayMode == .graph {
                VStack {
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        graphLegendChip(renderState.snapshot)
                        Spacer(minLength: 0)
                        zoomControls
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索节点名称")
        .toolbar {
            if renderState != nil, !progressStore.graphNodeIDs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        filterMenu
                        displayModePicker
                        Button {
                            isCenterPickerPresented = true
                        } label: {
                            Label("选择中心", systemImage: "scope")
                        }
                        .accessibilityHint("选择一个或多个节点作为关系展开的中心")
                    }
                }
            }
        }
        .sheet(isPresented: $isCenterPickerPresented) {
            if let renderState {
                CenterPickerSheet(
                    snapshot: liveSnapshotBinding,
                    selectedCenterIDs: $selectedCenterIDs,
                    onToggle: { id in
                        toggleCenter(id)
                    },
                    onReset: {
                        selectedCenterIDs = []
                        scheduleRebuild()
                    }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            guard knowledgeStore == nil else { return }
            knowledgeStore = await KnowledgePackLoader.shared.store()
            didAttemptLoad = true
            scheduleRebuild()
        }
        .onChange(of: progressStore.graphNodeIDs) {
            scheduleRebuild()
        }
        .onChange(of: records.map(\.recordID)) {
            scheduleRebuild()
        }
        .onChange(of: sessionStore.sessionIDs) {
            scheduleRebuild()
        }
        .onChange(of: expansionLimit) {
            scheduleRebuild()
        }
        .onDisappear {
            rebuildTask?.cancel()
        }
    }

    /// Live view of the current render snapshot so the center picker sheet
    /// reflects graph rebuilds triggered by center toggles while it is open.
    private var liveSnapshotBinding: Binding<UserKnowledgeGraphSnapshot?> {
        Binding(
            get: { renderState?.snapshot },
            set: { _ in }
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("文化图谱还是空的", systemImage: "point.3.connected.trianglepath.dotted")
        } description: {
            Text("在对象或知识详情页点击“加入文化图谱”，这里会显示已加入节点，并从中心向外展开关系。")
        }
        .padding(CultureTheme.pagePadding)
    }

    // MARK: - Filtering & selection

    /// Nodes already captured in scan history get a prominent badge.
    private var recordedNodeIDs: Set<UUID> {
        Set(
            records.compactMap { $0.savedObject?.culturalElementID }
        )
    }

    private func matchesFilters(_ node: UserKnowledgeGraphNode) -> Bool {
        if !searchText.isEmpty,
            !node.name.localizedCaseInsensitiveContains(searchText)
        {
            return false
        }
        if let kindFilter, node.kind != kindFilter { return false }
        if let levelFilter, progressStore.level(for: node.id) != levelFilter { return false }
        return true
    }

    private var filtersActive: Bool {
        !searchText.isEmpty || kindFilter != nil || levelFilter != nil
    }

    /// The selected node plus its direct neighbors; empty when nothing is
    /// selected (no dimming applied).
    private func highlightSet(in snapshot: UserKnowledgeGraphSnapshot) -> Set<UUID> {
        guard let selectedNodeID else { return [] }
        var ids: Set<UUID> = [selectedNodeID]
        for edge in snapshot.edges {
            if edge.sourceID == selectedNodeID { ids.insert(edge.targetID) }
            if edge.targetID == selectedNodeID { ids.insert(edge.sourceID) }
        }
        return ids
    }

    private func nodeOpacity(
        _ node: UserKnowledgeGraphNode,
        snapshot: UserKnowledgeGraphSnapshot
    ) -> Double {
        if filtersActive, !matchesFilters(node) { return 0.12 }
        let highlight = highlightSet(in: snapshot)
        if !highlight.isEmpty, !highlight.contains(node.id) { return 0.3 }
        return 1
    }

    // MARK: - Toolbar

    private var displayModePicker: some View {
        Menu {
            ForEach(DisplayMode.allCases) { mode in
                Button {
                    displayMode = mode
                } label: {
                    if displayMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            Image(
                systemName: displayMode == .graph
                    ? "point.3.connected.trianglepath.dotted"
                    : "list.bullet"
            )
        }
        .accessibilityLabel("显示方式")
        .accessibilityValue(displayMode.rawValue)
    }

    private var filterMenu: some View {
        Menu {
            Menu("文化类别") {
                Button {
                    kindFilter = nil
                } label: {
                    if kindFilter == nil {
                        Label("全部", systemImage: "checkmark")
                    } else {
                        Text("全部")
                    }
                }
                ForEach(ConceptKind.allCases, id: \.self) { kind in
                    Button {
                        kindFilter = kind
                    } label: {
                        if kindFilter == kind {
                            Label(kind.rawValue, systemImage: "checkmark")
                        } else {
                            Label(kind.rawValue, systemImage: kind.systemImage)
                        }
                    }
                }
            }
            Menu("掌握程度") {
                Button {
                    levelFilter = nil
                } label: {
                    if levelFilter == nil {
                        Label("全部", systemImage: "checkmark")
                    } else {
                        Text("全部")
                    }
                }
                ForEach(KnowledgeLevel.allCases, id: \.self) { level in
                    Button {
                        levelFilter = level
                    } label: {
                        if levelFilter == level {
                            Label(level.rawValue, systemImage: "checkmark")
                        } else {
                            Text(level.rawValue)
                        }
                    }
                }
            }
            if filtersActive {
                Divider()
                Button("清除筛选") {
                    searchText = ""
                    kindFilter = nil
                    levelFilter = nil
                }
            }
        } label: {
            Image(systemName: filtersActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选节点")
    }

    // MARK: - Graph canvas

    private func graphViewport(_ state: RenderState) -> some View {
        // Pinch zoom is delegated to UIScrollView (ZoomableScrollView), so it
        // is anchored at the finger centroid instead of the canvas center.
        ZoomableScrollView(
            contentSize: CGSize(
                width: state.layout.size.width + 36,
                height: state.layout.size.height + 36
            ),
            zoomScale: $zoomScale,
            fittedZoomScale: $fittedZoomScale,
            centerRequest: $centerRequest,
            centerPoint: contentCenterPoint(in: state),
            fitOnAppear: true
        ) {
            ZStack {
                edgeCanvas(state)

                ForEach(state.snapshot.nodes) { node in
                    graphNodeButton(node, snapshot: state.snapshot)
                        .position(state.layout.positions[node.id] ?? .zero)
                        .opacity(nodeOpacity(node, snapshot: state.snapshot))
                }
            }
            .frame(width: state.layout.size.width, height: state.layout.size.height)
            .padding(18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("以可选择节点为中心的可缩放文化知识图谱")
        .accessibilityHint("双指缩放，单指拖动画布，点按节点查看邻居")
        .onChange(of: state.snapshot.centerID) {
            selectedNodeID = nil
            centerRequest += 1
        }
    }

    /// `padding(18)` sits inside the hosted content, so content coordinates
    /// are offset by 18 from layout coordinates.
    private func contentCenterPoint(in state: RenderState) -> CGPoint {
        if let centerID = state.snapshot.centerID,
            let position = state.layout.positions[centerID]
        {
            return CGPoint(x: position.x + 18, y: position.y + 18)
        }
        return CGPoint(
            x: (state.layout.size.width + 36) / 2,
            y: (state.layout.size.height + 36) / 2
        )
    }

    private func edgeCanvas(_ state: RenderState) -> some View {
        let highlight = highlightSet(in: state.snapshot)
        return Canvas { context, _ in
            for edge in state.snapshot.edges {
                let family = RelationSemanticFamily(kind: edge.kind)
                guard !hiddenFamilies.contains(family),
                    let source = state.layout.positions[edge.sourceID],
                    let target = state.layout.positions[edge.targetID]
                else { continue }

                let touchesSelection = selectedNodeID == nil
                    ? (state.snapshot.centerIDs.contains(edge.sourceID)
                        || state.snapshot.centerIDs.contains(edge.targetID))
                    : highlight.contains(edge.sourceID) && highlight.contains(edge.targetID)
                    && (edge.sourceID == selectedNodeID || edge.targetID == selectedNodeID)

                let geometry = GraphEdgeGeometry(
                    source: source,
                    target: target,
                    inset: UserKnowledgeGraphLayout.nodeSize.width / 2 + 4
                )
                var path = Path()
                path.move(to: geometry.start)
                path.addLine(to: geometry.end)
                var style = family.strokeStyle
                if !touchesSelection {
                    style = StrokeStyle(
                        lineWidth: max(style.lineWidth * 0.7, 1),
                        lineCap: .round,
                        dash: style.dash
                    )
                }
                context.stroke(
                    path,
                    with: .color(family.color.opacity(touchesSelection ? 0.8 : 0.24)),
                    style: style
                )

                // Arrowhead along the typed direction.
                var arrow = Path()
                arrow.move(to: geometry.end)
                arrow.addLine(to: geometry.arrowLeft)
                arrow.move(to: geometry.end)
                arrow.addLine(to: geometry.arrowRight)
                context.stroke(
                    arrow,
                    with: .color(family.color.opacity(touchesSelection ? 0.9 : 0.3)),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                )

                // Labels ride on the edges adjacent to the selected node (or
                // the center when nothing is selected).
                if touchesSelection, let kind = edge.kind {
                    let label = Text(kind.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(family.color)
                    context.draw(
                        context.resolve(label),
                        at: geometry.label,
                        anchor: .center
                    )
                }
            }
        }
        .frame(width: state.layout.size.width, height: state.layout.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func graphNodeButton(
        _ node: UserKnowledgeGraphNode,
        snapshot: UserKnowledgeGraphSnapshot
    ) -> some View {
        Button {
            withAnimation(.snappy) {
                selectedNodeID = selectedNodeID == node.id ? nil : node.id
            }
        } label: {
            graphNode(
                node,
                isCenter: snapshot.centerIDs.contains(node.id),
                isSelected: selectedNodeID == node.id,
                isRecorded: recordedNodeIDs.contains(node.id),
                isMissingPrerequisite: missingPrerequisiteIDs.contains(node.id)
            )
        }
        .buttonStyle(.plain)
        // System-style preview anchored at the node itself (like a long-press
        // preview), instead of a detached bottom banner.
        .popover(
            isPresented: Binding(
                get: { selectedNodeID == node.id },
                set: { if !$0 { selectedNodeID = nil } }
            ),
            arrowEdge: .top
        ) {
            selectionPopup(node)
        }
        .contextMenu {
            graphNodeActions(node)
        }
    }

    private func graphNode(
        _ node: UserKnowledgeGraphNode,
        isCenter: Bool,
        isSelected: Bool,
        isRecorded: Bool,
        isMissingPrerequisite: Bool
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: isCenter ? "scope" : node.kind.systemImage)
                Text(nodeCaption(node, isCenter: isCenter))
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isCenter ? CultureTheme.antiqueGold : nodeAccent(node))

            LocalizedPackText(
                source: node.name,
                cacheNamespace: "element",
                cacheKey: node.elementKey
            )
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
                .stroke(
                    isSelected ? CultureTheme.cinnabar : nodeAccent(node),
                    lineWidth: isSelected || node.isJoined || isCenter ? 2 : 1
                )
        }
        .overlay(alignment: .topLeading) {
            if isRecorded {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(CultureTheme.cinnabar, in: Circle())
                    .overlay {
                        Circle().stroke(CultureTheme.canvas, lineWidth: 2)
                    }
                    .offset(x: -6, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isMissingPrerequisite, !isCenter {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(CultureTheme.cinnabar)
                    .padding(6)
            }
        }
        .shadow(color: .black.opacity(isCenter ? 0.13 : 0.04), radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 19))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                node.name,
                nodeCaption(node, isCenter: isCenter),
                isRecorded ? String(localized: "已记录") : nil,
                isMissingPrerequisite ? String(localized: "前置知识尚未掌握") : nil,
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
        .accessibilityHint("点按查看邻居；长按可设为中心")
    }

    /// Popover preview shown at the node's own position: name, type/mastery,
    /// a short summary, and the detail / re-center actions.
    private func selectionPopup(_ node: UserKnowledgeGraphNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: node.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(nodeAccent(node))

                VStack(alignment: .leading, spacing: 3) {
                    LocalizedPackText(
                        source: node.name,
                        cacheNamespace: "element",
                        cacheKey: node.elementKey
                    )
                    .font(.headline)
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .lineLimit(1)
                    Text(nodeCaption(node, isCenter: false))
                        .font(.caption)
                        .foregroundStyle(CultureTheme.inkSecondary)
                }

                Spacer(minLength: 8)
            }

            if !node.summary.isEmpty {
                Text(node.summary)
                    .font(.subheadline)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                if let route = route(for: node) {
                    Button {
                        selectedNodeID = nil
                        onNavigate?(route)
                    } label: {
                        Label("查看详情", systemImage: "arrow.right.circle")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.cinnabar)
                }
                Button {
                    selectedNodeID = nil
                    toggleCenter(node.id)
                } label: {
                    let isCenter = renderState?.snapshot.centerIDs.contains(node.id) ?? false
                    Label(isCenter ? "取消中心" : "设为中心", systemImage: "scope")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func graphNodeActions(_ node: UserKnowledgeGraphNode) -> some View {
        // The canvas is hosted in a UIHostingController (ZoomableScrollView),
        // so NavigationLink has no stack to push into — route via onNavigate.
        if let route = route(for: node), let onNavigate {
            Button {
                onNavigate(route)
            } label: {
                Label("查看详情", systemImage: "arrow.right.circle")
            }
        }

        Button {
            toggleCenter(node.id)
        } label: {
            let isCenter = renderState?.snapshot.centerIDs.contains(node.id) ?? false
            Label(isCenter ? "取消中心" : "设为中心", systemImage: "scope")
        }

        Menu {
            ForEach(KnowledgeLevel.allCases, id: \.self) { level in
                Button {
                    withAnimation(.snappy) {
                        progressStore.setLevel(
                            level,
                            for: node.id,
                            source: .manual,
                            elementID: node.id
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

    // MARK: - Legend & zoom

    private func graphLegendChip(_ snapshot: UserKnowledgeGraphSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(progressStore.graphNodeIDs.count) 已加入 · \(snapshot.nodes.count) 展示")
                    .font(.caption2)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .lineLimit(1)
                if snapshot.isExpansionTruncated {
                    Button {
                        expansionLimit = min(
                            expansionLimit + Self.expansionStep,
                            Self.maximumExpansionLimit
                        )
                    } label: {
                        Label("已截断，展开更多", systemImage: "ellipsis.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CultureTheme.cinnabar)
                    }
                    .accessibilityHint("当前只展示了部分节点，双击增加展示数量")
                }
            }

            HStack(spacing: 8) {
                ForEach(RelationSemanticFamily.allCases, id: \.self) { family in
                    Button {
                        withAnimation(.snappy) {
                            if hiddenFamilies.contains(family) {
                                hiddenFamilies.remove(family)
                            } else {
                                hiddenFamilies.insert(family)
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: family.systemImage)
                            Text(family.rawValue)
                        }
                        .font(.caption2)
                        .foregroundStyle(
                            hiddenFamilies.contains(family)
                                ? CultureTheme.inkSecondary.opacity(0.4)
                                : family.color
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(family.rawValue)关系")
                    .accessibilityValue(hiddenFamilies.contains(family) ? "已隐藏" : "已显示")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoomScale = GraphZoom.decreased(from: zoomScale)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 32, height: 32)
            }
            .disabled(zoomScale <= GraphZoom.minimumScale)

            Button {
                zoomScale = fittedZoomScale
                centerRequest += 1
            } label: {
                Text(GraphZoom.percentageText(for: zoomScale))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(minWidth: 42)
            }
            .accessibilityLabel("恢复适合屏幕大小")
            .accessibilityValue(GraphZoom.percentageText(for: zoomScale))

            Button {
                zoomScale = GraphZoom.increased(from: zoomScale)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 32, height: 32)
            }
            .disabled(zoomScale >= GraphZoom.maximumScale)
        }
        .foregroundStyle(CultureTheme.inkPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - List mode

    private func nodeList(_ snapshot: UserKnowledgeGraphSnapshot) -> some View {
        let nodes = snapshot.nodes.filter(matchesFilters)
        return ScrollView {
            LazyVStack(spacing: 12) {
                if nodes.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的节点",
                        systemImage: "magnifyingglass",
                        description: Text("调整搜索或筛选条件后再试。")
                    )
                    .padding(.top, 60)
                }
                ForEach(nodes) { node in
                    if let route = route(for: node) {
                        NavigationLink(value: route) {
                            nodeListRow(node, snapshot: snapshot)
                        }
                        .buttonStyle(.plain)
                    } else {
                        nodeListRow(node, snapshot: snapshot)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func nodeListRow(_ node: UserKnowledgeGraphNode, snapshot: UserKnowledgeGraphSnapshot) -> some View {
        let isCenter = snapshot.centerIDs.contains(node.id)
        return HStack(spacing: 12) {
            Image(systemName: node.kind.systemImage)
                .font(.headline)
                .foregroundStyle(nodeAccent(node))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                LocalizedPackText(
                    source: node.name,
                    cacheNamespace: "element",
                    cacheKey: node.elementKey
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.inkPrimary)
                Text(isCenter ? "当前中心" : nodeCaption(node, isCenter: false))
                    .font(.caption2)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }

            Spacer(minLength: 8)

            if recordedNodeIDs.contains(node.id) {
                Label("已记录", systemImage: "checkmark.seal.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CultureTheme.cinnabar)
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("已记录")
            }

            Button {
                toggleCenter(node.id)
                displayMode = .graph
            } label: {
                Image(systemName: "scope")
                    .foregroundStyle(isCenter ? CultureTheme.cinnabar : CultureTheme.inkPrimary)
            }
            .accessibilityLabel(isCenter ? "取消中心" : "设为中心")
        }
        .padding(14)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Rebuild & resolution

    private func route(for node: UserKnowledgeGraphNode) -> AppRoute? {
        if knowledgeStore?.element(id: node.id) != nil {
            return .knowledgeElement(node.id)
        }
        if let elementKey = node.elementKey,
            let id = knowledgeStore?.resolveElementID(elementKey)
                ?? UUID(uuidString: elementKey),
            knowledgeStore?.element(id: id) != nil
        {
            return .knowledgeElement(id)
        }
        if object(id: node.id) != nil {
            return .object(node.id)
        }
        if concept(id: node.id) != nil {
            return .concept(node.id)
        }
        return nil
    }

    private func toggleCenter(_ id: UUID) {
        if selectedCenterIDs.contains(id) {
            selectedCenterIDs.remove(id)
        } else {
            selectedCenterIDs.insert(id)
        }
        scheduleRebuild()
    }

    /// Coalesces rapid state changes (joins, history sync, center switches)
    /// into a single graph rebuild (design 0007 性能).
    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            rebuildGraph()
        }
    }

    private func rebuildGraph() {
        guard let knowledgeStore else {
            renderState = nil
            return
        }
        guard !progressStore.graphNodeIDs.isEmpty else {
            selectedCenterIDs = []
            renderState = nil
            return
        }

        let snapshot = knowledgeStore.userKnowledgeGraph(
            // Sorted so the layout stays deterministic across rebuilds.
            centerIDs: selectedCenterIDs.sorted(by: { $0.uuidString < $1.uuidString }),
            joinedSeeds: joinedSeeds,
            maximumExpandedNodes: expansionLimit
        )

        // Missing prerequisites of the primary center: closure minus nodes
        // the user already understands or masters.
        if let centerID = snapshot.centerID,
            knowledgeStore.element(id: centerID) != nil
        {
            let knownIDs = Set(
                progressStore.entriesByID.values.compactMap { entry -> UUID? in
                    entry.level == .contact
                      ? nil
                      : (entry.elementKey.flatMap(UUID.init(uuidString:)) ?? entry.nodeID)
                }
            )
            missingPrerequisiteIDs = Set(
                knowledgeStore.missingPrerequisites(
                    id: centerID,
                    known: knownIDs,
                    maxCount: 12
                )
                .map(\.id)
            )
        } else {
            missingPrerequisiteIDs = []
        }

        renderState = RenderState(
            snapshot: snapshot,
            layout: UserKnowledgeGraphLayout(snapshot: snapshot)
        )
    }

    /// Decoded history indexes, built once per rebuild so each record's JSON
    /// snapshot is decoded at most once instead of once per joined node.
    private struct HistoryIndexes {
        let objectsByID: [UUID: CultureObject]
        let conceptsByID: [UUID: CultureConcept]
    }

    private var historyIndexes: HistoryIndexes {
        var objectsByID: [UUID: CultureObject] = [:]
        var conceptsByID: [UUID: CultureConcept] = [:]
        for record in records {
            guard let object = record.savedObject else { continue }
            objectsByID[object.id] = object
            for concept in object.concepts {
                conceptsByID[concept.id] = concept
            }
        }
        return HistoryIndexes(objectsByID: objectsByID, conceptsByID: conceptsByID)
    }

    private var joinedSeeds: [UserKnowledgeGraphSeed] {
        let indexes = historyIndexes
        return progressStore.graphNodeIDs.map { id in
            if let object = sessionStore.object(id: id) ?? indexes.objectsByID[id]
                ?? SampleCultureData.object(id: id)
            {
                return UserKnowledgeGraphSeed(
                    id: id,
                    name: object.canonicalName,
                    summary: object.summary
                )
            }
            if let concept = sessionStore.concept(id: id) ?? indexes.conceptsByID[id]
                ?? SampleCultureData.concept(id: id)
            {
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
        if let indexed = historyIndexes.objectsByID[id] {
            return indexed
        }
        return SampleCultureData.object(id: id)
    }

    private func concept(id: UUID) -> CultureConcept? {
        if let sessionConcept = sessionStore.concept(id: id) {
            return sessionConcept
        }
        if let indexed = historyIndexes.conceptsByID[id] {
            return indexed
        }
        return SampleCultureData.concept(id: id)
    }

    private func nodeCaption(_ node: UserKnowledgeGraphNode, isCenter: Bool) -> String {
        if isCenter { return String(localized: "当前中心") }
        if let level = progressStore.level(for: node.id) {
            return level.localizedTitle
        }
        return node.kind.localizedTitle
    }

    private func nodeAccent(_ node: UserKnowledgeGraphNode) -> Color {
        if node.isJoined { return CultureTheme.antiqueGold }
        switch node.hop {
        case 1: return CultureTheme.cinnabar
        case 2: return CultureTheme.antiqueGold
        default: return CultureTheme.inkSecondary
        }
    }
}

/// Searchable multi-select center picker (design 0007, 多中心发散).
/// Empty selection means "every joined node"; tapping rows toggles centers.
private struct CenterPickerSheet: View {
    /// Live binding to the current render snapshot — center toggles rebuild
    /// the graph while the sheet is open, and the list must reflect that.
    @Binding var snapshot: UserKnowledgeGraphSnapshot?
    /// Resolved centers of the current render (defaults included), used to
    /// show checkmarks; toggling goes through `onToggle`.
    @Binding var selectedCenterIDs: Set<UUID>
    let onToggle: (UUID) -> Void
    let onReset: () -> Void

    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var effectiveCenterIDs: Set<UUID> {
        selectedCenterIDs.isEmpty ? Set(snapshot?.centerIDs ?? []) : selectedCenterIDs
    }

    private func matches(_ node: UserKnowledgeGraphNode) -> Bool {
        searchText.isEmpty
            || node.name.localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                let joined = (snapshot?.nodes ?? []).filter(\.isJoined).filter(matches)
                let discovered = (snapshot?.nodes ?? []).filter { !$0.isJoined }.filter(matches)
                Section {
                    Text(
                        selectedCenterIDs.isEmpty
                            ? "当前默认以全部已加入节点为中心向外发散。"
                            : "已选择 \(selectedCenterIDs.count) 个中心，各自向外发散三层。"
                    )
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
                }
                if !joined.isEmpty {
                    Section("已加入") {
                        ForEach(joined) { node in
                            centerRow(node)
                        }
                    }
                }
                if !discovered.isEmpty {
                    Section("展开关系") {
                        ForEach(discovered) { node in
                            centerRow(node)
                        }
                    }
                }
                if joined.isEmpty && discovered.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的节点",
                        systemImage: "magnifyingglass"
                    )
                }
            }
            .searchable(text: $searchText, prompt: "搜索中心节点")
            .navigationTitle("选择中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("重置为全部已加入", action: onReset)
                        .disabled(selectedCenterIDs.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func centerRow(_ node: UserKnowledgeGraphNode) -> some View {
        Button {
            onToggle(node.id)
        } label: {
            HStack {
                Label(node.name, systemImage: node.kind.systemImage)
                Spacer()
                if effectiveCenterIDs.contains(node.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CultureTheme.cinnabar)
                }
            }
        }
        .foregroundStyle(CultureTheme.inkPrimary)
        .accessibilityHint(
            effectiveCenterIDs.contains(node.id) ? "取消该中心" : "设为中心"
        )
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
