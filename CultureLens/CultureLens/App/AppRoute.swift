import Foundation

nonisolated enum AppRoute: Hashable {
    case object(UUID)
    case concept(UUID)
    case knowledgeElement(UUID)
    case ask(UUID)
    /// General cultural Q&A from the home chat card (no specific object).
    case chat
    case scanResult(UUID)
    case scanCandidate(sessionID: UUID, candidateID: UUID)
    case history(UUID)
    /// Scan footprint map (pushed from「更多」on compact).
    case footprint
    /// Review hub: timeline + visit trips (pushed from「更多」on compact).
    case visitTrips
    case visitTrip(UUID)
    case themes
    case theme(String)
    case settings
}
