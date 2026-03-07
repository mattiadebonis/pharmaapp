import Foundation
import AuthenticationServices

enum AuthGatewayError: Error, LocalizedError, Equatable {
    case cancelled
    case message(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return nil
        case let .message(message):
            return message
        }
    }
}

@MainActor
protocol AuthGateway {
    var currentUser: AuthUser? { get }

    func observeAuthState() -> AsyncStream<AuthUser?>
    func signInWithGoogle(idToken: String, accessToken: String) async throws
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws
    func signOut() throws
    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws

    func isConfigured() -> Bool
    func googleClientID() -> String?
}
