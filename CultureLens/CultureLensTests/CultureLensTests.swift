//
//  CultureLensTests.swift
//  CultureLensTests
//
//  Created by 狗带菌 on 2026/7/27.
//

import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import CultureLens

@MainActor
struct CultureLensTests {

  @Test func sampleDataHasResolvableRoutes() {
    for object in SampleCultureData.objects {
      #expect(SampleCultureData.object(id: object.id) == object)

      for concept in object.concepts {
        #expect(SampleCultureData.concept(id: concept.id) == concept)
      }
    }
  }

  @Test func sampleObjectsContainTrustSignals() {
    for object in SampleCultureData.objects {
      #expect((0...1).contains(object.confidence))
      #expect(!object.sources.isEmpty)
      #expect(!object.summary.isEmpty)
    }
  }

  @Test func cultureObjectPreservesCulturalElementKey() throws {
    var object = SampleCultureData.featured
    object.culturalElementKey = "timber-bracket"

    let encoded = try JSONEncoder().encode(object)
    let decoded = try JSONDecoder().decode(CultureObject.self, from: encoded)

    #expect(decoded.culturalElementKey == "timber-bracket")
  }

  @Test func attractionCandidatesExcludeTheCurrentPrimaryAttraction() {
    let primary = CultureObject(
      id: UUID(),
      canonicalName: "三潭印月",
      summary: "主结果",
      category: .space,
      confidence: 0.9,
      artworkSymbol: "square.3.layers.3d",
      concepts: [],
      relations: [],
      sources: []
    )
    let duplicate = RecognitionCandidate(
      id: UUID(),
      attractionKey: "three-pools-mirroring-moon",
      canonicalName: " 三潭印月 ",
      category: .space,
      confidence: 0,
      rationale: "附近候选",
      resolutionStatus: "attraction"
    )
    let other = RecognitionCandidate(
      id: UUID(),
      attractionKey: "leifeng-pagoda",
      canonicalName: "雷峰塔",
      category: .space,
      confidence: 0,
      rationale: "附近候选",
      summary: "雷峰塔介绍",
      resolutionStatus: "attraction"
    )
    let result = RecognitionResult(
      id: UUID(),
      object: primary,
      alternatives: [duplicate, other],
      rationale: "画面判断",
      modelIdentifier: "test",
      usedPlaceContext: true,
      resolutionStatus: "attraction"
    )

    #expect(result.displayAttractionCandidates == [other])
    #expect(other.cultureObject.summary == "雷峰塔介绍")

    var generic = other
    generic.summary = generic.rationale
    #expect(generic.informativeSummary == nil)
    #expect(generic.cultureObject.summary == "暂无可展示的景点介绍。")
  }

  @Test func conceptDetailOnlyReturnsIndependentText() {
    let duplicate = CultureConcept(
      id: UUID(),
      name: "观看方式",
      kind: .foundation,
      summary: "同一段文字。",
      detail: "  同一段\n文字。  "
    )
    let distinct = CultureConcept(
      id: UUID(),
      name: "观看方式",
      kind: .foundation,
      summary: "摘要",
      detail: "更完整的解释。"
    )

    #expect(duplicate.distinctDetail == nil)
    #expect(distinct.distinctDetail == "更完整的解释。")
  }

  @Test func sampleKnowledgeGraphRelationsResolveToNodes() {
    for object in SampleCultureData.objects {
      let nodeIDs = Set([object.id] + object.concepts.map(\.id))

      #expect(!object.relations.isEmpty)
      for relation in object.relations {
        #expect(nodeIDs.contains(relation.sourceID))
        #expect(nodeIDs.contains(relation.targetID))
        #expect(!relation.explanation.isEmpty)
      }
    }
  }

