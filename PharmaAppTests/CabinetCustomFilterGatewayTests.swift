import XCTest
import CoreData
@testable import PharmaApp

@MainActor
final class CabinetCustomFilterGatewayTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var provider: CoreDataAppDataProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
        provider = CoreDataAppDataProvider(
            authGateway: TestAuthGateway(userID: "user-1"),
            backupGateway: TestBackupGateway(),
            context: context,
            notificationCenter: NotificationCenter()
        )
    }

    override func tearDownWithError() throws {
        provider = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testCreateUpdateDeleteCustomFilterLifecycle() throws {
        let created = try provider.medicines.createCustomFilter(
            name: "Scorte basse",
            query: "stock:low"
        )

        XCTAssertEqual(created.name, "Scorte basse")
        XCTAssertEqual(created.query, "stock:low")
        XCTAssertEqual(created.position, 0)

        let snapshotAfterCreate = try provider.medicines.fetchCabinetSnapshot()
        XCTAssertEqual(snapshotAfterCreate.customFilters.count, 1)
        XCTAssertEqual(snapshotAfterCreate.customFilters.first?.id, created.id)

        let updated = try provider.medicines.updateCustomFilter(
            id: created.id,
            name: "Scorte critiche",
            query: "stock:out"
        )

        XCTAssertEqual(updated.id, created.id)
        XCTAssertEqual(updated.name, "Scorte critiche")
        XCTAssertEqual(updated.query, "stock:out")

        try provider.medicines.deleteCustomFilter(id: created.id)

        let snapshotAfterDelete = try provider.medicines.fetchCabinetSnapshot()
        XCTAssertTrue(snapshotAfterDelete.customFilters.isEmpty)
    }

    func testCustomFiltersAreScopedByOwner() throws {
        let ownerFilter = CustomFilter(context: context)
        ownerFilter.id = UUID()
        ownerFilter.owner_user_id = "user-1"
        ownerFilter.name = "Owner"
        ownerFilter.query = "stock:low"
        ownerFilter.position = 0
        ownerFilter.created_at = Date()
        ownerFilter.updated_at = Date()

        let foreignFilter = CustomFilter(context: context)
        foreignFilter.id = UUID()
        foreignFilter.owner_user_id = "user-2"
        foreignFilter.name = "Foreign"
        foreignFilter.query = "stock:out"
        foreignFilter.position = 1
        foreignFilter.created_at = Date()
        foreignFilter.updated_at = Date()

        try context.save()

        let snapshot = try provider.medicines.fetchCabinetSnapshot()
        XCTAssertEqual(snapshot.customFilters.map(\.name), ["Owner"])
    }

    func testCustomFiltersKeepCreationOrderByPosition() throws {
        let first = try provider.medicines.createCustomFilter(
            name: "Primo",
            query: "stock:low"
        )
        let second = try provider.medicines.createCustomFilter(
            name: "Secondo",
            query: "stock:out"
        )

        XCTAssertEqual(first.position, 0)
        XCTAssertEqual(second.position, 1)

        let snapshot = try provider.medicines.fetchCabinetSnapshot()
        XCTAssertEqual(snapshot.customFilters.map(\.name), ["Primo", "Secondo"])
    }
}

@MainActor
private final class TestAuthGateway: AuthGateway {
    private let userID: String

    init(userID: String) {
        self.userID = userID
    }

    var currentUser: AuthUser? {
        AuthUser(id: userID, provider: .google, email: nil, fullName: nil, imageURL: nil)
    }

    func observeAuthState() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            continuation.yield(currentUser)
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        let _ = idToken
        let _ = accessToken
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let _ = idToken
        let _ = rawNonce
        let _ = fullName
    }

    func signOut() throws {}

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
        let _ = displayName
        let _ = photoURL
    }

    func isConfigured() -> Bool { true }

    func googleClientID() -> String? { nil }
}

@MainActor
private final class TestBackupGateway: BackupGateway {
    var backupEnabled: Bool = false

    private(set) var state: BackupGatewayState = BackupGatewayState(
        status: .idle,
        cloudAvailability: .unavailable,
        snapshots: [],
        lastSuccessfulBackupAt: nil,
        lastErrorMessage: nil,
        backupEnabled: false,
        restoreRevision: 0
    )

    var status: BackupStatus { state.status }
    var cloudAvailability: BackupCloudAvailability { state.cloudAvailability }
    var snapshots: [BackupSnapshotDescriptor] { state.snapshots }
    var lastSuccessfulBackupAt: Date? { state.lastSuccessfulBackupAt }
    var lastErrorMessage: String? { state.lastErrorMessage }

    func start() {}

    func setEnabled(_ isEnabled: Bool) {
        backupEnabled = isEnabled
    }

    func setAuthenticatedUserID(_ userID: String?) {
        let _ = userID
    }

    func refreshSnapshots() {}

    func observeState() -> AsyncStream<BackupGatewayState> {
        AsyncStream { continuation in
            continuation.yield(state)
        }
    }

    func performManualBackup() async -> Bool { false }

    func performAutomaticBackupIfNeeded() async -> Bool { false }

    func restore(snapshotId: BackupSnapshotDescriptor.ID) async -> Bool {
        let _ = snapshotId
        return false
    }

    func listSnapshots() -> [BackupSnapshotDescriptor] { [] }
}
