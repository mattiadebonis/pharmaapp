import Foundation
import AuthenticationServices
import FirebaseAuth

typealias FirebaseAuthStateListener = @MainActor (AuthUser?) -> Void

protocol FirebaseAuthClientProtocol {
    var currentUserSnapshot: AuthUser? { get }
    func startListening(_ listener: @escaping FirebaseAuthStateListener) -> AnyObject
    func stopListening(_ handle: AnyObject)
    func signInWithGoogle(idToken: String, accessToken: String) async throws
    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws
    func signOut() throws
    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws
}

final class FirebaseAuthClient: FirebaseAuthClientProtocol {
    var currentUserSnapshot: AuthUser? {
        Self.mapUser(Auth.auth().currentUser)
    }

    func startListening(_ listener: @escaping FirebaseAuthStateListener) -> AnyObject {
        Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                listener(Self.mapUser(user))
            }
        } as AnyObject
    }

    func stopListening(_ handle: AnyObject) {
        guard let listenerHandle = handle as? NSObjectProtocol else { return }
        Auth.auth().removeStateDidChangeListener(listenerHandle)
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        _ = try await Auth.auth().signIn(with: credential)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: fullName
        )
        _ = try await Auth.auth().signIn(with: credential)

        guard let fullName else { return }
        let formatter = PersonNameComponentsFormatter()
        let formattedName = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formattedName.isEmpty else { return }

        try await updateCurrentUser(displayName: formattedName, photoURL: nil)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
        guard let user = Auth.auth().currentUser else { return }

        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDisplayNameChange = normalizedDisplayName != user.displayName
        let hasPhotoChange = photoURL != nil && photoURL != user.photoURL
        guard hasDisplayNameChange || hasPhotoChange else { return }

        let request = user.createProfileChangeRequest()
        if hasDisplayNameChange {
            request.displayName = normalizedDisplayName
        }
        if hasPhotoChange {
            request.photoURL = photoURL
        }
        try await request.commitChanges()
    }

    private static func mapUser(_ user: User?) -> AuthUser? {
        guard let user else { return nil }

        let providerData = user.providerData
        let provider = AuthProvider.fromFirebaseProviderIDs(providerData.map(\.providerID))
        let email = user.email ?? providerData.compactMap(\.email).first
        let fullName = user.displayName ?? providerData.compactMap(\.displayName).first
        let photoURL = user.photoURL ?? providerData.compactMap(\.photoURL).first

        return AuthUser(
            id: user.uid,
            provider: provider,
            email: email,
            fullName: fullName,
            imageURL: photoURL
        )
    }
}
