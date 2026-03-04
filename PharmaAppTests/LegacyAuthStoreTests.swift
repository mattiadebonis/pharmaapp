import XCTest
@testable import PharmaApp

final class LegacyAuthStoreTests: XCTestCase {
    func testConsumeUserReturnsLegacyAuthUserAndRemovesStoredValue() throws {
        let suite = "LegacyAuthStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let legacyUser = AuthUser(
            id: "legacy-id",
            provider: .apple,
            email: "legacy@example.com",
            fullName: "Mario Rossi",
            imageURL: nil
        )
        let data = try JSONEncoder().encode(legacyUser)
        defaults.set(data, forKey: "auth.user")

        let store = LegacyAuthStore(defaults: defaults)
        let consumedUser = store.consumeUser()

        XCTAssertEqual(consumedUser, legacyUser)
        XCTAssertNil(defaults.data(forKey: "auth.user"))

        defaults.removePersistentDomain(forName: suite)
    }
}
