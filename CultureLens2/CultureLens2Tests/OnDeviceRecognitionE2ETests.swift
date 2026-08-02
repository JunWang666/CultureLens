import Foundation
import Testing

@testable import CultureLens2

/// End-to-end test against the real Cloudflare AI Gateway. Skipped unless the
/// environment variable `CULTURELENS_E2E_IMAGE` points at a local JPEG/PNG
/// fixture. Simulator test runners inherit variables via the `SIMCTL_CHILD_`
/// prefix, e.g.:
///   SIMCTL_CHILD_CULTURELENS_E2E_IMAGE=/path/to/photo.jpg \
///     xcodebuild ... test -only-testing:CultureLens2Tests/OnDeviceRecognitionE2ETests
struct OnDeviceRecognitionE2ETests {
  @MainActor @Test func endToEndRecognitionViaGateway() async throws {
    // Fixture resolution: env override first, then the shared test photo at
    // the repository root. Missing file => skip (returns green, no network).
    let repoRootFixture = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // CultureLens2Tests/
      .deletingLastPathComponent() // CultureLens2/
      .deletingLastPathComponent() // repository root
      .appending(path: "three_pools_mirroring_the_moon_geotagged 2.JPG")
      .path
    let path = ProcessInfo.processInfo.environment["CULTURELENS_E2E_IMAGE"]
      ?? repoRootFixture
    guard
      let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
      !imageData.isEmpty
    else {
      return
    }

    let service = try OnDeviceRecognitionService()
    // Coordinates near 三潭印月, West Lake — inside the bundled knowledge pack.
    let result = try await service.recognize(
      RecognitionInput(
        imageData: imageData,
        place: PlaceContext(latitude: 30.2386, longitude: 120.1419),
        contextNote: nil,
        localeIdentifier: "zh_CN"
      )
    )

    #expect(!result.object.canonicalName.isEmpty)
    #expect(
      ["resolved", "attraction", "unresolved"].contains(result.resolutionStatus ?? "")
    )
    #expect(!result.modelIdentifier.isEmpty)
    print("E2E result: \(result.object.canonicalName) status=\(result.resolutionStatus ?? "?") model=\(result.modelIdentifier)")
  }
}
