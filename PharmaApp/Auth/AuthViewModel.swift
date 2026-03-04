import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import UIKit

@MainActor
final class AuthViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case unauthenticated
        case authenticated
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var user: AuthUser?
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private let firebaseAuthClient: FirebaseAuthClientProtocol
    private let googleSignInClient: GoogleSignInClientProtocol
    private let legacyAuthStore: LegacyAuthStoreProtocol
    private let presentingViewControllerProvider: () -> UIViewController?
    private let isFirebaseConfigured: () -> Bool

    private var listenerHandle: AnyObject?
    private var didStart: Bool = false
    private var currentNonce: String?
    private var legacyUser: AuthUser?
    private var pendingProfileFallback: PendingProfileFallback?

    init(
        firebaseAuthClient: FirebaseAuthClientProtocol = FirebaseAuthClient(),
        googleSignInClient: GoogleSignInClientProtocol = GoogleSignInClient(),
        legacyAuthStore: LegacyAuthStoreProtocol = LegacyAuthStore(),
        presentingViewControllerProvider: (() -> UIViewController?)? = nil,
        isFirebaseConfigured: @escaping () -> Bool = { FirebaseApp.app() != nil }
    ) {
        self.firebaseAuthClient = firebaseAuthClient
        self.googleSignInClient = googleSignInClient
        self.legacyAuthStore = legacyAuthStore
        self.presentingViewControllerProvider = presentingViewControllerProvider ?? { UIApplication.topViewController() }
        self.isFirebaseConfigured = isFirebaseConfigured
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        state = .loading
        legacyUser = legacyAuthStore.consumeUser()

        guard isFirebaseConfigured() else {
            state = .unauthenticated
            return
        }

        listenerHandle = firebaseAuthClient.startListening { [weak self] authUser in
            self?.handleAuthStateDidChange(authUser)
        }
    }

    func handleAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        do {
            let nonce = try Self.randomNonceString()
            currentNonce = nonce
            request.nonce = Self.sha256(nonce)
        } catch {
            currentNonce = nil
            errorMessage = "Impossibile iniziare il login con Apple. Riprova."
        }
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Credenziali Apple non valide."
                return
            }
            Task {
                await performAppleSignIn(with: credential)
            }
        case .failure(let error):
            guard !Self.isCancellation(error) else { return }
            errorMessage = localizedMessage(for: error)
        }
    }

    func signInWithGoogle() {
        guard let clientID = Self.googleClientID() else {
            errorMessage = "Google Sign-In non configurato. Imposta CLIENT_ID e REVERSED_CLIENT_ID di Firebase."
            return
        }

        guard let presentingViewController = presentingViewControllerProvider() else {
            errorMessage = "Impossibile presentare il login Google."
            return
        }

        Task {
            await performGoogleSignIn(clientID: clientID, presentingViewController: presentingViewController)
        }
    }

    func signOut() {
        var capturedError: Error?

        do {
            try firebaseAuthClient.signOut()
        } catch {
            capturedError = error
        }

        googleSignInClient.signOut()
        pendingProfileFallback = nil

        if let capturedError {
            errorMessage = localizedMessage(for: capturedError)
        } else {
            errorMessage = nil
        }
    }

    func handleOpenURL(_ url: URL) {
        _ = googleSignInClient.handle(url: url)
    }

    func performGoogleSignIn(clientID: String, presentingViewController: UIViewController) async {
        isBusy = true
        errorMessage = nil
        defer {
            isBusy = false
        }

        do {
            let payload = try await googleSignInClient.signIn(
                presentingViewController: presentingViewController,
                clientID: clientID
            )
            pendingProfileFallback = PendingProfileFallback(
                provider: .google,
                email: payload.email,
                fullName: payload.fullName,
                imageURL: payload.imageURL
            )
            try await firebaseAuthClient.signInWithGoogle(idToken: payload.idToken, accessToken: payload.accessToken)
        } catch {
            pendingProfileFallback = nil
            guard !Self.isCancellation(error) else { return }
            errorMessage = localizedMessage(for: error)
        }
    }

    func applePayload(identityTokenData: Data?, fullName: PersonNameComponents?) throws -> AppleSignInPayload {
        guard let identityTokenData else {
            throw AuthFlowError.missingAppleIdentityToken
        }
        guard let currentNonce else {
            throw AuthFlowError.missingAppleNonce
        }
        guard let idToken = String(data: identityTokenData, encoding: .utf8), !idToken.isEmpty else {
            throw AuthFlowError.invalidAppleIdentityToken
        }

        return AppleSignInPayload(idToken: idToken, rawNonce: currentNonce, fullName: fullName)
    }

    func performAppleSignIn(with credential: ASAuthorizationAppleIDCredential) async {
        isBusy = true
        errorMessage = nil
        defer {
            isBusy = false
            currentNonce = nil
        }

        do {
            let payload = try applePayload(
                identityTokenData: credential.identityToken,
                fullName: credential.fullName
            )
            pendingProfileFallback = PendingProfileFallback(
                provider: .apple,
                email: credential.email,
                fullName: Self.formatAppleName(credential.fullName),
                imageURL: nil
            )
            try await firebaseAuthClient.signInWithApple(
                idToken: payload.idToken,
                rawNonce: payload.rawNonce,
                fullName: payload.fullName
            )
        } catch {
            pendingProfileFallback = nil
            guard !Self.isCancellation(error) else { return }
            errorMessage = localizedMessage(for: error)
        }
    }

    private func handleAuthStateDidChange(_ authUser: AuthUser?) {
        guard let authUser else {
            user = nil
            state = .unauthenticated
            return
        }

        let enrichedUser = enrich(authUser)
        user = enrichedUser
        state = .authenticated
        errorMessage = nil
        pendingProfileFallback = nil

        Task {
            await backfillFirebaseProfileIfNeeded(original: authUser, enriched: enrichedUser)
        }
    }

    private func enrich(_ authUser: AuthUser) -> AuthUser {
        var enrichedUser = authUser

        for fallback in [pendingProfileFallback, legacyFallback(for: authUser)] {
            guard let fallback, Self.shouldApplyFallback(fallback, to: authUser) else { continue }

            if Self.normalizedValue(from: enrichedUser.fullName) == nil {
                enrichedUser.fullName = fallback.fullName
            }

            if Self.normalizedValue(from: enrichedUser.email) == nil {
                enrichedUser.email = fallback.email
            }

            if enrichedUser.imageURL == nil {
                enrichedUser.imageURL = fallback.imageURL
            }
        }

        return enrichedUser
    }

    private func legacyFallback(for authUser: AuthUser) -> PendingProfileFallback? {
        guard let legacyUser else { return nil }
        return PendingProfileFallback(
            provider: legacyUser.provider,
            email: legacyUser.email,
            fullName: legacyUser.fullName,
            imageURL: legacyUser.imageURL
        )
    }

    private func backfillFirebaseProfileIfNeeded(original: AuthUser, enriched: AuthUser) async {
        let needsDisplayName = Self.normalizedValue(from: original.fullName) == nil
            && Self.normalizedValue(from: enriched.fullName) != nil
        let needsPhoto = original.imageURL == nil && enriched.imageURL != nil

        guard needsDisplayName || needsPhoto else { return }

        do {
            try await firebaseAuthClient.updateCurrentUser(
                displayName: enriched.fullName,
                photoURL: enriched.imageURL
            )
        } catch {
            // Non blocchiamo la sessione se l'aggiornamento profilo fallisce.
        }
    }

    private static func formatAppleName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components)
        return normalizedValue(from: name)
    }

    private static func googleClientID() -> String? {
        if let clientID = sanitizedClientID(FirebaseApp.app()?.options.clientID) {
            return clientID
        }

        if let clientID = sanitizedClientID(Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) {
            return clientID
        }

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let clientID = sanitizedClientID(dict["CLIENT_ID"] as? String) else {
            return nil
        }

        return clientID
    }

    private func localizedMessage(for error: Error) -> String? {
        if let flowError = error as? AuthFlowError {
            return flowError.errorDescription
        }

        if let googleError = error as? GoogleSignInClientError {
            return googleError.errorDescription
        }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .accountExistsWithDifferentCredential:
                return "Esiste già un account con un provider diverso. Accedi con il provider usato in precedenza."
            case .credentialAlreadyInUse:
                return "Queste credenziali risultano già collegate a un altro account."
            case .missingOrInvalidNonce:
                return "Nonce Apple non valido. Riprova."
            case .webContextCancelled:
                return nil
            default:
                break
            }
        }

        return nsError.localizedDescription
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if let error = error as? GoogleSignInClientError, error == .cancelled {
            return true
        }

        if let error = error as? ASAuthorizationError, error.code == .canceled {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let authErrorCode = AuthErrorCode(rawValue: nsError.code),
           authErrorCode == .webContextCancelled {
            return true
        }

        return false
    }

    private static func normalizedValue(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedClientID(_ value: String?) -> String? {
        guard let trimmed = normalizedValue(from: value) else { return nil }
        if trimmed.contains("REPLACE_WITH_FIREBASE") {
            return nil
        }
        return trimmed
    }

    private static func shouldApplyFallback(_ fallback: PendingProfileFallback, to authUser: AuthUser) -> Bool {
        guard fallback.provider == authUser.provider else { return false }

        let fallbackEmail = normalizedValue(from: fallback.email)
        let authEmail = normalizedValue(from: authUser.email)
        if let fallbackEmail, let authEmail {
            return fallbackEmail.caseInsensitiveCompare(authEmail) == .orderedSame
        }

        return true
    }

    private static func randomNonceString(length: Int = 32) throws -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard status == errSecSuccess else {
            throw AuthFlowError.nonceGenerationFailed
        }

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ value: String) -> String {
        let inputData = Data(value.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension AuthViewModel {
    struct AppleSignInPayload {
        let idToken: String
        let rawNonce: String
        let fullName: PersonNameComponents?
    }
}

private extension AuthViewModel {
    struct PendingProfileFallback {
        let provider: AuthProvider
        let email: String?
        let fullName: String?
        let imageURL: URL?
    }

    enum AuthFlowError: LocalizedError {
        case missingAppleIdentityToken
        case invalidAppleIdentityToken
        case missingAppleNonce
        case nonceGenerationFailed

        var errorDescription: String? {
            switch self {
            case .missingAppleIdentityToken:
                return "Apple non ha restituito un token di identità valido."
            case .invalidAppleIdentityToken:
                return "Impossibile leggere il token restituito da Apple."
            case .missingAppleNonce:
                return "Nonce Apple mancante. Riprova."
            case .nonceGenerationFailed:
                return "Impossibile generare il nonce per Apple Sign-In."
            }
        }
    }
}
