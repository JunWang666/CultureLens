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
  @GestureState private var transientMagnification: CGFloat = 1

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
    VStack(alignment: .leading, spacing: 16) {
      header(showsDisplayModePicker: true)

      if object.relations.isEmpty {
        unavailableGraph
      } else if displayMode == .graph {
        zoomableGraph
      } else {
        ScrollView {
          relationList
        }
      }
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 20)
    .background {
      CulturePageBackground()
        .ignoresSafeArea()
    }
    .navigationTitle("文化知识图谱")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Button {
          dismiss()
        } label: {
          Label("关闭", systemImage: "xmark")
            .labelStyle(.iconOnly)
        }
      }

      if displayMode == .graph, !object.relations.isEmpty {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            zoomScale = GraphZoom.decreased(from: zoomScale)
          } label: {
            Label("缩小", systemImage: "minus.magnifyingglass")
              .labelStyle(.iconOnly)
          }
          .disabled(zoomScale <= GraphZoom.minimumScale)

          Button {
            zoomScale = fittedZoomScale
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
            Label("放大", systemImage: "plus.magnifyingglass")
              .labelStyle(.iconOnly)
          }
          .disabled(zoomScale >= GraphZoom.maximumScale)
        }
      }
    }
  }

  private var unavailableGraph: some View {
    ContentUnavailableView(
      "关系资料不足",
      systemImage: "point.3.connected.trianglepath.dotted",
      description: Text("当前结果还没有可验证的关系边。")
    )
    .frame(minHeight: 220)
  }

  private func header(showsDisplayModePicker: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text("文化知识图谱")
            .font(.cultureSerif(.title2))
            .foregroundStyle(CultureTheme.inkPrimary)
          Text("沿箭头阅读：前置知识 → \(object.canonicalName) → 制度与文化延伸")
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkSecondary)
        }

        Spacer(minLength: 12)

        if showsDisplayModePicker {
          Picker("显示方式", selection: $displayMode) {
            ForEach(DisplayMode.allCases) { mode in
              Text(mode.rawValue).tag(mode)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
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

  private var graph: some View {
    let layout = GraphLayout(object: object)

    return VStack(alignment: .leading, spacing: 10) {
      ScrollViewReader { proxy in
        ScrollView([.horizontal, .vertical]) {
          graphCanvas(layout: layout, linksEnabled: true)
          .padding(18)
        }
        .onAppear {
          centerGraph(using: proxy)
        }
        .onChange(of: object.id) {
          centerGraph(using: proxy)
        }
      }
      .frame(height: min(layout.size.height + 36, 520))
      .scrollIndicators(.visible)
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 28))
      .overlay {
        RoundedRectangle(cornerRadius: 28)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(object.canonicalName)有向文化知识图谱")

      HStack(spacing: 14) {
        legendItem("前置知识", color: CultureTheme.cinnabar)
        legendItem("制度与语境", color: CultureTheme.antiqueGold)
        legendItem("其他关系", color: CultureTheme.inkSecondary)
        Spacer()
        Label("可拖动", systemImage: "hand.draw")
      }
      .font(.caption2)
      .foregroundStyle(CultureTheme.inkSecondary)
    }
  }

  private var staticGraphPreview: some View {
    let layout = GraphLayout(object: object)
    let contentSize = CGSize(width: layout.size.width + 36, height: layout.size.height + 36)

    return GeometryReader { proxy in
      let availableSize = CGSize(
        width: max(proxy.size.width - 24, 1),
        height: max(proxy.size.height - 24, 1)
      )
      let previewScale = GraphZoom.fittedScale(
        contentSize: contentSize,
        viewportSize: availableSize,
        minimum: 0.05
      )

      ZStack {
        graphCanvas(layout: layout, linksEnabled: false)
          .padding(18)
          .scaleEffect(previewScale)
          .frame(
            width: contentSize.width * previewScale,
            height: contentSize.height * previewScale
          )
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
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
    let layout = GraphLayout(object: object)
    let contentSize = CGSize(width: layout.size.width + 36, height: layout.size.height + 36)
    let effectiveScale = GraphZoom.clamped(zoomScale * transientMagnification)

    return GeometryReader { proxy in
      let scaledSize = CGSize(
        width: contentSize.width * effectiveScale,
        height: contentSize.height * effectiveScale
      )

      ScrollView([.horizontal, .vertical]) {
        ZStack {
          graphCanvas(layout: layout, linksEnabled: true)
            .padding(18)
            .scaleEffect(effectiveScale)
            .frame(width: scaledSize.width, height: scaledSize.height)
        }
        .frame(
          width: max(scaledSize.width, proxy.size.width),
          height: max(scaledSize.height, proxy.size.height)
        )
      }
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
      }
      .onChange(of: proxy.size) {
        updateFittedZoom(contentSize: contentSize, viewportSize: proxy.size)
      }
      .onChange(of: object.id) {
        didInitializeZoom = false
        configureInitialZoom(contentSize: contentSize, viewportSize: proxy.size)
      }
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 28))
      .overlay {
        RoundedRectangle(cornerRadius: 28)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(object.canonicalName)可缩放有向文化知识图谱")
      .accessibilityHint("双指缩放，单指拖动画布")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func graphCanvas(layout: GraphLayout, linksEnabled: Bool) -> some View {
    ZStack {
      ForEach(object.relations) { relation in
        if let source = layout.positions[relation.sourceID],
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
      Text(object.canonicalName)
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
        Text(concept.kind.rawValue)
      }
      .font(.caption2)
      .foregroundStyle(color(for: concept.kind))

      Text(concept.name)
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
    .accessibilityLabel("\(concept.kind.rawValue)，\(concept.name)")
    .accessibilityHint("打开概念详情")
  }

  private func relationEdge(
    _ relation: CultureRelation,
    source: CGPoint,
    target: CGPoint,
    showsLabel: Bool
  ) -> some View {
    let geometry = EdgeGeometry(source: source, target: target)
    let edgeColor = color(for: relation)

    return ZStack {
      Path { path in
        path.move(to: geometry.start)
        path.addLine(to: geometry.end)
      }
      .stroke(
        edgeColor.opacity(0.76),
        style: StrokeStyle(
          lineWidth: relation.kind == .prerequisiteFor ? 2.2 : 1.6,
          lineCap: .round,
          dash: relation.kind == .prerequisiteFor ? [] : [6, 4]
        )
      )

      Path { path in
        path.move(to: geometry.end)
        path.addLine(to: geometry.arrowLeft)
        path.move(to: geometry.end)
        path.addLine(to: geometry.arrowRight)
      }
      .stroke(edgeColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))

      if showsLabel {
        Text(relation.kind.rawValue)
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
    DispatchQueue.main.async {
      proxy.scrollTo(object.id, anchor: .center)
    }
  }

  private func configureInitialZoom(contentSize: CGSize, viewportSize: CGSize) {
    updateFittedZoom(contentSize: contentSize, viewportSize: viewportSize)
    guard !didInitializeZoom else { return }
    zoomScale = fittedZoomScale
    didInitializeZoom = true
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
    default:
      ContentUnavailableView("当前入口不可用", systemImage: "questionmark.circle")
    }
  }

  private func relationRow(_ relation: CultureRelation) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text(name(for: relation.sourceID))
          .font(.subheadline.weight(.semibold))
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundStyle(color(for: relation))
        Text(relation.kind.rawValue)
          .font(.caption.weight(.semibold))
          .foregroundStyle(color(for: relation))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(color(for: relation).opacity(0.1), in: Capsule())
        Image(systemName: "arrow.right")
          .font(.caption)
          .foregroundStyle(color(for: relation))
        Text(name(for: relation.targetID))
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
      "\(name(for: relation.sourceID))，\(relation.kind.rawValue)，\(name(for: relation.targetID))。\(relation.explanation)"
    )
    .accessibilityHint(navigableConcept(for: relation) == nil ? "" : "打开相关概念")
  }

  private func name(for id: UUID) -> String {
    if id == object.id {
      return object.canonicalName
    }
    return object.concepts.first { $0.id == id }?.name ?? "未知节点"
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

  private func color(for relation: CultureRelation) -> Color {
    switch relation.kind {
    case .prerequisiteFor:
      CultureTheme.cinnabar
    case .governedBy, .expresses, .explains:
      CultureTheme.antiqueGold
    default:
      CultureTheme.inkSecondary
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
}

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
    var queue: [UUID] = [object.id]
    var queueIndex = 0
    while queueIndex < queue.count {
      let current = queue[queueIndex]
      queueIndex += 1
      let nextHop = (shortestHops[current] ?? 0) + 1
      for neighbor in adjacency[current, default: []]
      where shortestHops[neighbor] == nil {
        shortestHops[neighbor] = nextHop
        queue.append(neighbor)
      }
    }

    let outerReachableHop = shortestHops.values.max() ?? 0
    let disconnectedHop = max(outerReachableHop + 1, 1)
    for conceptID in conceptIDs where shortestHops[conceptID] == nil {
      shortestHops[conceptID] = disconnectedHop
    }

    let conceptsByHop = Dictionary(grouping: object.concepts) {
      shortestHops[$0.id] ?? disconnectedHop
    }
    let orderedHops = conceptsByHop.keys.sorted()
    var radiusByHop: [Int: CGFloat] = [:]
    var previousRadius: CGFloat = 0
    for hop in orderedHops {
      let count = CGFloat(conceptsByHop[hop]?.count ?? 0)
      let circumferenceRadius = count * 172 / (2 * .pi)
      let minimumRadius: CGFloat = previousRadius == 0 ? 220 : previousRadius + 190
      let radius = max(minimumRadius, circumferenceRadius)
      radiusByHop[hop] = radius
      previousRadius = radius
    }

    let maximumRadius = radiusByHop.values.max() ?? 220
    let horizontalRadius = maximumRadius * 1.14
    let verticalRadius = maximumRadius * 0.86
    let center = CGPoint(x: horizontalRadius + 108, y: verticalRadius + 86)
    var result: [UUID: CGPoint] = [object.id: center]

    for hop in orderedHops {
      guard let concepts = conceptsByHop[hop], !concepts.isEmpty else { continue }
      let radius = radiusByHop[hop] ?? 220
      let orderedConcepts = concepts.sorted {
        if $0.name != $1.name { return $0.name < $1.name }
        return $0.id.uuidString < $1.id.uuidString
      }
      let angleStep = 2 * CGFloat.pi / CGFloat(orderedConcepts.count)
      let startingAngle =
        -CGFloat.pi / 2
        + (hop.isMultiple(of: 2) ? angleStep / 2 : 0)
      for (index, concept) in orderedConcepts.enumerated() {
        let angle = startingAngle + angleStep * CGFloat(index)
        result[concept.id] = CGPoint(
          x: center.x + cos(angle) * radius * 1.14,
          y: center.y + sin(angle) * radius * 0.86
        )
      }
    }

    positions = result
    hops = shortestHops
    size = CGSize(width: center.x * 2, height: center.y * 2)
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

private struct EdgeGeometry {
  let start: CGPoint
  let end: CGPoint
  let arrowLeft: CGPoint
  let arrowRight: CGPoint
  let label: CGPoint

  init(source: CGPoint, target: CGPoint) {
    let dx = target.x - source.x
    let dy = target.y - source.y
    let distance = max(hypot(dx, dy), 1)
    let unitX = dx / distance
    let unitY = dy / distance
    let sourceInset: CGFloat = 78
    let targetInset: CGFloat = 78
    let lineStart = CGPoint(
      x: source.x + unitX * sourceInset,
      y: source.y + unitY * sourceInset
    )
    let lineEnd = CGPoint(
      x: target.x - unitX * targetInset,
      y: target.y - unitY * targetInset
    )
    let arrowLength: CGFloat = 9
    let perpendicularX = -unitY
    let perpendicularY = unitX

    start = lineStart
    end = lineEnd
    arrowLeft = CGPoint(
      x: lineEnd.x - unitX * arrowLength + perpendicularX * 5,
      y: lineEnd.y - unitY * arrowLength + perpendicularY * 5
    )
    arrowRight = CGPoint(
      x: lineEnd.x - unitX * arrowLength - perpendicularX * 5,
      y: lineEnd.y - unitY * arrowLength - perpendicularY * 5
    )
    label = CGPoint(
      x: (lineStart.x + lineEnd.x) / 2 + perpendicularX * 12,
      y: (lineStart.y + lineEnd.y) / 2 + perpendicularY * 12
    )
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
