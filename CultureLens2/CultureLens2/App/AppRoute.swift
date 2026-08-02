import Foundation

enum AppRoute: Hashable {
    case object(UUID)
    case concept(UUID)
    case ask(UUID)
    case scanResult(UUID)
    case scanCandidate(sessionID: UUID, candidateID: UUID)
    case history(UUID)
}