  @Test func dougongGraphContainsPrerequisitesAndRitualPath() throws {
    let object = SampleCultureData.dougong
    let buildingRank = try #require(
      object.concepts.first { $0.name == "建筑等级" }
    )
    let ritualOrder = try #require(
      object.concepts.first { $0.name == "礼制秩序" }
    )
    let prerequisites = object.relations.filter {
      $0.kind == .prerequisiteFor && $0.targetID == object.id
    }

    #expect(prerequisites.count == 3)
    #expect(
      object.relations.contains {
        $0.sourceID == object.id
          && $0.targetID == buildingRank.id
          && $0.kind == .expresses
      }
    )
    #expect(
      object.relations.contains {
        $0.sourceID == buildingRank.id
          && $0.targetID == ritualOrder.id
          && $0.kind == .explains
      }
    )
  }

  @Test func photoLocationPreservesRecordedPrecisionAndCoordinateReferences() throws {
    let imageData = try jpegWithGPS(
      latitude: 33.856784,
      latitudeReference: "S",
      longitude: 151.215297,
      longitudeReference: "E",
      horizontalAccuracy: 4.25
    )
    let place = try #require(
      PhotoLocationProvider.embeddedPlaceContext(in: imageData)
    )

    #expect(abs(place.latitude + 33.856784) < 0.000_001)
    #expect(abs(place.longitude - 151.215297) < 0.000_001)
    #expect(place.accuracyMeters == 4.25)
  }

  @Test func photoWithoutRecordedLocationDoesNotCreatePlaceContext() {
    #expect(
      PhotoLocationProvider.embeddedPlaceContext(
        in: SampleScanImage.jpegData()
      ) == nil
    )
  }

  @Test func imagePreprocessorProducesBoundedMetadataFreeJPEG() throws {
    let sourceData = SampleScanImage.jpegData()
    let result = try ImagePreprocessor.normalizedJPEG(from: sourceData)
    let source = try #require(
      CGImageSourceCreateWithData(result as CFData, nil)
    )
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    )

    #expect(CGImageSourceGetType(source) == "public.jpeg" as CFString)
    #expect((properties[kCGImagePropertyPixelWidth] as? Int) ?? 0 <= 1_600)
    #expect((properties[kCGImagePropertyPixelHeight] as? Int) ?? 0 <= 1_600)
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
  }

  @Test func sampleRecognitionUsesSharedResultContract() async throws {
    let input = RecognitionInput(
      imageData: SampleScanImage.jpegData(),
      place: PlaceContext(
        latitude: 31.23,
        longitude: 121.47,
        accuracyMeters: 1_000,
        cityName: "上海市",
        regionName: "中国大陆",
        regionCode: "CN",
        displayName: "上海市，中国大陆"
      ),
      contextNote: "古建筑屋檐",
      localeIdentifier: "zh_CN"
    )

    let result = try await RecognitionService.sample.recognize(input)
    let encoded = try JSONEncoder().encode(result)
    let decoded = try JSONDecoder().decode(RecognitionResult.self, from: encoded)

    #expect(decoded.object.canonicalName == "斗拱")
    #expect(decoded.usedPlaceContext)
    #expect(decoded.locationInfluence?.effect == LocationInfluence.Effect.none)
    #expect(decoded.resolutionStatus == "resolved")
    #expect(decoded.catalogCandidateCount == 3)
    #expect(decoded.alternatives.first?.resolutionStatus == "resolved")
    let alternativeSources = try #require(decoded.alternatives.first?.sources)
    #expect(!alternativeSources.isEmpty)
    #expect(!decoded.object.concepts.isEmpty)
    #expect(decoded == result)
  }

  @Test func imagePreprocessorDrawsFocusFrameWithoutCropping() throws {
    let normalized = try ImagePreprocessor.normalizedJPEG(
      from: SampleScanImage.jpegData()
    )
    let originalSize = try ImagePreprocessor.pixelSize(of: normalized)
    let annotated = try ImagePreprocessor.annotatedJPEG(
      from: normalized,
      region: NormalizedImageRegion(
        x: 0.25,
        y: 0.20,
        width: 0.50,
        height: 0.40
      )
    )
    let annotatedSize = try ImagePreprocessor.pixelSize(of: annotated)
    let source = try #require(
      CGImageSourceCreateWithData(annotated as CFData, nil)
    )
    let properties = try #require(
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any]
    )

    #expect(annotatedSize == originalSize)
    #expect(annotated != normalized)
    #expect(CGImageSourceGetType(source) == "public.jpeg" as CFString)
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
  }

  @Test func ownedDataCopyIsIndependentFromMutableFoundationStorage() throws {
    let mutable = NSMutableData(data: Data([1, 2, 3, 4]))
    let bridged = mutable as Data
    let owned = bridged.ownedCopy()

    mutable.resetBytes(in: NSRange(location: 0, length: mutable.length))

    #expect(owned == Data([1, 2, 3, 4]))
  }

  @Test func normalizedAndAnnotatedImagesSupportConcurrentBase64Encoding() async throws {
    let normalized = try ImagePreprocessor.normalizedJPEG(
      from: SampleScanImage.jpegData()
    )
    let annotated = try ImagePreprocessor.annotatedJPEG(
      from: normalized,
      region: .defaultFocus
    )
    let inputs = [normalized, annotated]

    let encodedLengths = await withTaskGroup(of: Int.self) { group in
      for _ in 0..<16 {
        for input in inputs {
          group.addTask {
            input.base64EncodedString().utf8.count
          }
        }
      }

      var lengths: [Int] = []
      for await length in group {
        lengths.append(length)
      }
      return lengths
    }

    #expect(encodedLengths.count == 32)
    #expect(encodedLengths.allSatisfy { $0 > 0 })
    #expect(Set(encodedLengths).count == 2)
  }

  @Test func recognitionInputPreencodesSingleImageBeforeServiceBoundary() throws {
    let normalized = try ImagePreprocessor.normalizedJPEG(
      from: SampleScanImage.jpegData()
    )
    let annotated = try ImagePreprocessor.annotatedJPEG(
      from: normalized,
      region: .defaultFocus
    )
    let input = RecognitionInput(
      imageData: annotated,
      place: nil,
      contextNote: nil,
      localeIdentifier: "zh_CN"
    )

    #expect(Data(base64Encoded: input.imageBase64) == annotated)
  }

  @Test func normalizedFocusRegionStaysInsideImageBounds() {
    let region = NormalizedImageRegion(
      x: -0.4,
      y: 0.9,
      width: 1.3,
      height: 0.3
    ).clamped(minimumSize: 0.18)

    #expect(region.x == 0)
    #expect(region.y == 0.7)
    #expect(region.width == 1)
    #expect(region.height == 0.3)
  }

  @Test func productionAPIBaseURLIsConfiguredGlobally() {
    #expect(
      CultureLensAPI.shared.baseURL.absoluteString
        == "https://cl.codight.online"
    )
  }

  @Test func nearbyRecommendationsDecodeDatabaseContent() throws {
    let payload = Data(
      #"""
      {
        "requestedLocation": {
          "latitude": 30.248963,
          "longitude": 120.148691,
          "radiusMeters": 50000
        },
        "totalMatches": 10,
        "introductions": [
          {
            "key": "wenlan-pavilion.imperial-library",
            "name": "文澜阁的藏书楼身份",
            "introduction": {
              "schemaVersion": 1,
              "blocks": [
                { "type": "paragraph", "text": "国家编纂工程落实为具体的阅读空间。" }
              ]
            },
            "culturalElement": {
              "key": "siku-quanshu-library",
              "name": "《四库全书》与皇家藏书楼"
            },
            "attraction": {
              "key": "wenlan-pavilion",
              "name": "文澜阁"
            },
            "location": {
              "latitude": 30.253303,
              "longitude": 120.137856
            },
            "distanceMeters": 1147.2
          }
        ]
      }
      """#.utf8
    )

    let response = try JSONDecoder().decode(
      NearbyRecommendationsResponse.self,
      from: payload
    )
    let recommendation = try #require(response.introductions.first)

    #expect(response.totalMatches == 10)
    #expect(recommendation.id == "wenlan-pavilion.imperial-library")
    #expect(recommendation.attraction.name == "文澜阁")
    #expect(recommendation.culturalElement.key == "siku-quanshu-library")
    #expect(recommendation.introduction.plainText == "国家编纂工程落实为具体的阅读空间。")
    #expect(recommendation.distanceMeters == 1_147.2)
  }

  @Test func knowledgeUnderstandingPersistsAndCanBeReverted() throws {
    let suiteName = "KnowledgeProgressStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let nodeID = UUID()
    let store = KnowledgeProgressStore(userDefaults: userDefaults)

    #expect(!store.isUnderstood(nodeID))

    store.toggleUnderstanding(nodeID)
    #expect(store.isUnderstood(nodeID))

    let restoredStore = KnowledgeProgressStore(userDefaults: userDefaults)
    #expect(restoredStore.isUnderstood(nodeID))

    restoredStore.toggleUnderstanding(nodeID)
    #expect(!restoredStore.isUnderstood(nodeID))
  }

  @Test func graphLayoutUsesUndirectedShortestHopRings() throws {
    let rootID = UUID()
    let incomingID = UUID()
    let outgoingID = UUID()
    let shortcutID = UUID()
    let secondHopID = UUID()
    let isolatedID = UUID()
    let concepts = [
      CultureConcept(id: incomingID, name: "入边一跳", kind: .foundation, summary: "", detail: ""),
      CultureConcept(id: outgoingID, name: "出边一跳", kind: .history, summary: "", detail: ""),
      CultureConcept(id: shortcutID, name: "存在直达捷径", kind: .aesthetics, summary: "", detail: ""),
      CultureConcept(id: secondHopID, name: "严格二跳", kind: .institution, summary: "", detail: ""),
      CultureConcept(id: isolatedID, name: "孤立节点", kind: .similar, summary: "", detail: ""),
    ]
    let relations = [
      CultureRelation(
        id: UUID(), sourceID: incomingID, targetID: rootID, kind: .explains, explanation: ""),
      CultureRelation(
        id: UUID(), sourceID: rootID, targetID: outgoingID, kind: .explains, explanation: ""),
      CultureRelation(
        id: UUID(), sourceID: incomingID, targetID: shortcutID, kind: .explains, explanation: ""),
      CultureRelation(
        id: UUID(), sourceID: rootID, targetID: shortcutID, kind: .explains, explanation: ""),
      CultureRelation(
        id: UUID(), sourceID: outgoingID, targetID: secondHopID, kind: .explains, explanation: ""),
    ]
    let object = CultureObject(
      id: rootID,
      canonicalName: "中心对象",
      summary: "",
      category: .space,
      confidence: 1,
      artworkSymbol: "circle",
      concepts: concepts,
      relations: relations,
      sources: []
    )

    let layout = GraphLayout(object: object)
    #expect(layout.hops[rootID] == 0)
    #expect(layout.hops[incomingID] == 1)
    #expect(layout.hops[outgoingID] == 1)
    #expect(layout.hops[shortcutID] == 1)
    #expect(layout.hops[secondHopID] == 2)
    #expect(layout.hops[isolatedID] == 3)

    let center = try #require(layout.positions[rootID])
    let firstRing = try #require(layout.positions[incomingID])
    let secondRing = try #require(layout.positions[secondHopID])
    let outerRing = try #require(layout.positions[isolatedID])
    func distance(_ point: CGPoint) -> CGFloat {
      hypot(point.x - center.x, point.y - center.y)
    }
    #expect(distance(firstRing) < distance(secondRing))
    #expect(distance(secondRing) < distance(outerRing))
    #expect(center.x == layout.size.width / 2)
    #expect(center.y == layout.size.height / 2)
  }

}

private func jpegWithGPS(
  latitude: Double,
  latitudeReference: String,
  longitude: Double,
  longitudeReference: String,
  horizontalAccuracy: Double
) throws -> Data {
  let source = try #require(
    CGImageSourceCreateWithData(SampleScanImage.jpegData() as CFData, nil)
  )
  let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  let output = NSMutableData()
  let destination = try #require(
    CGImageDestinationCreateWithData(
      output,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    )
  )
  let gps: [CFString: Any] = [
    kCGImagePropertyGPSLatitude: latitude,
    kCGImagePropertyGPSLatitudeRef: latitudeReference,
    kCGImagePropertyGPSLongitude: longitude,
    kCGImagePropertyGPSLongitudeRef: longitudeReference,
    kCGImagePropertyGPSHPositioningError: horizontalAccuracy,
  ]
  CGImageDestinationAddImage(
    destination,
    image,
    [kCGImagePropertyGPSDictionary: gps] as CFDictionary
  )
  guard CGImageDestinationFinalize(destination) else {
    throw ImagePreprocessorError.encodingFailed
  }
  return Data(bytes: output.bytes, count: output.length)
}
