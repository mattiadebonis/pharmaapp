import Foundation
import AuthenticationServices
import FirebaseCore
import FirebaseAuth

enum FirebaseRuntimeConfigurator {
    static func configureIfNeeded(
        appProvider: () -> FirebaseApp? = { FirebaseApp.app() },
        bundle: Bundle = .main
    ) {
        guard appProvider() == nil else { return }
        guard bundle.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }
}

@MainActor
final class FirebaseAuthGatewayAdapter: AuthGateway {
    private let firebaseAuthClient: FirebaseAuthClientProtocol
    private let isFirebaseConfiguredProvider: () -> Bool

    init(
        firebaseAuthClient: FirebaseAuthClientProtocol = FirebaseAuthClient(),
        isFirebaseConfiguredProvider: @escaping () -> Bool = { FirebaseApp.app() != nil }
    ) {
        self.firebaseAuthClient = firebaseAuthClient
        self.isFirebaseConfiguredProvider = isFirebaseConfiguredProvider
    }

    var currentUser: AuthUser? {
        firebaseAuthClient.currentUserSnapshot
    }

    func observeAuthState() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            continuation.yield(firebaseAuthClient.currentUserSnapshot)

            let listenerHandle = firebaseAuthClient.startListening { authUser in
                continuation.yield(authUser)
            }

            continuation.onTermination = { [firebaseAuthClient] _ in
                Task { @MainActor in
                    firebaseAuthClient.stopListening(listenerHandle)
                }
            }
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        do {
            try await firebaseAuthClient.signInWithGoogle(idToken: idToken, accessToken: accessToken)
        } catch {
            throw Self.translated(error)
        }
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        do {
            try await firebaseAuthClient.signInWithApple(
                idToken: idToken,
                rawNonce: rawNonce,
                fullName: fullName
            )
        } catch {
            throw Self.translated(error)
        }
    }

    func signOut() throws {
        do {
            try firebaseAuthClient.signOut()
        } catch {
            throw Self.translated(error)
        }
    }

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
        do {
            try await firebaseAuthClient.updateCurrentUser(displayName: displayName, photoURL: photoURL)
        } catch {
            throw Self.translated(error)
        }
    }

    func isConfigured() -> Bool {
        isFirebaseConfiguredProvider()
    }

    func googleClientID() -> String? {
        if let clientID = Self.sanitizedClientID(FirebaseApp.app()?.options.clientID) {
            return clientID
        }

        if let clientID = Self.sanitizedClientID(Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) {
            return clientID
        }

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let clientID = Self.sanitizedClientID(dict["CLIENT_ID"] as? String) else {
            return nil
        }

        return clientID
    }

    private static func sanitizedClientID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains("REPLACE_WITH_FIREBASE") else { return nil }
        return trimmed
    }

    private static func translated(_ error: Error) -> Error {
        if let authError = error as? AuthGatewayError {
            return authError
        }

        let nsError = error as NSError
        guard nsError.domain == AuthErrorDomain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return error
        }

        switch code {
        case .webContextCancelled:
            return AuthGatewayError.cancelled
        case .accountExistsWithDifferentCredential:
            return AuthGatewayError.message(
                "Esiste già un account con un provider diverso. Accedi con il provider usato in precedenza."
            )
        case .credentialAlreadyInUse:
            return AuthGatewayError.message(
                "Queste credenziali risultano già collegate a un altro account."
            )
        case .internalError:
            return AuthGatewayError.message(firebaseInternalErrorMessage(from: nsError))
        case .operationNotAllowed:
            return AuthGatewayError.message("Login con Apple non abilitato in Firebase Authentication.")
        case .invalidCredential:
            return AuthGatewayError.message(
                "Credenziali Apple non valide oppure configurazione Apple/Firebase incompleta."
            )
        case .missingOrInvalidNonce:
            return AuthGatewayError.message("Nonce Apple non valido. Riprova.")
        case .appNotAuthorized:
            return AuthGatewayError.message("L'app non è autorizzata alla configurazione Firebase corrente.")
        case .invalidAPIKey:
            return AuthGatewayError.message("Configurazione Firebase non valida. Controlla GoogleService-Info.plist.")
        case .networkError:
            return AuthGatewayError.message("Errore di rete durante l'accesso. Riprova.")
        case .keychainError:
            return AuthGatewayError.message(
                "Impossibile completare l'accesso su questo dispositivo. Controlla account Apple e portachiavi."
            )
        default:
            return error
        }
    }

    private static func firebaseInternalErrorMessage(from error: NSError) -> String {
        let backendMessage = firebaseBackendMessage(from: error)
        if let backendMessage {
            let normalizedBackendMessage = backendMessage.uppercased()
            if normalizedBackendMessage.contains("CONFIGURATION_NOT_FOUND")
                || normalizedBackendMessage.contains("CONFIGURATION NOT FOUND") {
                return "Il provider Apple non risulta configurato nel progetto Firebase corrente. Controlla Sign-in method > Apple nel progetto pharmapp-1987 e verifica Service ID, Team ID, Key ID, private key e Return URL."
            }
            return "Firebase Auth ha restituito un errore interno: \(backendMessage). Verifica la configurazione del provider Apple in Firebase Console e Apple Developer."
        }

        if let underlyingError = deepestUnderlyingError(from: error),
           underlyingError.localizedDescription != error.localizedDescription {
            return "Firebase Auth ha restituito un errore interno: \(underlyingError.localizedDescription)"
        }

        return "Firebase Auth ha restituito un errore interno. Di solito indica una configurazione Apple/Firebase incompleta o non coerente."
    }

    private static func firebaseBackendMessage(from error: NSError) -> String? {
        let responseKey = "FIRAuthErrorUserInfoDeserializedResponseKey"

        if let directResponse = error.userInfo[responseKey] as? [String: AnyHashable],
           let message = normalizedValue(from: directResponse["message"] as? String) {
            return message
        }

        var currentError = error.userInfo[NSUnderlyingErrorKey] as? NSError
        while let unwrappedError = currentError {
            if let response = unwrappedError.userInfo[responseKey] as? [String: AnyHashable],
               let message = normalizedValue(from: response["message"] as? String) {
                return message
            }
            currentError = unwrappedError.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return nil
    }

    private static func deepestUnderlyingError(from error: NSError) -> NSError? {
        var currentError: NSError? = error
        var deepestError: NSError?

        while let nextError = currentError?.userInfo[NSUnderlyingErrorKey] as? NSError {
            deepestError = nextError
            currentError = nextError
        }

        return deepestError
    }

    private static func normalizedValue(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
