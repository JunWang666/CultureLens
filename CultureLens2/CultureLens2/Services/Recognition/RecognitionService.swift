import Foundation
import SwiftUI

enum RecognitionServiceError: LocalizedError {
  case invalidConfiguration
  case localResourcesMissing
  case invalidResponse
  case server(statusCode: Int, message: String?)
  case transport(String)

  var errorDescription: String? {
    switch self {
    case .invalidConfiguration:
      "识别服务尚未配置。"
    case .localResourcesMissing:
      "应用内缺少知识库或提示词资源，无法进行识别。"
    case .invalidResponse:
      "识别服务返回了无法读取的数据。"
    case .server(let statusCode, let message):
      message ?? "识别服务暂时不可用（\(statusCode)）。"
    case .transport(let message):
      "无法连接识别服务：\(message)"
    }
  }
}

struct RecognitionService: Sendable {
  enum Mode: String, Sendable {
    case demo
    case remote
  }

  private enum Backend: Sendable {
    case sample
    case onDevice(OnDeviceRecognitionService)
    case unavailable
  }

  let mode: Mode
  private let backend: Backend

  func recognize(_ input: RecognitionInput) async throws -> RecognitionResult {
    switch backend {
    case .sample:
      try await Self.recognizeSample(input)
    case .onDevice(let service):
      try await service.recognize(input)
    case .unavailable:
      throw RecognitionServiceError.localResourcesMissing
    }
  }

  static let sample = RecognitionService(mode: .demo, backend: .sample)

  static func configured() -> RecognitionService {
    do {
      return RecognitionService(
        mode: .remote,
        backend: .onDevice(try OnDeviceRecognitionService())
      )
    } catch {
      return RecognitionService(mode: .remote, backend: .unavailable)
    }
  }

  private static func recognizeSample(
    _ input: RecognitionInput
  ) async throws -> RecognitionResult {
    try await Task.sleep(for: .milliseconds(900))

    let object = SampleCultureData.featured
    let alternative = SampleCultureData.lotusPattern
    return RecognitionResult(
      id: UUID(),
      object: object,
      alternatives: [
        RecognitionCandidate(
          id: alternative.id,
          canonicalName: alternative.canonicalName,
          category: alternative.category,
          confidence: 0.24,
          rationale: "这是已审核知识库中的对照候选，但框选处缺少放射状花瓣与连续纹样。",
          summary: alternative.summary,
          timePeriod: alternative.timePeriod,
          region: alternative.region,
          artworkSymbol: alternative.artworkSymbol,
          sources: alternative.sources,
          resolutionStatus: "resolved"
        )
      ],
      rationale: input.place == nil
        ? "样例根据木构件的层叠、出跳和柱梁连接特征给出结果。"
        : "样例结合木构件视觉特征与附近地点上下文给出结果；位置仅作为辅助。",
      uncertainty: "这是演示识别，不代表视觉模型已经分析了这张照片。",
      modelIdentifier: "culturelens-sample-v1",
      usedPlaceContext: input.place != nil,
      locationInfluence: input.place == nil
        ? nil
        : LocationInfluence(
          effect: .none,
          summary: "位置没有缩小当前 3 条内置知识库候选，样例仍按视觉特征给出结果。"
        ),
      resolutionStatus: "resolved",
      catalogVersion: "app-sample-v1",
      catalogCandidateCount: SampleCultureData.objects.count
    )
  }
}

private struct RecognitionServiceKey: EnvironmentKey {
  static let defaultValue = RecognitionService.sample
}

extension EnvironmentValues {
  var recognitionService: RecognitionService {
    get { self[RecognitionServiceKey.self] }
    set { self[RecognitionServiceKey.self] = newValue }
  }
}
