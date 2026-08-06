import Foundation

/// Severity of a pack validation finding.
nonisolated enum KnowledgePackIssueSeverity: String, Sendable, Hashable {
  case error
  case warning
}

nonisolated struct KnowledgePackIssue: Identifiable, Sendable, Hashable {
  let id: String
  let severity: KnowledgePackIssueSeverity
  let message: String

  init(severity: KnowledgePackIssueSeverity, message: String) {
    self.severity = severity
    self.message = message
    self.id = "\(severity.rawValue):\(message)"
  }
}

/// Structural checks for in-app pack editing / export (design 0006 export gate).
enum KnowledgePackValidator {
  nonisolated static func validate(_ pack: KnowledgePack) -> [KnowledgePackIssue] {
    var issues: [KnowledgePackIssue] = []
    let stamped = pack.withStampedContentRoles()
    let elementKeys = Set(stamped.elements.compactMap(\.key))
    let elementIDs = Set(stamped.elements.map(\.id))
    let attractionKeys = Set(stamped.attractions.compactMap(\.key))
    let attractionIDs = Set(stamped.attractions.map(\.id))
    let elementLabel: (UUID) -> String = { id in
      stamped.elements.first { $0.id == id }.flatMap(\.key) ?? id.uuidString
    }

    if stamped.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(severity: .error, message: "包版本号不能为空。"))
    }

    var seenElementKeys = Set<String>()
    for element in stamped.elements {
      let key = element.key ?? ""
      if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "存在空的元素 key。"))
      } else if !seenElementKeys.insert(key).inserted {
        issues.append(.init(severity: .error, message: "重复的元素 key：\(key)"))
      }
      if element.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "元素「\(key)」缺少名称。"))
      }
      if element.conceptKind == nil {
        issues.append(.init(severity: .warning, message: "元素「\(key)」缺少 conceptKind。"))
      } else if let raw = element.conceptKind, ConceptKind(rawValue: raw) == nil {
        issues.append(
          .init(severity: .error, message: "元素「\(key)」的 conceptKind 无效：\(raw)")
        )
      }
      if element.introduction.blocks.isEmpty {
        issues.append(.init(severity: .warning, message: "元素「\(key)」介绍为空。"))
      }
    }

    for attraction in stamped.attractions {
      let key = attraction.key ?? attraction.id.uuidString
      if let attractionKey = attraction.key, !elementKeys.contains(attractionKey) {
        issues.append(
          .init(
            severity: .error,
            message: "景点「\(key)」没有同 key 的元素节点。"
          )
        )
      }
      let role = stamped.elements.first { $0.key == attraction.key }
        .map { $0.resolvedContentRole(attractionKeys: attractionKeys) }
      if role == .history {
        issues.append(
          .init(
            severity: .error,
            message: "景点「\(key)」对应元素的 contentRole 应为看点。"
          )
        )
      }
    }

    for element in stamped.elements
    where element.resolvedContentRole(attractionKeys: attractionKeys) == .sight
    {
      guard let key = element.key else { continue }
      if !attractionKeys.contains(key) {
        issues.append(
          .init(
            severity: .warning,
            message: "看点「\(key)」未列入 attractions[]。"
          )
        )
      }
    }

    var missingKind = 0
    for relation in stamped.relations {
      let from = elementLabel(relation.elementId)
      let to = elementLabel(relation.relatedElementId)
      if !elementIDs.contains(relation.elementId) {
        issues.append(
          .init(
            severity: .error,
            message: "关系起点「\(from)」不存在。"
          )
        )
      }
      if !elementIDs.contains(relation.relatedElementId) {
        issues.append(
          .init(
            severity: .error,
            message: "关系终点「\(to)」不存在。"
          )
        )
      }
      if let kind = relation.kind {
        if RelationKind(rawValue: kind) == nil {
          issues.append(
            .init(
              severity: .error,
              message: "关系 kind 无效：\(kind)（\(from) → \(to)）"
            )
          )
        }
      } else {
        missingKind += 1
      }
      if (relation.explanation ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(
          .init(
            severity: .warning,
            message: "关系缺少 explanation：\(from) → \(to)"
          )
        )
      }
    }
    if missingKind > 0 {
      issues.append(
        .init(
          severity: .warning,
          message: "有 \(missingKind) 条关系缺少 kind（抽象阶梯与校验将忽略它们）。"
        )
      )
    }

    if let cycle = firstUpwardCycle(in: stamped) {
      issues.append(
        .init(
          severity: .error,
          message: "上行关系图存在环：\(cycle.joined(separator: " → "))"
        )
      )
    }

    for intro in stamped.introductions {
      let introKey = intro.key ?? intro.id.uuidString
      if !attractionIDs.contains(intro.attractionId) {
        issues.append(
          .init(
            severity: .error,
            message: "介绍「\(introKey)」的 attractionId「\(intro.attractionId.uuidString)」不存在。"
          )
        )
      }
      if !elementIDs.contains(intro.culturalElementId) {
        issues.append(
          .init(
            severity: .error,
            message: "介绍「\(introKey)」的 culturalElementId「\(intro.culturalElementId.uuidString)」不存在。"
          )
        )
      }
      if !(-90...90).contains(intro.latitude) || !(-180...180).contains(intro.longitude) {
        issues.append(
          .init(severity: .error, message: "介绍「\(introKey)」坐标超出范围。")
        )
      }
    }

    for theme in stamped.themes {
      let themeKey = theme.key ?? theme.id.uuidString
      for elementId in theme.elementIds where !elementIDs.contains(elementId) {
        issues.append(
          .init(
            severity: .error,
            message: "主题「\(themeKey)」引用了不存在的元素「\(elementLabel(elementId))」。"
          )
        )
      }
      if theme.minContacted < 1 {
        issues.append(
          .init(severity: .warning, message: "主题「\(themeKey)」的 minContacted 应 ≥ 1。")
        )
      }
    }

    if stamped.locales?["en"] == nil {
      issues.append(.init(severity: .warning, message: "缺少 locales.en 覆盖层（英文名为必填约定）。"))
    }

    return issues
  }

  nonisolated static func hasErrors(_ pack: KnowledgePack) -> Bool {
    validate(pack).contains { $0.severity == .error }
  }

  /// DFS for a cycle along audited upward edges (`isAuditedUpward`).
  nonisolated static func firstUpwardCycle(in pack: KnowledgePack) -> [String]? {
    let label: (UUID) -> String = { id in
      pack.elements.first { $0.id == id }.flatMap(\.key) ?? id.uuidString
    }
    var adjacency: [String: [String]] = [:]
    for relation in pack.relations {
      guard let raw = relation.kind, let kind = RelationKind(rawValue: raw), kind.isAuditedUpward
      else { continue }
      adjacency[label(relation.elementId), default: []].append(label(relation.relatedElementId))
    }

    var visiting = Set<String>()
    var visited = Set<String>()
    var stack: [String] = []

    func dfs(_ node: String) -> [String]? {
      if visiting.contains(node) {
        if let start = stack.firstIndex(of: node) {
          return Array(stack[start...]) + [node]
        }
        return [node, node]
      }
      if visited.contains(node) { return nil }
      visiting.insert(node)
      stack.append(node)
      for next in adjacency[node, default: []] {
        if let cycle = dfs(next) { return cycle }
      }
      stack.removeLast()
      visiting.remove(node)
      visited.insert(node)
      return nil
    }

    for key in adjacency.keys.sorted() {
      if let cycle = dfs(key) { return cycle }
    }
    return nil
  }
}
