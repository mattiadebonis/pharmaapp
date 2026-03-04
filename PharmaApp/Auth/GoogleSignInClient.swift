import Foundation
import UIKit
import GoogleSignIn

struct GoogleSignInPayload: Equatable {
    let idToken: String
    let accessToken: String
    let email: String?
    let fullName: String?
    let imageURL: URL?
}

enum GoogleSignInClientError: LocalizedError, Equatable {
    case invalidConfiguration
    case missingIDToken
    case missingAccessToken
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Configurazione Google non valida."
        case .missingIDToken:
            return "Google non ha restituito un ID token valido."
        case .missingAccessToken:
            return "Google non ha restituito un access token valido."
        case .cancelled:
            return nil
        }
    }
}

protocol GoogleSignInClientProtocol {
    func signIn(presentingViewController: UIViewController, clientID: String) async throws -> GoogleSignInPayload
    func handle(url: URL) -> Bool
    func signOut()
}

final class GoogleSignInClient: GoogleSignInClientProtocol {
    func signIn(presentingViewController: UIViewController, clientID: String) async throws -> GoogleSignInPayload {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw GoogleSignInClientError.invalidConfiguration
        }

        let configuration = GIDConfiguration(clientID: trimmedClientID)
        GIDSignIn.sharedInstance.configuration = configuration

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error = error as NSError? {
                    if error.domain == kGIDSignInErrorDomain,
                       error.code == GIDSignInError.canceled.rawValue {
                        continuation.resume(throwing: GoogleSignInClientError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let result else {
                    continuation.resume(throwing: GoogleSignInClientError.cancelled)
                    return
                }

                guard let idToken = result.user.idToken?.tokenString else {
                    continuation.resume(throwing: GoogleSignInClientError.missingIDToken)
                    return
                }

                let accessToken = result.user.accessToken.tokenString
                guard !accessToken.isEmpty else {
                    continuation.resume(throwing: GoogleSignInClientError.missingAccessToken)
                    return
                }

                continuation.resume(returning: GoogleSignInPayload(
                    idToken: idToken,
                    accessToken: accessToken,
                    email: result.user.profile?.email,
                    fullName: result.user.profile?.name,
                    imageURL: result.user.profile?.imageURL(withDimension: 128)
                ))
            }
        }
    }

    func handle(url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}
