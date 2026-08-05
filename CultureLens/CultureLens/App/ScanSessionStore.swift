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
        for session in sessions.values {
            if session.result.object.id == id {
                return session.result.object
            }
            // 候选详情页的对象来自 alternatives（景点候选与视觉备选）。
            if let candidate = session.result.alternatives.first(where: { $0.id == id }) {
                return candidate.cultureObject
            }
        }
        return nil
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
