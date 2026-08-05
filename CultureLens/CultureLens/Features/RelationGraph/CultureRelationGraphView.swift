import Foundation
import SwiftUI

struct CultureRelationGraphView: View {
  enum Presentation {
    case inlineInteractive
    case expandablePreview
    case fullscreen
  }

  enum DisplayMode: String, CaseIterable, Identifiable {
    case graph = "图谱"
    case list = "列表"
    var id: Self { self }
  }

  let object: CultureObject
  var presentation: Presentation = .inlineInteractive

  @Environment(\.dismiss) private var dismiss
  @State private var displayMode: DisplayMode = .graph
  @State private var isFullscreenPresented = false
  @State private var zoomScale: CGFloat = 1
  @State private var fittedZoomScale: CGFloat = 1
  @State private var didInitializeZoom = false
  @State private var centerRequest = 0
  /// Layout is computed once per object instead of on every body evaluation,
  /// so pinch-to-zoom frames never rerun the BFS.
  @State private var layout: GraphLayout
  @State private var hiddenFamilies: Set<RelationSemanticFamily> = []
  @GestureState private var transientMagnification: CGFloat = 1

  init(object: CultureObject, presentation: Presentation = .inlineInteractive) {
    self.object = object
    self.presentation = presentation
    _layout = State(initialValue: GraphLayout(object: object))
  }

  private var prerequisiteCount: Int {
    object.relations.count {
      $0.kind == .prerequisiteFor && $0.targetID == object.id
    }
  }

  @ViewBuilder
  var body: some View {
    switch presentation {
    case .inlineInteractive:
      interactiveContent
    case .expandablePreview:
      expandablePreview
        .fullScreenCover(isPresented: $isFullscreenPresented) {
          NavigationStack {
            CultureRelationGraphView(object: object, presentation: .fullscreen)
              .navigationDestination(for: AppRoute.self) { route in
                fullscreenDestination(for: route)
              }
          }
          .tint(CultureTheme.cinnabar)
        }
    case .fullscreen:
      fullscreenContent
    }
  }

  private var interactiveContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      header(showsDisplayModePicker: true)

