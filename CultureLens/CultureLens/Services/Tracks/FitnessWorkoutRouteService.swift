import CoreLocation
import Foundation
import HealthKit

nonisolated struct FitnessWorkoutSummary: Identifiable, Equatable, Sendable {
  let id: UUID
  let activityTitle: String
  let startedAt: Date
  let duration: TimeInterval
  let sourceName: String

  var importedTrackName: String {
    "\(activityTitle) · \(startedAt.formatted(date: .abbreviated, time: .shortened))"
  }
}

nonisolated enum FitnessWorkoutRouteError: LocalizedError, Equatable {
  case healthDataUnavailable
  case workoutNoLongerAvailable
  case routeUnavailable

  var errorDescription: String? {
    switch self {
    case .healthDataUnavailable:
      String(localized: "这台设备不支持读取 Fitness 与健康数据。")
    case .workoutNoLongerAvailable:
      String(localized: "这条运动记录已不可用，请刷新后重试。")
    case .routeUnavailable:
      String(localized: "这条运动记录没有可读取的 GPS 路线。")
    }
  }
}

/// Read-only HealthKit adapter. HealthKit objects remain actor-confined and
/// only Sendable summaries / normalized route drafts leave this boundary.
actor FitnessWorkoutRouteService {
  static let shared = FitnessWorkoutRouteService()

  private let healthStore: HKHealthStore
  private var workoutsByID: [UUID: HKWorkout] = [:]

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func loadRoutableWorkouts(limit: Int = 100) async throws -> [FitnessWorkoutSummary] {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw FitnessWorkoutRouteError.healthDataUnavailable
    }

    try await healthStore.requestAuthorization(
      toShare: [],
      read: [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    )

    let query = HKSampleQueryDescriptor<HKWorkout>(
      predicates: [.workout()],
      sortDescriptors: [SortDescriptor(\HKWorkout.startDate, order: .reverse)],
      limit: limit
    )
    let workouts = try await query.result(for: healthStore)

    var summaries: [FitnessWorkoutSummary] = []
    var refreshedWorkouts: [UUID: HKWorkout] = [:]

    for workout in workouts {
      try Task.checkCancellation()
      let routes = try await routeSamples(for: workout)
      guard !routes.isEmpty else { continue }

      refreshedWorkouts[workout.uuid] = workout
      summaries.append(
        FitnessWorkoutSummary(
          id: workout.uuid,
          activityTitle: Self.activityTitle(for: workout.workoutActivityType),
          startedAt: workout.startDate,
          duration: workout.duration,
          sourceName: workout.sourceRevision.source.name
        )
      )
    }

    workoutsByID = refreshedWorkouts
    return summaries
  }

  func routeDraft(for summary: FitnessWorkoutSummary) async throws -> FitnessWorkoutRouteDraft {
    guard let workout = workoutsByID[summary.id] else {
      throw FitnessWorkoutRouteError.workoutNoLongerAvailable
    }

    let routes = try await routeSamples(for: workout)
    guard !routes.isEmpty else {
      throw FitnessWorkoutRouteError.routeUnavailable
    }

    var totalPointCount = 0
    var segments: [ImportedTrackSegment] = []

    for route in routes.sorted(by: { $0.startDate < $1.startDate }) {
      try Task.checkCancellation()
      var points: [ImportedTrackPoint] = []
      let locationResults = HKWorkoutRouteQueryDescriptor(route).results(for: healthStore)

      for try await location in locationResults {
        try Task.checkCancellation()
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { continue }

        totalPointCount += 1
        guard totalPointCount <= 200_000 else {
          throw ImportedTrackError.tooManyPoints
        }
        points.append(
          ImportedTrackPoint(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            elevationMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            recordedAt: location.timestamp
          )
        )
      }

      if points.count >= 2 {
        segments.append(ImportedTrackSegment(points: points))
      }
    }

    guard !segments.isEmpty else {
      throw FitnessWorkoutRouteError.routeUnavailable
    }

    return FitnessWorkoutRouteDraft(
      sourceIdentifier: summary.id.uuidString.lowercased(),
      name: summary.importedTrackName,
      sourceName: summary.sourceName,
      startedAt: summary.startedAt,
      segments: segments
    )
  }

  private func routeSamples(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
    let predicate = HKQuery.predicateForObjects(from: workout)
    let query = HKAnchoredObjectQueryDescriptor<HKWorkoutRoute>(
      predicates: [.workoutRoute(predicate)],
      anchor: nil,
      limit: HKObjectQueryNoLimit
    )
    return try await query.result(for: healthStore).addedSamples
  }

  private static func activityTitle(for type: HKWorkoutActivityType) -> String {
    switch type {
    case .walking:
      String(localized: "户外步行")
    case .running:
      String(localized: "户外跑步")
    case .cycling:
      String(localized: "户外骑行")
    case .hiking:
      String(localized: "徒步")
    case .swimming:
      String(localized: "游泳")
    case .rowing:
      String(localized: "划船")
    case .paddleSports:
      String(localized: "桨板")
    case .crossCountrySkiing:
      String(localized: "越野滑雪")
    case .downhillSkiing:
      String(localized: "高山滑雪")
    case .snowboarding:
      String(localized: "单板滑雪")
    case .skatingSports:
      String(localized: "滑冰")
    case .wheelchairWalkPace:
      String(localized: "轮椅步行配速")
    case .wheelchairRunPace:
      String(localized: "轮椅跑步配速")
    default:
      String(localized: "户外运动")
    }
  }
}
