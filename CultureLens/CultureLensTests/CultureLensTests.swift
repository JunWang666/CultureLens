//
//  CultureLensTests.swift
//  CultureLensTests
//
//  Created by 狗带菌 on 2026/7/27.
//

import Foundation
import ImageIO
import SwiftData
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

  @Test func focusSelectionMapsIPhoneLetterboxedCoordinatesToImage() {
    let imageFrame = FocusSelectionGeometry.aspectFitFrame(
      imageSize: CGSize(width: 1_200, height: 1_600),
      in: CGRect(x: 0, y: 0, width: 393, height: 852)
    )
    let region = FocusSelectionGeometry.region(
      from: CGPoint(
        x: imageFrame.minX + imageFrame.width * 0.10,
        y: imageFrame.minY + imageFrame.height * 0.15
      ),
      to: CGPoint(
        x: imageFrame.minX + imageFrame.width * 0.80,
        y: imageFrame.minY + imageFrame.height * 0.75
      ),
      in: imageFrame,
      enforceMinimumSize: true
    )

    #expect(abs(region.x - 0.10) < 0.000_001)
    #expect(abs(region.y - 0.15) < 0.000_001)
    #expect(abs(region.width - 0.70) < 0.000_001)
    #expect(abs(region.height - 0.60) < 0.000_001)
  }

  @Test func focusSelectionReachesIPadImageEdgesWithTopLetterbox() {
    let imageFrame = FocusSelectionGeometry.aspectFitFrame(
      imageSize: CGSize(width: 1_600, height: 1_200),
      in: CGRect(x: 0, y: 0, width: 1_032, height: 1_376)
    )
    let region = FocusSelectionGeometry.region(
      from: CGPoint(x: imageFrame.minX - 20, y: imageFrame.minY - 20),
      to: CGPoint(x: imageFrame.maxX + 20, y: imageFrame.maxY + 20),
      in: imageFrame,
      enforceMinimumSize: true
    )

    #expect(imageFrame.minY > 0)
    #expect(region == NormalizedImageRegion(x: 0, y: 0, width: 1, height: 1))
  }

  @Test func focusSelectionMinimumSizeUsesScreenPoints() {
    let imageFrame = CGRect(x: 100, y: 200, width: 800, height: 1_000)
    let region = FocusSelectionGeometry.region(
      from: CGPoint(x: 500, y: 700),
      to: CGPoint(x: 502, y: 703),
      in: imageFrame,
      enforceMinimumSize: true
    )

    #expect(abs(region.width * imageFrame.width - 16) < 0.000_001)
    #expect(abs(region.height * imageFrame.height - 16) < 0.000_001)
    #expect(region.x >= 0 && region.y >= 0)
    #expect(region.x + region.width <= 1)
    #expect(region.y + region.height <= 1)
  }

  @Test func llmGatewayEndpointIsConfiguredGlobally() {
    #expect(
      LLMGatewayConfig.default.endpoint.absoluteString
        == "https://gateway.ai.cloudflare.com/v1/b6fa8079d0ef1344774cb287040dc153/apps/compat/chat/completions"
    )
    #expect(LLMGatewayConfig.default.model == "dynamic/culturelens")
    #expect(LLMGatewayConfig.default.timeout == 55)
    #expect(LLMGatewayConfig.chat.model == "dynamic/chat")
    #expect(LLMGatewayConfig.chat.endpoint == LLMGatewayConfig.default.endpoint)
    #expect(LLMGatewayConfig.chat.timeout == 180)
  }

  @Test func explanationStreamingRequestUsesLowReasoningEffort() throws {
    let data = try LLMGatewayClient.streamingRequestBody(
      model: "dynamic/chat",
      messages: [
        ["role": "system", "content": "system"],
        ["role": "user", "content": "user"],
      ],
      reasoningEffort: .low
    )
    let body = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )

    #expect(body["model"] as? String == "dynamic/chat")
    #expect(body["stream"] as? Bool == true)
    #expect(body["reasoning_effort"] as? String == "low")
  }

  @Test func chatAnswerSplitsCitationSectionIntoCards() {
    let markdown = """
      三潭印月是西湖夜景的代表。

      ## 引用来源
      - key: `three-pools-mirroring-moon`, name: 三潭印月
        - 原文摘录：由湖中石塔、灯孔、水面与月色共同构成。
      - key: `three-pools-light-mechanism`, name: “印月”的光影原理
        - 原文摘录：常见解释包括灯光、倒影与错觉。
      """
    let parsed = CultureChatService.parseAnswer(markdown)
    #expect(parsed.body == "三潭印月是西湖夜景的代表。")
    #expect(parsed.citations.count == 2)
    #expect(parsed.citations[0].key == "three-pools-mirroring-moon")
    #expect(parsed.citations[0].name == "三潭印月")
    #expect(parsed.citations[0].fragment.contains("湖中石塔"))
    #expect(parsed.citations[1].key == "three-pools-light-mechanism")
    #expect(!parsed.body.contains("引用来源"))
  }

  @Test func personalizedExplanationKeepsTwoSectionsAndExtractsCitations() {
    let markdown = """
      ## 文化背景
      三潭印月把石塔、灯孔、水面与月色组织成一个夜间观看传统。

      ## 下一步建议
      - 观察灯孔与水面倒影如何重叠。

      ## 引用来源
      - key: `three-pools-mirroring-moon`, name: 三潭印月
        - 原文摘录：由湖中石塔、灯孔、水面与月色共同构成。
      """
    let parsed = CultureChatService.parseAnswer(markdown)

    #expect(parsed.body.contains("## 文化背景"))
    #expect(parsed.body.contains("## 下一步建议"))
    #expect(!parsed.body.contains("为什么是它"))
    #expect(!parsed.body.contains("引用来源"))
    #expect(parsed.citations.map(\.key) == ["three-pools-mirroring-moon"])
  }

  @Test func cultureCiteURLResolvesElementKey() throws {
    let withKey = try #require(
      URL(
        string:
          "https://culturelens.local/cite?citationMarker=9F742443&citationTitle=%E4%B8%89%E6%BD%AD%E5%8D%B0%E6%9C%88&citationA11yValue=%E4%B8%89%E6%BD%AD%E5%8D%B0%E6%9C%88&elementKey=three-pools-mirroring-moon"
      )
    )
    #expect(CultureCiteURL.elementKey(from: withKey, store: nil) == "three-pools-mirroring-moon")

    let fromA11y = try #require(
      URL(
        string:
          "https://culturelens.local/cite?citationMarker=9F742443&citationTitle=West%20Lake&citationA11yValue=West%20Lake(west-lake-ten-scenes)"
      )
    )
    #expect(CultureCiteURL.elementKey(from: fromA11y, store: nil) == "west-lake-ten-scenes")

    let unrelated = try #require(URL(string: "https://example.com/docs"))
    #expect(CultureCiteURL.elementKey(from: unrelated, store: nil) == nil)
  }

  @Test func cultureCiteSanitizerFixesBrokenInlineCitations() {
    let broken = """
      西湖十景不是标签，而是观看脚本。west-lake-ten-scenes
      南屏晚钟偏重听觉。`nanping-evening-bell`
      体系还会更新，如[west-lake-new-ten-scenes](https://culturelens.local/cite?citationMarker=west-lake-new-ten-scenes&citationTitle=1985 西湖新十景&citationA11yValue=1985 西湖新十景&elementKey=west-lake-new-ten-scenes)。
      """
    let cleaned = CultureCiteURL.sanitizeInlineCitations(broken, store: nil)
    #expect(!cleaned.contains("`nanping-evening-bell`"))
    #expect(!cleaned.contains("[west-lake-new-ten-scenes]("))
    #expect(!cleaned.contains("citationTitle=1985 西湖新十景"))
    #expect(!cleaned.contains("。west-lake-ten-scenes"))
    #expect(cleaned.contains("[9F742443](https://culturelens.local/cite?citationMarker=9F742443&"))
    #expect(cleaned.contains("elementKey=west-lake-new-ten-scenes"))
    #expect(cleaned.contains("elementKey=west-lake-ten-scenes"))
    #expect(cleaned.contains("elementKey=nanping-evening-bell"))
    #expect(cleaned.contains("citationTitle=1985%20%E8%A5%BF%E6%B9%96%E6%96%B0%E5%8D%81%E6%99%AF"))
    #expect(cleaned.contains("观看脚本。"))
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

  @Test func graphMembershipReusesLegacyStorageAndCanBeReverted() throws {
    let suiteName = "KnowledgeProgressStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let nodeID = UUID()
    userDefaults.set(
      [nodeID.uuidString],
      forKey: KnowledgeProgressStore.defaultStorageKey
    )
    let schema = Schema([KnowledgeProgressRecord.self])
    let configuration = ModelConfiguration(
      "KnowledgeProgressStoreTests",
      schema: schema,
      isStoredInMemoryOnly: true
    )
    let container = try ModelContainer(
      for: schema,
      configurations: [configuration]
    )
    let store = KnowledgeProgressStore(userDefaults: userDefaults)
    store.configure(modelContext: container.mainContext)

    #expect(store.isInGraph(nodeID))
    #expect(store.level(for: nodeID) == .understand)
    store.toggleGraphMembership(nodeID)
    #expect(!store.isInGraph(nodeID))

    let restoredStore = KnowledgeProgressStore(userDefaults: userDefaults)
    restoredStore.configure(modelContext: container.mainContext)
    #expect(!restoredStore.isInGraph(nodeID))

    restoredStore.toggleGraphMembership(nodeID)
    #expect(restoredStore.isInGraph(nodeID))

    let reloadedStore = KnowledgeProgressStore(userDefaults: userDefaults)
    reloadedStore.configure(modelContext: container.mainContext)
    #expect(reloadedStore.isInGraph(nodeID))
    #expect(reloadedStore.level(for: nodeID) == .contact)
  }

  @Test func graphMembershipMatchesSameAttractionByElementKey() throws {
    let suiteName = "KnowledgeProgressStoreElementKeyTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      userDefaults.removePersistentDomain(forName: suiteName)
    }
    let schema = Schema([KnowledgeProgressRecord.self])
    let configuration = ModelConfiguration(
      "KnowledgeProgressStoreElementKeyTests",
      schema: schema,
      isStoredInMemoryOnly: true
    )
    let container = try ModelContainer(
      for: schema,
      configurations: [configuration]
    )
    let store = KnowledgeProgressStore(userDefaults: userDefaults)
    store.configure(modelContext: container.mainContext)

    let joinedID = UUID()
    let rescannedID = UUID()
    store.setLevel(
      .contact,
      for: joinedID,
      source: .manual,
      elementKey: "three-pools-mirroring-moon"
    )

    #expect(store.isInGraph(rescannedID, elementKey: "three-pools-mirroring-moon"))
    #expect(
      store.level(for: rescannedID, elementKey: "three-pools-mirroring-moon") == .contact
    )
    #expect(!store.isInGraph(rescannedID, elementKey: "broken-bridge"))
  }

  @Test func userGraphKeepsJoinedNodesAndExpandsExactlyThreeHops() throws {
    let store = makeGraphStore(
      keys: (0...5).map { "e\($0)" },
      edges: (0..<5).map { ("e\($0)", "e\($0 + 1)") }
    )
    let rootID = DeterministicID.culturalElement("e0")
    let fourthHopID = DeterministicID.culturalElement("e4")
    let snapshot = store.userKnowledgeGraph(
      centerID: rootID,
      joinedSeeds: [
        UserKnowledgeGraphSeed(id: rootID, name: "节点 0", summary: ""),
        UserKnowledgeGraphSeed(id: fourthHopID, name: "节点 4", summary: ""),
      ]
    )

    let nodesByKey = Dictionary(
      uniqueKeysWithValues: snapshot.nodes.compactMap { node in
        node.elementKey.map { ($0, node) }
      }
    )
    #expect(Set(nodesByKey.keys) == Set((0...4).map { "e\($0)" }))
    #expect(nodesByKey["e0"]?.hop == 0)
    #expect(nodesByKey["e1"]?.hop == 1)
    #expect(nodesByKey["e2"]?.hop == 2)
    #expect(nodesByKey["e3"]?.hop == 3)
    #expect(nodesByKey["e4"]?.hop == 4)
    #expect(nodesByKey["e4"]?.isJoined == true)
    #expect(nodesByKey["e5"] == nil)
    #expect(snapshot.edges.count == 4)

    let recentered = store.userKnowledgeGraph(
      centerID: DeterministicID.culturalElement("e2"),
      joinedSeeds: [
        UserKnowledgeGraphSeed(id: rootID, name: "节点 0", summary: ""),
        UserKnowledgeGraphSeed(id: fourthHopID, name: "节点 4", summary: ""),
      ]
    )
    #expect(recentered.centerID == DeterministicID.culturalElement("e2"))
    #expect(recentered.nodes.first { $0.elementKey == "e2" }?.hop == 0)
    #expect(recentered.nodes.first { $0.elementKey == "e5" }?.hop == 3)
  }

  @Test func userGraphExpansionHonorsNodeBudget() {
    let store = makeGraphStore(
      keys: (0...8).map { "e\($0)" },
      edges: (1...8).map { ("e0", "e\($0)") }
    )
    let rootID = DeterministicID.culturalElement("e0")
    let snapshot = store.userKnowledgeGraph(
      centerID: rootID,
      joinedSeeds: [UserKnowledgeGraphSeed(id: rootID, name: "中心", summary: "")],
      maximumDepth: 3,
      maximumExpandedNodes: 4
    )

    #expect(snapshot.nodes.count == 4)
    #expect(snapshot.isExpansionTruncated)
    #expect(snapshot.nodes.first { $0.id == rootID }?.hop == 0)
  }

  @Test func userGraphLayoutPlacesShortestHopLayersOutward() throws {
    let store = makeGraphStore(
      keys: (0...4).map { "e\($0)" },
      edges: (0..<4).map { ("e\($0)", "e\($0 + 1)") }
    )
    let rootID = DeterministicID.culturalElement("e0")
    let fourthHopID = DeterministicID.culturalElement("e4")
    let snapshot = store.userKnowledgeGraph(
      centerID: rootID,
      joinedSeeds: [
        UserKnowledgeGraphSeed(id: rootID, name: "节点 0", summary: ""),
        UserKnowledgeGraphSeed(id: fourthHopID, name: "节点 4", summary: ""),
      ]
    )
    let layout = UserKnowledgeGraphLayout(snapshot: snapshot)
    let center = try #require(layout.positions[rootID])

    func radius(for key: String) throws -> CGFloat {
      let point = try #require(layout.positions[DeterministicID.culturalElement(key)])
      return hypot(point.x - center.x, point.y - center.y)
    }

    #expect(try radius(for: "e1") < radius(for: "e2"))
    #expect(try radius(for: "e2") < radius(for: "e3"))
    #expect(try radius(for: "e3") < radius(for: "e4"))
    #expect(center.x == layout.size.width / 2)
    #expect(center.y == layout.size.height / 2)
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

  @Test func graphZoomClampsAndStepsWithinSupportedRange() {
    #expect(GraphZoom.clamped(0.1) == 0.5)
    #expect(GraphZoom.clamped(1.4) == 1.4)
    #expect(GraphZoom.clamped(4) == 2.5)
    #expect(GraphZoom.decreased(from: 0.6) == 0.5)
    #expect(GraphZoom.increased(from: 2.4) == 2.5)
    #expect(GraphZoom.percentageText(for: 1.25) == "125%")
  }

  @Test func graphZoomFitsContentWithoutAutomaticallyUpscaling() {
    #expect(
      GraphZoom.fittedScale(
        contentSize: CGSize(width: 1_000, height: 800),
        viewportSize: CGSize(width: 500, height: 600)
      ) == 0.5
    )
    #expect(
      GraphZoom.fittedScale(
        contentSize: CGSize(width: 100, height: 80),
        viewportSize: CGSize(width: 500, height: 600)
      ) == 1
    )
    #expect(
      GraphZoom.fittedScale(
        contentSize: CGSize(width: 1_000, height: 800),
        viewportSize: CGSize(width: 100, height: 100),
        minimum: 0.05
      ) == 0.1
    )
  }

}

private func makeGraphStore(
  keys: [String],
  edges: [(String, String)]
) -> KnowledgeStore {
  let emptyIntroduction = RichTextDocument(schemaVersion: 1, blocks: [])
  return KnowledgeStore(
    pack: KnowledgePack(
      version: "graph-test",
      elements: keys.map {
        KnowledgePack.Element(
          key: $0,
          name: "节点 \($0)",
          introduction: emptyIntroduction
        )
      },
      attractions: [],
      relations: edges.map {
        KnowledgePack.Relation(elementKey: $0.0, relatedElementKey: $0.1)
      },
      introductions: []
    )
  )
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
