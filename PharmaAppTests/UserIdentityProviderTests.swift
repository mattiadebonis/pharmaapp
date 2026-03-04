import XCTest
import CoreData
@testable import PharmaApp

@MainActor
final class UserIdentityProviderTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testUserIdUsesFirebaseUIDAndMigratesLegacyProfileWithoutDuplicates() throws {
        let suite = "UserIdentityProviderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("legacy-user", forKey: "pharmaapp.user_id")

        let provider = UserIdentityProvider(
            userDefaults: defaults,
            authUserIDProvider: { "firebase-user" }
        )

        let legacyProfile = try makeUserProfile(userID: "legacy-user")
        legacyProfile.display_name = "Mario Rossi"
        legacyProfile.device_id = "device-1"
        try context.save()

        XCTAssertEqual(provider.userId, "firebase-user")

        provider.syncAuthenticatedIdentity(
            from: AuthUser(id: "firebase-user", provider: .google, email: "test@example.com", fullName: "Mario Rossi", imageURL: nil),
            in: context
        )

        let profiles = try fetchProfiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.user_id, "firebase-user")
        XCTAssertEqual(profiles.first?.display_name, "Mario Rossi")
        XCTAssertEqual(profiles.first?.device_id, "device-1")

        defaults.removePersistentDomain(forName: suite)
    }

    @discardableResult
    private func makeUserProfile(userID: String) throws -> UserProfile {
        guard let entity = NSEntityDescription.entity(forEntityName: "UserProfile", in: context) else {
            XCTFail("Entity UserProfile non trovata nel contesto di test")
            throw NSError(domain: "UserIdentityProviderTests", code: 1)
        }

        let profile = UserProfile(entity: entity, insertInto: context)
        profile.id = UUID()
        profile.user_id = userID
        profile.created_at = Date()
        return profile
    }

    private func fetchProfiles() throws -> [UserProfile] {
        let request = UserProfile.fetchRequest()
        return try context.fetch(request)
    }
}
