import Foundation

struct CultureLensAPI: Sendable {
    static let shared = CultureLensAPI()

    let baseURL: URL

    private init() {
        guard let baseURL = URL(string: "https://cl.codight.online") else {
            preconditionFailure("CultureLens API base URL must be valid.")
        }
        self.baseURL = baseURL
    }
}
