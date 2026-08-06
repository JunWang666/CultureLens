import Foundation

nonisolated enum AppRoute: Hashable {
    case object(UUID)
    case concept(UUID)
    case knowledgeElement(String)
    case ask(UUID)
    /// General cultural Q&A from the home chat card (no specific object).
    case chat
    case scanResult(UUID)
    case scanCandidate(sessionID: UUID, candidateID: UUID)
    case history(UUID)
    /// Scan footprint map + timeline (pushed from「更多」on compact).
    case footprint
    case visitTrips
    case visitTrip(UUID)
    case themes
    case theme(String)
    case settings
    case packEditor
    case packEditorDraft(UUID)
}
