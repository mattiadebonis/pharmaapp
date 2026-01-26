import SwiftUI
import AuthenticationServices

#if canImport(UIKit)
import UIKit
#endif

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@MainActor
final class AuthViewModel: ObservableObject {
    enum State {
        case loading
        case unauthenticated
        case authenticated
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var user: AuthUser?
    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private let storedUserKey = "auth.user"

    init() {
        Task { await restoreSession() }
    }

    func restoreSession() async {
        state = .loading
        var didAttemptGoogleRestore = false

        if let saved = loadUser() {
            switch saved.provider {
            case .apple:
                await restoreAppleSession(savedUser: saved)
                return
            case .google:
                didAttemptGoogleRestore = true
                if await restoreGoogleSession() != nil {
                    return
                }
            }
        }

        if !didAttemptGoogleRestore {
            didAttemptGoogleRestore = true
            if await restoreGoogleSession() != nil {
                return
            }
        }

        state = .unauthenticated
    }

    func handleAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Credenziali Apple non valide."
                state = .unauthenticated
                return
            }

            let userID = credential.user
            let fullName = Self.formatAppleName(credential.fullName)
            let email = credential.email

            var existing = loadUser()
            if existing?.provider == .apple, existing?.id == userID {
                if existing?.fullName == nil || existing?.fullName?.isEmpty == true {
                    existing?.fullName = fullName
                }
                if existing?.email == nil || existing?.email?.isEmpty == true {
                    existing?.email = email
                }
            }

            let authUser = existing ?? AuthUser(
                id: userID,
                provider: .apple,
                email: email,
                fullName: fullName,
                imageURL: nil
            )

            setAuthenticated(authUser)
        case .failure(let error):
            errorMessage = error.localizedDescription
            state = .unauthenticated
        }
    }

    func signInWithGoogle() {
        #if canImport(GoogleSignIn)
        guard let clientID = Self.googleClientID() else {
            errorMessage = "Client ID Google mancante. Aggiungi GIDClientID o GoogleService-Info.plist."
            return
        }

        guard let presentingViewController = UIApplication.topViewController() else {
            errorMessage = "Impossibile presentare il login Google."
            return
        }

        let configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = configuration
        isBusy = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let result else {
                    self.errorMessage = "Login Google annullato."
                    return
                }

                let authUser = Self.mapGoogleUser(result.user)
                self.setAuthenticated(authUser)
            }
        }
        #else
        errorMessage = "Google Sign-In non configurato: aggiungi i pacchetti GoogleSignIn."
        #endif
    }

    func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        clearStoredUser()
        user = nil
        state = .unauthenticated
    }

    func handleOpenURL(_ url: URL) {
        #if canImport(GoogleSignIn)
        _ = GIDSignIn.sharedInstance.handle(url)
        #endif
    }

    // MARK: - Private helpers

    private func restoreAppleSession(savedUser: AuthUser) async {
        let provider = ASAuthorizationAppleIDProvider()
        await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: savedUser.id) { state, _ in
                Task { @MainActor in
                    switch state {
                    case .authorized:
                        self.setAuthenticated(savedUser)
                    case .revoked, .notFound, .transferred:
                        self.clearStoredUser()
                        self.state = .unauthenticated
                    @unknown default:
                        self.state = .unauthenticated
                    }
                    continuation.resume()
                }
            }
        }
    }

    private func restoreGoogleSession() async -> AuthUser? {
        #if canImport(GoogleSignIn)
        if let clientID = Self.googleClientID() {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }

        return await withCheckedContinuation { continuation in
            guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
                continuation.resume(returning: nil)
                return
            }

            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                Task { @MainActor in
                    if let user {
                        let authUser = Self.mapGoogleUser(user)
                        self.setAuthenticated(authUser)
                        continuation.resume(returning: authUser)
                    } else {
                        if let error {
                            self.errorMessage = error.localizedDescription
                        }
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
        #else
        return nil
        #endif
    }

    private func setAuthenticated(_ authUser: AuthUser) {
        user = authUser
        persistUser(authUser)
        errorMessage = nil
        state = .authenticated
    }

    private func persistUser(_ authUser: AuthUser) {
        guard let data = try? JSONEncoder().encode(authUser) else { return }
        UserDefaults.standard.set(data, forKey: storedUserKey)
    }

    private func loadUser() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: storedUserKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return nil
        }
        return user
    }

    private func clearStoredUser() {
        UserDefaults.standard.removeObject(forKey: storedUserKey)
    }

    private static func formatAppleName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let name = formatter.string(from: components)
        return name.isEmpty ? nil : name
    }

    private static func googleClientID() -> String? {
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            return clientID
        }

        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path),
              let clientID = dict["CLIENT_ID"] as? String else {
            return nil
        }

        return clientID
    }

    #if canImport(GoogleSignIn)
    private static func mapGoogleUser(_ user: GIDGoogleUser) -> AuthUser {
        AuthUser(
            id: user.userID ?? UUID().uuidString,
            provider: .google,
            email: user.profile?.email,
            fullName: user.profile?.name,
            imageURL: user.profile?.imageURL(withDimension: 128)
        )
    }
    #endif
}
