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
    let elementKeys = Set(stamped.elements.map(\.key))
    let attractionKeys = Set(stamped.attractions.map(\.key))

    if stamped.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.init(severity: .error, message: "包版本号不能为空。"))
    }

    var seenElementKeys = Set<String>()
    for element in stamped.elements {
      if element.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "存在空的元素 key。"))
      } else if !seenElementKeys.insert(element.key).inserted {
        issues.append(.init(severity: .error, message: "重复的元素 key：\(element.key)"))
      }
      if element.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append(.init(severity: .error, message: "元素「\(element.key)」缺少名称。"))
      }
      if element.conceptKind == nil {
        issues.append(.init(severity: .warning, message: "元素「\(element.key)」缺少 conceptKind。"))
      } else if let raw = element.conceptKind, ConceptKind(rawValue: raw) == nil {
        issues.append(
          .init(severity: .error, message: "元素「\(element.key)」的 conceptKind 无效：\(raw)")
        )
      }
      if element.introduction.blocks.isEmpty {
        issues.append(.init(severity: .warning, message: "元素「\(element.key)」介绍为空。"))
      }
    }

    for attraction in stamped.attractions {
      if !elementKeys.contains(attraction.key) {
        issues.append(
          .init(
            severity: .error,
            message: "景点「\(attraction.key)」没有同 key 的元素节点。"
          )
        )
      }
      let role = stamped.elements.first { $0.key == attraction.key }
        .map { $0.resolvedContentRole(attractionKeys: attractionKeys) }
      if role == .history {
        issues.append(
          .init(
            severity: .error,
            message: "景点「\(attraction.key)」对应元素的 contentRole 应为看点。"
          )
        )
      }
    }

    for element in stamped.elements
    where element.resolvedContentRole(attractionKeys: attractionKeys) == .sight
      && !attractionKeys.contains(element.key)
    {
      issues.append(
        .init(
          severity: .warning,
          message: "看点「\(element.key)」未列入 attractions[]。"
        )
      )
    }

    var missingKind = 0
    for relation in stamped.relations {
      if !elementKeys.contains(relation.elementKey) {
        issues.append(
          .init(
            severity: .error,
            message: "关系起点「\(relation.elementKey)」不存在。"
          )
        )
      }
      if !elementKeys.contains(relation.relatedElementKey) {
        issues.append(
          .init(
            severity: .error,
            message: "关系终点「\(relation.relatedElementKey)」不存在。"
          )
        )
      }
      if let kind = relation.kind {
        if RelationKind(rawValue: kind) == nil {
          issues.append(
            .init(
              severity: .error,
              message: "关系 kind 无效：\(kind)（\(relation.elementKey) → \(relation.relatedElementKey)）"
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
            message: "关系缺少 explanation：\(relation.elementKey) → \(relation.relatedElementKey)"
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
      if !attractionKeys.contains(intro.attractionKey) {
        issues.append(
          .init(
            severity: .error,
            message: "介绍「\(intro.key)」的 attractionKey「\(intro.attractionKey)」不存在。"
          )
        )
      }
      if !elementKeys.contains(intro.culturalElementKey) {
        issues.append(
          .init(
            severity: .error,
            message: "介绍「\(intro.key)」的 culturalElementKey「\(intro.culturalElementKey)」不存在。"
          )
        )
      }
      if !(-90...90).contains(intro.latitude) || !(-180...180).contains(intro.longitude) {
        issues.append(
          .init(severity: .error, message: "介绍「\(intro.key)」坐标超出范围。")
        )
      }
    }

    for theme in stamped.themes {
      for key in theme.elementKeys where !elementKeys.contains(key) {
        issues.append(
          .init(
            severity: .error,
            message: "主题「\(theme.key)」引用了不存在的元素「\(key)」。"
          )
        )
      }
      if theme.minContacted < 1 {
        issues.append(
          .init(severity: .warning, message: "主题「\(theme.key)」的 minContacted 应 ≥ 1。")
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
    var adjacency: [String: [String]] = [:]
    for relation in pack.relations {
      guard let raw = relation.kind, let kind = RelationKind(rawValue: raw), kind.isAuditedUpward
      else { continue }
      adjacency[relation.elementKey, default: []].append(relation.relatedElementKey)
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
