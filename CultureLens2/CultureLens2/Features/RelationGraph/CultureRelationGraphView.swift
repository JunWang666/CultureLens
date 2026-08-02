import Foundation
import SwiftUI

struct CultureRelationGraphView: View {
  enum DisplayMode: String, CaseIterable, Identifiable {
    case graph = "图谱"
    case list = "列表"
    var id: Self { self }
  }

  let object: CultureObject
  @State private var displayMode: DisplayMode = .graph

  private var prerequisiteCount: Int {
    object.relations.count {
      $0.kind == .prerequisiteFor && $0.targetID == object.id
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header

      if object.relations.isEmpty {
        ContentUnavailableView(
          "关系资料不足",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text("当前结果还没有可验证的关系边。")
        )
        .frame(minHeight: 220)
      } else if displayMode == .graph {
        graph
      } else {
        relationList
      }
    }
  }

  private var header: some View {
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

        Picker("显示方式", selection: $displayMode) {
          ForEach(DisplayMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
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
                NavigationLink(value: AppRoute.concept(concept.id)) {
                  conceptNode(concept)
                }
                .buttonStyle(.plain)
                .position(position)
              }
            }
          }
          .frame(width: layout.size.width, height: layout.size.height)
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
