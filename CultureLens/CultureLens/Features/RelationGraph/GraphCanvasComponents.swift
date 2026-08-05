import SwiftUI

/// Semantic grouping of the 12 `RelationKind`s into a handful of visually
/// distinguishable families (design 0007 关系语义族). Each family maps to one
/// color + line style + icon so legends, filters, and edges stay consistent
/// across both graph surfaces.
nonisolated enum RelationSemanticFamily: String, CaseIterable, Hashable, Sendable {
  /// 理解前先懂 / 组成
  case prerequisiteAndComposition = "前置与构成"
  /// 产生于 / 位于
  case temporalSpatialOrigin = "时空来源"
  /// 用于 / 制作采用
  case functionAndCraft = "功能与工艺"
  /// 象征 / 体现 / 受规制于 / 受到影响
  case meaningAndAesthetics = "意涵与审美"
  /// 相似于 / 解释
  case analogy = "类比"

  init(kind: RelationKind?) {
    switch kind {
    case .prerequisiteFor, .composedOf:
      self = .prerequisiteAndComposition
    case .emergedIn, .locatedIn:
      self = .temporalSpatialOrigin
    case .usedFor, .madeWith:
      self = .functionAndCraft
    case .symbolizes, .expresses, .governedBy, .influencedBy:
      self = .meaningAndAesthetics
    case .similarTo, .explains, .none:
      self = .analogy
    }
  }

  var systemImage: String {
    switch self {
    case .prerequisiteAndComposition: "books.vertical"
    case .temporalSpatialOrigin: "clock"
    case .functionAndCraft: "hammer"
    case .meaningAndAesthetics: "paintpalette"
    case .analogy: "circle.hexagongrid"
    }
  }
}

extension RelationSemanticFamily {
  var color: Color {
    switch self {
    case .prerequisiteAndComposition: CultureTheme.cinnabar
    case .temporalSpatialOrigin: CultureTheme.antiqueGold
    case .functionAndCraft: CultureTheme.inkPrimary
    case .meaningAndAesthetics: CultureTheme.inkSecondary
    case .analogy: CultureTheme.inkSecondary.opacity(0.65)
    }
  }

  var strokeStyle: StrokeStyle {
    switch self {
    case .prerequisiteAndComposition:
      StrokeStyle(lineWidth: 2.2, lineCap: .round)
    case .temporalSpatialOrigin:
      StrokeStyle(lineWidth: 1.8, lineCap: .round)
    case .functionAndCraft:
      StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [6, 4])
    case .meaningAndAesthetics:
      StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [8, 4])
    case .analogy:
      StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2, 4])
    }
  }
}

/// Edge endpoints inset from the node centers so lines stop at the card
/// boundary instead of running underneath it, plus arrowhead and label
/// anchor points. Shared by both graph surfaces.
nonisolated struct GraphEdgeGeometry {
  let start: CGPoint
  let end: CGPoint
  let arrowLeft: CGPoint
  let arrowRight: CGPoint
  let label: CGPoint

  init(source: CGPoint, target: CGPoint, inset: CGFloat = 78) {
    let dx = target.x - source.x
    let dy = target.y - source.y
    let distance = max(hypot(dx, dy), 1)
    let unitX = dx / distance
    let unitY = dy / distance
    let lineStart = CGPoint(
      x: source.x + unitX * inset,
      y: source.y + unitY * inset
    )
    let lineEnd = CGPoint(
      x: target.x - unitX * inset,
      y: target.y - unitY * inset
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