      if object.relations.isEmpty {
        unavailableGraph
      } else if displayMode == .graph {
        graph
      } else {
        relationList
      }
    }
  }

  private var expandablePreview: some View {
    VStack(alignment: .leading, spacing: 16) {
      header(showsDisplayModePicker: false)

      if object.relations.isEmpty {
        unavailableGraph
      } else {
        Button {
          isFullscreenPresented = true
        } label: {
          staticGraphPreview
        }
        .buttonStyle(.plain)
        .accessibilityLabel("全屏查看\(object.canonicalName)文化知识图谱")
        .accessibilityHint("全屏后可以拖动、缩放并打开概念详情")
      }
    }
  }

  private var fullscreenContent: some View {
    ZStack {
      CulturePageBackground()
        .ignoresSafeArea()

      Group {
        if object.relations.isEmpty {
          unavailableGraph
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayMode == .graph {
          zoomableGraph
        } else {
          ScrollView {
            relationList
              .padding(.horizontal, 20)
              .padding(.top, 72)
              .padding(.bottom, 20)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea()

      VStack(spacing: 0) {
        fullscreenFloatingToolbar
        Spacer(minLength: 0)
        if displayMode == .graph, !object.relations.isEmpty {
          familyLegend
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
  }

  private var fullscreenFloatingToolbar: some View {
    HStack(spacing: 12) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)
          .frame(width: 40, height: 40)
          .background(.ultraThinMaterial, in: Circle())
      }
      .accessibilityLabel("关闭")

      Text("文化知识图谱")
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
        .lineLimit(1)

      Spacer(minLength: 8)

      HStack(spacing: 4) {
        displayModePicker

        if displayMode == .graph, !object.relations.isEmpty {
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
      }
      .foregroundStyle(CultureTheme.inkPrimary)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(.ultraThinMaterial, in: Capsule())
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }

  /// Empty-state attribution (design 0007): an object without relations is
  /// either unmatched to the knowledge base, the pack failed to load, or the
  /// node genuinely has no relation edges — three different messages.
  private var unavailableGraph: some View {
    if object.culturalElementKey == nil {
      ContentUnavailableView(
        "未匹配到知识库对象",
        systemImage: "questionmark.circle",
        description: Text("当前结果还没有绑定到知识库中的文化元素，因此没有可展示的关系。")
      )
      .frame(minHeight: 220)
    } else if KnowledgeStore.shared == nil {
      ContentUnavailableView(
        "知识包未载入",
        systemImage: "externaldrive.badge.exclamationmark",
        description: Text("知识库数据包没有成功载入，关系图谱暂时不可用。")
      )
      .frame(minHeight: 220)
    } else {
      ContentUnavailableView(
        "暂无关系边",
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text("知识库中该节点还没有记录可验证的关系边。")
      )
      .frame(minHeight: 220)
    }
  }

  private func header(showsDisplayModePicker: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("文化知识图谱")
          .font(.cultureSerif(.title2))
          .foregroundStyle(CultureTheme.inkPrimary)

        Spacer(minLength: 12)

        if showsDisplayModePicker {
          displayModePicker
        }
      }

      if prerequisiteCount > 0 {
        Label(
          "看懂\(object.canonicalName)前，建议先了解 \(prerequisiteCount) 项基础知识",
          systemImage: "books.vertical"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.cinnabar)
      }
    }
  }

  private var displayModePicker: some View {
    Picker("显示方式", selection: $displayMode) {
      ForEach(DisplayMode.allCases) { mode in
        Text(mode.rawValue).tag(mode)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
  }

  private var graph: some View {
    VStack(alignment: .leading, spacing: 10) {
      ScrollViewReader { proxy in
        ScrollView([.horizontal, .vertical]) {
          graphCanvas(layout: layout, linksEnabled: true)
          .padding(18)
        }
        .onAppear {
          centerGraph(using: proxy)
        }
        .onChange(of: object.id) {
          layout = GraphLayout(object: object)
          centerGraph(using: proxy)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: min(layout.size.height + 36, 520))
      .scrollIndicators(.visible)
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 28))
      .overlay {
        RoundedRectangle(cornerRadius: 28)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
      .clipShape(RoundedRectangle(cornerRadius: 28))
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(object.canonicalName)有向文化知识图谱")

      familyLegend
    }
  }

  /// Tappable semantic-family legend; tapping a family hides/shows its edges.
  private var familyLegend: some View {
    HStack(spacing: 12) {
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
          HStack(spacing: 4) {
            Image(systemName: family.systemImage)
              .font(.caption2)
            Text(family.rawValue)
          }
          .foregroundStyle(
            hiddenFamilies.contains(family) ? CultureTheme.inkSecondary.opacity(0.4) : family.color
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(family.rawValue)关系")
        .accessibilityValue(hiddenFamilies.contains(family) ? "已隐藏" : "已显示")
        .accessibilityHint("双击切换显示")
      }
      Spacer()
      Label("可拖动", systemImage: "hand.draw")
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .font(.caption2)
  }

  private var staticGraphPreview: some View {
    let contentSize = CGSize(width: layout.size.width + 36, height: layout.size.height + 36)

    // Fit the whole graph into the keyhole frame instead of clipping it at
    // 100% scale (design 0007: preview uses GraphZoom.fittedScale).
    return GeometryReader { proxy in
      let scale = GraphZoom.fittedScale(contentSize: contentSize, viewportSize: proxy.size)
      graphCanvas(layout: layout, linksEnabled: false)
        .padding(18)
        .scaleEffect(scale)
        .frame(width: contentSize.width * scale, height: contentSize.height * scale)
        .frame(width: proxy.size.width, height: proxy.size.height)
        .accessibilityHidden(true)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 270)
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 28))
      .overlay {
        RoundedRectangle(cornerRadius: 28)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
      .overlay(alignment: .bottomTrailing) {
        Label("点击全屏查看", systemImage: "arrow.up.left.and.arrow.down.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(12)
          .accessibilityHidden(true)
      }
      .clipShape(RoundedRectangle(cornerRadius: 28))
  }

  private var zoomableGraph: some View {
    let contentSize = CGSize(width: layout.size.width + 36, height: layout.size.height + 36)
    let effectiveScale = GraphZoom.clamped(zoomScale * transientMagnification)

    return GeometryReader { proxy in
      let scaledSize = CGSize(
        width: contentSize.width * effectiveScale,
        height: contentSize.height * effectiveScale
      )

      ScrollViewReader { scrollProxy in
        ScrollView([.horizontal, .vertical]) {
          graphCanvas(layout: layout, linksEnabled: true)
            .padding(18)
            .scaleEffect(effectiveScale)
            .frame(width: scaledSize.width, height: scaledSize.height)
            .frame(
              width: max(scaledSize.width, proxy.size.width),
              height: max(scaledSize.height, proxy.size.height)
            )
        }
        .defaultScrollAnchor(.center)
        .scrollIndicators(.visible)
        .simultaneousGesture(
          MagnifyGesture()
            .updating($transientMagnification) { value, state, _ in
              state = value.magnification
            }
            .onEnded { value in
              zoomScale = GraphZoom.clamped(zoomScale * value.magnification)
            }
        )
        .onAppear {
          configureInitialZoom(contentSize: contentSize, viewportSize: proxy.size)
          centerGraph(using: scrollProxy)
        }
        .onChange(of: proxy.size) {
          updateFittedZoom(contentSize: contentSize, viewportSize: proxy.size)
        }
        .onChange(of: object.id) {
          layout = GraphLayout(object: object)
          didInitializeZoom = false
          configureInitialZoom(contentSize: contentSize, viewportSize: proxy.size)
          centerGraph(using: scrollProxy)
        }
        .onChange(of: centerRequest) {
          centerGraph(using: scrollProxy)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(object.canonicalName)可缩放有向文化知识图谱")
      .accessibilityHint("双指缩放，单指拖动画布")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(CultureTheme.surface)
    .ignoresSafeArea()
  }

  private func graphCanvas(layout: GraphLayout, linksEnabled: Bool) -> some View {
    ZStack {
      ForEach(object.relations) { relation in
        if !hiddenFamilies.contains(RelationSemanticFamily(kind: relation.kind)),
          let source = layout.positions[relation.sourceID],
          let target = layout.positions[relation.targetID]
        {
          relationEdge(
            relation,
            source: source,
            target: target,
            showsLabel: relation.sourceID == object.id
              || relation.targetID == object.id
          )
        }
      }

      objectNode
        .id(object.id)
        .position(layout.positions[object.id] ?? .zero)

      ForEach(object.concepts) { concept in
        if let position = layout.positions[concept.id] {
          if linksEnabled {
            NavigationLink(value: AppRoute.concept(concept.id)) {
              conceptNode(concept)
            }
            .buttonStyle(.plain)
            .position(position)
          } else {
            conceptNode(concept)
              .position(position)
          }
        }
      }
    }
    .frame(width: layout.size.width, height: layout.size.height)
  }

  private var relationList: some View {
    LazyVStack(spacing: 12) {
      ForEach(object.relations) { relation in
        if let concept = navigableConcept(for: relation) {
          NavigationLink(value: AppRoute.concept(concept.id)) {
            relationRow(relation)
          }
          .buttonStyle(.plain)
        } else {
          relationRow(relation)
        }
      }
    }
  }

  private var objectNode: some View {
    VStack(spacing: 7) {
      Image(systemName: object.artworkSymbol)
        .font(.title2)
      Text("当前对象")
        .font(.caption2)
        .foregroundStyle(CultureTheme.antiqueGold)
      LocalizedPackText(
        source: object.canonicalName,
        cacheNamespace: "element",
        cacheKey: objectElementKey
      )
      .font(.headline)
      .lineLimit(1)
    }
    .foregroundStyle(.white)
    .frame(width: 136, height: 100)
    .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24)
        .stroke(CultureTheme.antiqueGold, lineWidth: 2)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("当前对象，\(object.canonicalName)")
  }

  private func conceptNode(_ concept: CultureConcept) -> some View {
    VStack(spacing: 5) {
      HStack(spacing: 5) {
        Image(systemName: concept.kind.systemImage)
        Text(concept.kind.localizedTitle)
      }
      .font(.caption2)
      .foregroundStyle(color(for: concept.kind))

      LocalizedPackText(
        source: concept.name,
        cacheNamespace: "element",
        cacheKey: KnowledgeStore.shared?.elementKey(for: concept.id)
      )
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(CultureTheme.inkPrimary)
      .multilineTextAlignment(.center)
      .lineLimit(2)
    }
    .frame(width: 138, height: 82)
    .background(CultureTheme.canvas, in: RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(color(for: concept.kind).opacity(0.72), lineWidth: 1.2)
    }
    .contentShape(RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(concept.kind.localizedTitle)，\(concept.name)")
    .accessibilityHint("打开概念详情")
  }

  private func relationEdge(
    _ relation: CultureRelation,
    source: CGPoint,
    target: CGPoint,
    showsLabel: Bool
  ) -> some View {
    let geometry = GraphEdgeGeometry(source: source, target: target)
    let family = RelationSemanticFamily(kind: relation.kind)
    let edgeColor = family.color

    return ZStack {
      Path { path in
        path.move(to: geometry.start)
        path.addLine(to: geometry.end)
      }
      .stroke(edgeColor.opacity(0.76), style: family.strokeStyle)

      Path { path in
        path.move(to: geometry.end)
        path.addLine(to: geometry.arrowLeft)
        path.move(to: geometry.end)
        path.addLine(to: geometry.arrowRight)
      }
      .stroke(edgeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

      if showsLabel {
        Text(relation.kind.localizedTitle)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(edgeColor)
          .padding(.horizontal, 7)
          .padding(.vertical, 4)
          .background(CultureTheme.surface.opacity(0.96), in: Capsule())
          .overlay {
            Capsule().stroke(edgeColor.opacity(0.25), lineWidth: 0.5)
          }
          .position(geometry.label)
      }
    }
    .accessibilityHidden(true)
  }

  private func centerGraph(using proxy: ScrollViewProxy) {
    Task { @MainActor in
      proxy.scrollTo(object.id, anchor: .center)
      // Zoom/frame updates land on the next layout pass; scroll again so the
      // current object stays visually centered after that settle.
      await Task.yield()
      proxy.scrollTo(object.id, anchor: .center)
    }
  }

  private func configureInitialZoom(contentSize: CGSize, viewportSize: CGSize) {
    updateFittedZoom(contentSize: contentSize, viewportSize: viewportSize)
    guard !didInitializeZoom else { return }
    zoomScale = 1
    didInitializeZoom = true
    centerRequest += 1
  }

  private func updateFittedZoom(contentSize: CGSize, viewportSize: CGSize) {
    fittedZoomScale = GraphZoom.fittedScale(
      contentSize: contentSize,
      viewportSize: viewportSize
    )
  }

  @ViewBuilder
  private func fullscreenDestination(for route: AppRoute) -> some View {
    switch route {
    case .concept(let id):
      if let concept = object.concepts.first(where: { $0.id == id }) {
        ConceptDetailView(concept: concept)
      } else {
        ContentUnavailableView(
          "未找到文化关系",
          systemImage: "point.3.connected.trianglepath.dotted"
        )
      }
    case .knowledgeElement(let key):
      if let concept = KnowledgeStore.shared?.cultureConcept(elementKey: key) {
        ConceptDetailView(concept: concept, elementKey: key)
      } else {
        ContentUnavailableView("知识节点暂不可用", systemImage: "externaldrive.badge.questionmark")
      }
    case .object(let id):
      if id == object.id {
        ObjectDetailView(object: object)
      } else if let sample = SampleCultureData.object(id: id) {
        ObjectDetailView(object: sample)
      } else {
        ContentUnavailableView("未找到对象", systemImage: "questionmark.circle")
      }
    default:
      ContentUnavailableView("当前入口不可用", systemImage: "questionmark.circle")
    }
  }

  private func relationRow(_ relation: CultureRelation) -> some View {
    let relationColor = RelationSemanticFamily(kind: relation.kind).color
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        LocalizedPackText(
          source: name(for: relation.sourceID),
          cacheNamespace: "element",
          cacheKey: elementKey(for: relation.sourceID)
        )
        .font(.subheadline.weight(.semibold))
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundStyle(relationColor)
        Text(relation.kind.localizedTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(relationColor)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(relationColor.opacity(0.1), in: Capsule())
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundStyle(relationColor)
        LocalizedPackText(
          source: name(for: relation.targetID),
          cacheNamespace: "element",
          cacheKey: elementKey(for: relation.targetID)
        )
        .font(.subheadline.weight(.semibold))
        Spacer(minLength: 0)
      }
      .foregroundStyle(CultureTheme.inkPrimary)

      Text(relation.explanation)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(16)
    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(name(for: relation.sourceID))，\(relation.kind.localizedTitle)，\(name(for: relation.targetID))。\(relation.explanation)"
    )
    .accessibilityHint(navigableConcept(for: relation) == nil ? "" : "打开相关概念")
  }

  private var objectElementKey: String? {
    object.culturalElementKey ?? KnowledgeStore.shared?.elementKey(for: object.id)
  }

  private func elementKey(for id: UUID) -> String? {
    if id == object.id {
      return objectElementKey
    }
    return KnowledgeStore.shared?.elementKey(for: id)
  }

  private func name(for id: UUID) -> String {
    if id == object.id {
      return object.canonicalName
    }
    return object.concepts.first { $0.id == id }?.name ?? String(localized: "未知节点")
  }

  private func navigableConcept(for relation: CultureRelation) -> CultureConcept? {
    object.concepts.first { $0.id == relation.targetID }
      ?? object.concepts.first { $0.id == relation.sourceID }
  }

  private func color(for conceptKind: ConceptKind) -> Color {
    switch conceptKind {
    case .foundation:
      CultureTheme.cinnabar
    case .institution, .history:
      CultureTheme.antiqueGold
    default:
      CultureTheme.inkSecondary
    }
  }
}

/// Object-graph layout: BFS hops from the object node, rendered through the
/// shared `RadialGraphLayout` kernel (barycenter ordering + abstraction
/// direction bias). Kept as a value type so views can cache it in `@State`.
struct GraphLayout {
  let positions: [UUID: CGPoint]
  let hops: [UUID: Int]
  let size: CGSize

  init(object: CultureObject) {
    let conceptIDs = Set(object.concepts.map(\.id))
    let nodeIDs = conceptIDs.union([object.id])
    var adjacency: [UUID: Set<UUID>] = [:]
    for relation in object.relations
    where nodeIDs.contains(relation.sourceID) && nodeIDs.contains(relation.targetID) {
      adjacency[relation.sourceID, default: []].insert(relation.targetID)
      adjacency[relation.targetID, default: []].insert(relation.sourceID)
    }

    var shortestHops: [UUID: Int] = [object.id: 0]
    var parentByID: [UUID: UUID] = [:]
    var queue: [UUID] = [object.id]
    var queueIndex = 0
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      let nextHop = (shortestHops[current] ?? 0) + 1
      for neighbor in adjacency[current, default: []]
      where shortestHops[neighbor] == nil {
        shortestHops[neighbor] = nextHop
        parentByID[neighbor] = current
        queue.append(neighbor)
      }
    }

    let outerReachableHop = shortestHops.values.max() ?? 0
    let disconnectedHop = max(outerReachableHop + 1, 1)
    for conceptID in conceptIDs where shortestHops[conceptID] == nil {
      shortestHops[conceptID] = disconnectedHop
    }

    // Direction bias from the edge that connects each node to its BFS parent.
    var directionOf: [UUID: AbstractionDirection] = [:]
    for concept in object.concepts {
      guard let parentID = parentByID[concept.id] else { continue }
      guard
        let relation = object.relations.first(where: {
          ($0.sourceID == parentID && $0.targetID == concept.id)
            || ($0.sourceID == concept.id && $0.targetID == parentID)
        })
      else { continue }
      let direction = relation.kind.abstractionDirection
      if relation.sourceID == parentID {
        // parent → node: up means the node is the more abstract end.
        directionOf[concept.id] = direction
      } else {
        // node → parent: invert the axis.
        switch direction {
        case .up: directionOf[concept.id] = .down
        case .down: directionOf[concept.id] = .up
        default: directionOf[concept.id] = direction
        }
      }
    }

    let layout = RadialGraphLayout(
      centerID: object.id,
      nodes: object.concepts.map {
        RadialGraphLayout.Node(
          id: $0.id,
          ring: shortestHops[$0.id] ?? disconnectedHop,
          name: $0.name
        )
      },
      edges: object.relations
        .filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }
        .map { ($0.sourceID, $0.targetID) },
      directionOf: directionOf,
      metrics: RadialGraphLayout.Metrics(
        nodeSize: CGSize(width: 138, height: 82),
        initialRadius: 220,
        ringSpacing: 190,
        circumferenceSpacing: 172,
        horizontalStretch: 1.14,
        verticalStretch: 0.86,
        margin: 100,
        directionBiasWeight: 0.45
      )
    )

    positions = layout.positions
    hops = shortestHops
    size = layout.size
  }
}

nonisolated enum GraphZoom {
  static let minimumScale: CGFloat = 0.5
  static let maximumScale: CGFloat = 2.5
  static let step: CGFloat = 0.25

  static func clamped(_ scale: CGFloat) -> CGFloat {
    min(max(scale, minimumScale), maximumScale)
  }

  static func increased(from scale: CGFloat) -> CGFloat {
    clamped(scale + step)
  }

  static func decreased(from scale: CGFloat) -> CGFloat {
    clamped(scale - step)
  }

  static func fittedScale(
    contentSize: CGSize,
    viewportSize: CGSize,
    minimum: CGFloat = minimumScale,
    maximum: CGFloat = 1
  ) -> CGFloat {
    guard
      contentSize.width > 0,
      contentSize.height > 0,
      viewportSize.width > 0,
      viewportSize.height > 0
    else {
      return min(max(1, minimum), maximum)
    }

    let widthScale = viewportSize.width / contentSize.width
    let heightScale = viewportSize.height / contentSize.height
    return min(max(min(widthScale, heightScale, maximum), minimum), maximum)
  }

  static func percentageText(for scale: CGFloat) -> String {
    "\(Int((clamped(scale) * 100).rounded()))%"
  }
}

#Preview {
  NavigationStack {
    ScrollView {
      CultureRelationGraphView(object: SampleCultureData.featured)
        .padding()
    }
    .background(CultureTheme.canvas)
  }
}
