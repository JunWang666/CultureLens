import Foundation
import Testing

@testable import CultureLens

struct LLMIDSessionTests {

  @Test func registersElementsAndAttractionsIndependentlyFromOne() {
    var session = LLMIDSession()
    let e1 = DeterministicID.culturalElement("e1")
    let e2 = DeterministicID.culturalElement("e2")
    let a1 = DeterministicID.attraction("a1")
    let a2 = DeterministicID.attraction("a2")

    #expect(session.registerElements([e1, e2]) == ["1", "2"])
    #expect(session.registerAttractions([a1, a2]) == ["1", "2"])

    #expect(session.shortID(forElement: e1) == "1")
    #expect(session.shortID(forAttraction: a1) == "1")
    #expect(session.resolveElement("1") == e1)
    #expect(session.resolveAttraction("1") == a1)
    #expect(session.resolveElement("2") == e2)
    #expect(session.resolveAttraction("2") == a2)
  }

  @Test func reusesExistingShortIDsForDuplicates() {
    var session = LLMIDSession()
    let e1 = DeterministicID.culturalElement("e1")
    #expect(session.registerElements([e1, e1]) == ["1", "1"])
    #expect(session.elementShortToUUID.count == 1)
  }

  @Test func emptyOrWhitespaceResolvesToNil() {
    var session = LLMIDSession()
    let e1 = DeterministicID.culturalElement("e1")
    _ = session.registerElements([e1])
    #expect(session.resolveElement("") == nil)
    #expect(session.resolveElement("   ") == nil)
    #expect(session.resolveAttraction("") == nil)
  }

  @Test func acceptsRegisteredRawUUIDStrings() {
    var session = LLMIDSession()
    let e1 = DeterministicID.culturalElement("e1")
    _ = session.registerElements([e1])
    #expect(session.resolveElement(e1.uuidString) == e1)
    #expect(session.resolveElement(UUID().uuidString) == nil)
  }

  @Test func remapsElementShortIDsInMarkdownWithoutPartialMatches() {
    var session = LLMIDSession()
    // Register 10 elements so short ids include both "1" and "10", and so a
    // rewritten UUID may itself start with a digit that equals another short id.
    let ids = (1...10).map { DeterministicID.culturalElement("pad-\($0)") }
    _ = session.registerElements(ids)
    let id1 = ids[0]
    let id10 = ids[9]
    #expect(session.shortID(forElement: id1) == "1")
    #expect(session.shortID(forElement: id10) == "10")

    let markdown =
      "cite elementKey=10 and elementKey=1; list key: `10`, name: x; key: 1, name: y"
    let remapped = session.remapElementShortIDs(in: markdown)
    #expect(remapped.contains("elementKey=\(id10.uuidString)"))
    #expect(remapped.contains("elementKey=\(id1.uuidString)"))
    #expect(remapped.contains("key: `\(id10.uuidString)`"))
    #expect(remapped.contains("key: \(id1.uuidString),"))
    #expect(!remapped.contains("elementKey=10"))
    #expect(!remapped.contains("elementKey=1;"))
    // Must not concatenate into a UUID that starts with a short-id digit.
    #expect(!remapped.contains(id10.uuidString + id1.uuidString.prefix(8)))
  }
}
