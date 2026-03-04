import XCTest
import AuthenticationServices
import UIKit
@testable import PharmaApp

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testStartTransitionsToAuthenticatedWhenFirebaseListenerReturnsUser() async {
        let firebaseClient = MockFirebaseAuthClient()
        let viewModel = makeViewModel(firebaseClient: firebaseClient)

        viewModel.start()
        firebaseClient.emit(user: AuthUser(id: "firebase-user", provider: .google, email: "test@example.com", fullName: "Mario Rossi", imageURL: nil))
        await settleAsyncState()

        XCTAssertEqual(viewModel.state, .authenticated)
        XCTAssertEqual(viewModel.user?.id, "firebase-user")
        XCTAssertEqual(viewModel.user?.fullName, "Mario Rossi")
    }

    func testStartTransitionsToUnauthenticatedWhenFirebaseListenerReturnsNil() async {
        let firebaseClient = MockFirebaseAuthClient()
        let viewModel = makeViewModel(firebaseClient: firebaseClient)

        viewModel.start()
        firebaseClient.emit(user: nil)
        await settleAsyncState()

        XCTAssertEqual(viewModel.state, .unauthenticated)
        XCTAssertNil(viewModel.user)
    }

    func testGoogleFlowSuccessAuthenticatesSession() async {
        let firebaseClient = MockFirebaseAuthClient()
        let googleClient = MockGoogleSignInClient()
        googleClient.result = .success(GoogleSignInPayload(
            idToken: "id-token",
            accessToken: "access-token",
            email: "test@example.com",
            fullName: "Mario Rossi",
            imageURL: URL(string: "https://example.com/avatar.png")
        ))
        firebaseClient.signInWithGoogleHandler = { [weak firebaseClient] idToken, accessToken in
            XCTAssertEqual(idToken, "id-token")
            XCTAssertEqual(accessToken, "access-token")
            firebaseClient?.emit(user: AuthUser(
                id: "firebase-google",
                provider: .google,
                email: "test@example.com",
                fullName: nil,
                imageURL: nil
            ))
        }
        let viewModel = makeViewModel(firebaseClient: firebaseClient, googleClient: googleClient)
        viewModel.start()
        firebaseClient.emit(user: nil)

        await viewModel.performGoogleSignIn(
            clientID: "client-id",
            presentingViewController: UIViewController()
        )

        XCTAssertEqual(viewModel.state, .authenticated)
        XCTAssertEqual(viewModel.user?.id, "firebase-google")
        XCTAssertEqual(viewModel.user?.fullName, "Mario Rossi")
        XCTAssertNil(viewModel.errorMessage)
    }

    func testGoogleFlowCancellationDoesNotShowError() async {
        let firebaseClient = MockFirebaseAuthClient()
        let googleClient = MockGoogleSignInClient()
        googleClient.result = .failure(GoogleSignInClientError.cancelled)
        let viewModel = makeViewModel(firebaseClient: firebaseClient, googleClient: googleClient)

        await viewModel.performGoogleSignIn(
            clientID: "client-id",
            presentingViewController: UIViewController()
        )

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testAppleRequestAddsScopesAndNonce() {
        let viewModel = makeViewModel()
        let request = ASAuthorizationAppleIDProvider().createRequest()

        viewModel.handleAppleRequest(request)

        XCTAssertEqual(request.requestedScopes, [.fullName, .email])
        XCTAssertNotNil(request.nonce)
        XCTAssertFalse(request.nonce?.isEmpty ?? true)
    }

    func testApplePayloadFailsWhenIdentityTokenIsMissing() {
        let viewModel = makeViewModel()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        viewModel.handleAppleRequest(request)

        XCTAssertThrowsError(try viewModel.applePayload(identityTokenData: nil, fullName: nil)) { error in
            XCTAssertEqual(error.localizedDescription, "Apple non ha restituito un token di identità valido.")
        }
    }

    func testSignOutCallsFirebaseAndGoogleAndTransitionsToUnauthenticated() async {
        let firebaseClient = MockFirebaseAuthClient()
        let googleClient = MockGoogleSignInClient()
        firebaseClient.signOutHandler = { [weak firebaseClient] in
            firebaseClient?.emit(user: nil)
        }
        let viewModel = makeViewModel(firebaseClient: firebaseClient, googleClient: googleClient)
        viewModel.start()
        firebaseClient.emit(user: AuthUser(id: "firebase-user", provider: .google, email: nil, fullName: "Mario Rossi", imageURL: nil))
        await settleAsyncState()

        viewModel.signOut()
        await settleAsyncState()

        XCTAssertTrue(firebaseClient.didCallSignOut)
        XCTAssertTrue(googleClient.didCallSignOut)
        XCTAssertEqual(viewModel.state, .unauthenticated)
        XCTAssertNil(viewModel.user)
    }

    private func makeViewModel(
        firebaseClient: MockFirebaseAuthClient = MockFirebaseAuthClient(),
        googleClient: MockGoogleSignInClient = MockGoogleSignInClient(),
        legacyStore: LegacyAuthStoreProtocol = StubLegacyAuthStore(user: nil)
    ) -> AuthViewModel {
        AuthViewModel(
            firebaseAuthClient: firebaseClient,
            googleSignInClient: googleClient,
            legacyAuthStore: legacyStore,
            presentingViewControllerProvider: { UIViewController() },
            isFirebaseConfigured: { true }
        )
    }

    private func settleAsyncState() async {
        await Task.yield()
        await Task.yield()
    }
}

private final class MockFirebaseAuthClient: FirebaseAuthClientProtocol {
    var currentUserSnapshot: AuthUser?
    var didCallSignOut = false
    var listener: ((AuthUser?) -> Void)?
    var signInWithGoogleHandler: ((String, String) async throws -> Void)?
    var signInWithAppleHandler: ((String, String, PersonNameComponents?) async throws -> Void)?
    var signOutHandler: (() throws -> Void)?

    func startListening(_ listener: @escaping FirebaseAuthStateListener) -> AnyObject {
        self.listener = { user in
            Task { @MainActor in
                listener(user)
            }
        }
        return NSObject()
    }

    func stopListening(_ handle: AnyObject) {
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        try await signInWithGoogleHandler?(idToken, accessToken)
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        try await signInWithAppleHandler?(idToken, rawNonce, fullName)
    }

    func signOut() throws {
        didCallSignOut = true
        try signOutHandler?()
    }

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
    }

    func emit(user: AuthUser?) {
        currentUserSnapshot = user
        listener?(user)
    }
}

private final class MockGoogleSignInClient: GoogleSignInClientProtocol {
    var result: Result<GoogleSignInPayload, Error> = .failure(GoogleSignInClientError.invalidConfiguration)
    var didCallSignOut = false

    func signIn(presentingViewController: UIViewController, clientID: String) async throws -> GoogleSignInPayload {
        try result.get()
    }

    func handle(url: URL) -> Bool {
        false
    }

    func signOut() {
        didCallSignOut = true
    }
}

private struct StubLegacyAuthStore: LegacyAuthStoreProtocol {
    let user: AuthUser?

    func consumeUser() -> AuthUser? {
        user
    }
}
