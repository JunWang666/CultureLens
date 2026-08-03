import Foundation
import Observation

@MainActor
@Observable
final class ScanSessionStore {
    private(set) var sessions: [ScanSession.ID: ScanSession] = [:]

    var sessionIDs: [ScanSession.ID] {
        sessions.keys.sorted { $0.uuidString < $1.uuidString }
    }

    func insert(_ session: ScanSession) {
        sessions[session.id] = session
    }

    func session(id: ScanSession.ID) -> ScanSession? {
        sessions[id]
    }

    func object(id: CultureObject.ID) -> CultureObject? {
        sessions.values.lazy
            .map(\.result.object)
            .first { $0.id == id }
    }

    func concept(id: CultureConcept.ID) -> CultureConcept? {
        sessions.values.lazy
            .flatMap(\.result.object.concepts)
            .first { $0.id == id }
    }

    func remove(id: ScanSession.ID) {
        sessions[id] = nil
    }
}
