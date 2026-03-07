import Foundation
import AuthenticationServices

@MainActor
private struct SupabaseMedicinesGateway: MedicinesGateway {
    func fetchCabinetSnapshot() throws -> MedicinesCabinetSnapshot {
        throw SupabaseProviderError.notImplemented
    }

    func fetchCurrentOption() throws -> Option? {
        throw SupabaseProviderError.notImplemented
    }

    func fetchMedicineDetailSnapshot(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?
    ) throws -> MedicinesDetailSnapshot {
        let _ = medicine
        let _ = package
        let _ = medicinePackage
        throw SupabaseProviderError.notImplemented
    }

    func fetchTherapyFormSnapshot() throws -> MedicinesTherapyFormSnapshot {
        throw SupabaseProviderError.notImplemented
    }

    @discardableResult
    func createCabinet(name: String) throws -> Cabinet {
        let _ = name
        throw SupabaseProviderError.notImplemented
    }

    func moveEntry(entryId: UUID, toCabinet cabinetId: UUID?) throws {
        let _ = entryId
        let _ = cabinetId
        throw SupabaseProviderError.notImplemented
    }

    func hasSufficientStockForIntake(entryId: UUID) -> Bool {
        let _ = entryId
        return false
    }

    func units(for package: Package) -> Int {
        let _ = package
        return 0
    }

    @discardableResult
    func addPurchase(medicine: Medicine, package: Package) -> Bool {
        let _ = medicine
        let _ = package
        return false
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        let _ = medicine
        let _ = package
        let _ = targetUnits
    }

    func updateDeadline(
        medicine: Medicine,
        package: Package,
        preferredEntry: MedicinePackage?,
        month: Int?,
        year: Int?
    ) throws {
        let _ = medicine
        let _ = package
        let _ = preferredEntry
        let _ = month
        let _ = year
        throw SupabaseProviderError.notImplemented
    }

    func setCustomStockThreshold(medicine: Medicine, threshold: Int32) throws {
        let _ = medicine
        let _ = threshold
        throw SupabaseProviderError.notImplemented
    }

    func deleteCabinet(cabinetId: UUID, moveToCabinetId: UUID?) throws {
        let _ = cabinetId
        let _ = moveToCabinetId
        throw SupabaseProviderError.notImplemented
    }

    func deletePackage(medicine: Medicine, package: Package) throws {
        let _ = medicine
        let _ = package
        throw SupabaseProviderError.notImplemented
    }

    func deleteMedicine(_ medicine: Medicine) throws {
        let _ = medicine
        throw SupabaseProviderError.notImplemented
    }

    func loadLogs(medicine: Medicine) throws -> [Log] {
        let _ = medicine
        throw SupabaseProviderError.notImplemented
    }

    func missedDoseCandidate(medicine: Medicine, package: Package?, now: Date) -> MissedDoseCandidate? {
        let _ = medicine
        let _ = package
        let _ = now
        return nil
    }

    @discardableResult
    func recordMissedDoseIntake(
        candidate: MissedDoseCandidate,
        takenAt: Date,
        nextAction: MissedDoseNextAction,
        operationId: UUID
    ) -> Bool {
        let _ = candidate
        let _ = takenAt
        let _ = nextAction
        let _ = operationId
        return false
    }

    @discardableResult
    func recordIntake(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let _ = medicine
        let _ = package
        let _ = medicinePackage
        let _ = operationId
        return false
    }

    func createTherapy(_ input: TherapyWriteInput) throws {
        let _ = input
        throw SupabaseProviderError.notImplemented
    }

    func updateTherapy(_ therapy: Therapy, input: TherapyWriteInput) throws {
        let _ = therapy
        let _ = input
        throw SupabaseProviderError.notImplemented
    }

    func deleteTherapy(_ therapy: Therapy) throws {
        let _ = therapy
        throw SupabaseProviderError.notImplemented
    }
}
private struct SupabaseCatalogGateway: CatalogGateway {}
@MainActor
private struct SupabaseSearchGateway: SearchGateway {
    func fetchSnapshot() throws -> SearchDataSnapshot {
        throw SupabaseProviderError.notImplemented
    }

    func addCatalogSelectionToCabinet(_ selection: CatalogSelection) throws {
        let _ = selection
        throw SupabaseProviderError.notImplemented
    }

    func prepareCatalogPackageEditor(_ selection: CatalogSelection) throws -> SearchCatalogStockEditorPreparation {
        let _ = selection
        throw SupabaseProviderError.notImplemented
    }

    func prepareCatalogTherapy(_ selection: CatalogSelection) throws -> SearchCatalogResolvedContext {
        let _ = selection
        throw SupabaseProviderError.notImplemented
    }

    func applyCatalogStockEditor(
        _ context: SearchCatalogResolvedContext,
        targetUnits: Int,
        deadlineMonth: Int?,
        deadlineYear: Int?
    ) throws {
        let _ = context
        let _ = targetUnits
        let _ = deadlineMonth
        let _ = deadlineYear
        throw SupabaseProviderError.notImplemented
    }
}
@MainActor
private struct SupabaseAdherenceGateway: AdherenceGateway {
    func fetchTherapies() throws -> [Therapy] {
        throw SupabaseProviderError.notImplemented
    }

    func fetchIntakeLogs() throws -> [Log] {
        throw SupabaseProviderError.notImplemented
    }

    func fetchMedicines() throws -> [Medicine] {
        throw SupabaseProviderError.notImplemented
    }

    func fetchPurchaseLogs(since cutoff: Date) throws -> [Log] {
        let _ = cutoff
        throw SupabaseProviderError.notImplemented
    }

    func fetchMonitoringMeasurements(from start: Date, to endExclusive: Date) throws -> [MonitoringMeasurement] {
        let _ = start
        let _ = endExclusive
        throw SupabaseProviderError.notImplemented
    }
}
private struct SupabasePeopleGateway: PeopleGateway {}
@MainActor
private struct SupabaseSettingsGateway: SettingsGateway {
    func listPersons(includeAccount: Bool) throws -> [SettingsPersonRecord] {
        let _ = includeAccount
        throw SupabaseProviderError.notImplemented
    }

    func person(id: UUID) throws -> SettingsPersonRecord? {
        let _ = id
        throw SupabaseProviderError.notImplemented
    }

    func listDoctors() throws -> [SettingsDoctorRecord] {
        throw SupabaseProviderError.notImplemented
    }

    func doctor(id: UUID) throws -> SettingsDoctorRecord? {
        let _ = id
        throw SupabaseProviderError.notImplemented
    }

    func therapyNotificationPreferences() throws -> TherapyNotificationSettings {
        throw SupabaseProviderError.notImplemented
    }

    @discardableResult
    func savePerson(_ input: PersonWriteInput) throws -> UUID {
        let _ = input
        throw SupabaseProviderError.notImplemented
    }

    func deletePerson(id: UUID) throws {
        let _ = id
        throw SupabaseProviderError.notImplemented
    }

    @discardableResult
    func saveDoctor(_ input: DoctorWriteInput) throws -> UUID {
        let _ = input
        throw SupabaseProviderError.notImplemented
    }

    func deleteDoctor(id: UUID) throws {
        let _ = id
        throw SupabaseProviderError.notImplemented
    }

    func savePrescriptionMessageTemplate(doctorId: UUID, template: String?) throws {
        let _ = doctorId
        let _ = template
        throw SupabaseProviderError.notImplemented
    }

    func saveTherapyNotificationPreferences(level: TherapyNotificationLevel, snoozeMinutes: Int) throws {
        let _ = level
        let _ = snoozeMinutes
        throw SupabaseProviderError.notImplemented
    }
}
@MainActor
private struct SupabaseIntentsGateway: IntentsGateway {
    func queueRoute(_ route: AppRoute) {
        let _ = route
    }

    func suggestedMedicines(limit: Int) -> [MedicineIntentEntity] {
        let _ = limit
        return []
    }

    func medicines(matching query: String, limit: Int) -> [MedicineIntentEntity] {
        let _ = query
        let _ = limit
        return []
    }

    func medicines(withIDs ids: [String]) -> [MedicineIntentEntity] {
        let _ = ids
        return []
    }

    func markTaken(medicineID: String) -> SiriActionExecution {
        let _ = medicineID
        return notImplementedExecution()
    }

    func markPurchased(medicineID: String) -> SiriActionExecution {
        let _ = medicineID
        return notImplementedExecution()
    }

    func markPrescriptionReceived(medicineID: String) -> SiriActionExecution {
        let _ = medicineID
        return notImplementedExecution()
    }

    func nextDoseNow(now: Date) -> SiriNextDoseNow? {
        let _ = now
        return nil
    }

    func doneTodayStatus(now: Date) -> SiriDoneTodayStatus {
        let _ = now
        return SiriDoneTodayStatus(
            isDone: false,
            totalPlanned: 0,
            totalTaken: 0,
            missingMedicines: []
        )
    }

    func purchaseSummary(maxItems: Int) -> SiriPurchaseSummary {
        let _ = maxItems
        return SiriPurchaseSummary(items: [], totalCount: 0)
    }

    private func notImplementedExecution() -> SiriActionExecution {
        SiriActionExecution(
            succeeded: false,
            message: SupabaseProviderError.notImplemented.errorDescription ?? "Operazione non implementata.",
            medicineName: nil
        )
    }
}

@MainActor
private struct SupabaseNotificationsGateway: NotificationsGateway {
    func start() {}

    func refreshAfterStoreChange(reason: String) {
        let _ = reason
    }

    func refreshCriticalLiveActivity(reason: String, now: Date?) async {
        let _ = reason
        let _ = now
    }

    func markCriticalDoseTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        let _ = contentState
        return false
    }

    func remindCriticalDoseLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool {
        let _ = contentState
        let _ = now
        return false
    }

    func showCriticalDoseConfirmationThenRefresh(medicineName: String) async {
        let _ = medicineName
    }
}

private enum SupabaseProviderError: LocalizedError {
    case notImplemented

    var errorDescription: String? {
        "SupabaseAppDataProvider non implementato in questo step."
    }
}

@MainActor
private final class SupabaseAuthGateway: AuthGateway {
    var currentUser: AuthUser? { nil }

    func observeAuthState() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        throw SupabaseProviderError.notImplemented
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        throw SupabaseProviderError.notImplemented
    }

    func signOut() throws {
        throw SupabaseProviderError.notImplemented
    }

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
        throw SupabaseProviderError.notImplemented
    }

    func isConfigured() -> Bool {
        false
    }

    func googleClientID() -> String? {
        nil
    }
}

@MainActor
private final class SupabaseBackupGateway: BackupGateway {
    var state: BackupGatewayState {
        BackupGatewayState(
            status: .unavailable,
            cloudAvailability: .unavailable,
            snapshots: [],
            lastSuccessfulBackupAt: nil,
            lastErrorMessage: SupabaseProviderError.notImplemented.errorDescription,
            backupEnabled: false,
            restoreRevision: 0
        )
    }

    var status: BackupStatus { .unavailable }
    var cloudAvailability: BackupCloudAvailability { .unavailable }
    var snapshots: [BackupSnapshotDescriptor] { [] }
    var lastSuccessfulBackupAt: Date? { nil }
    var lastErrorMessage: String? { SupabaseProviderError.notImplemented.errorDescription }
    var backupEnabled: Bool {
        get { false }
        set { }
    }

    func start() {}
    func setEnabled(_ isEnabled: Bool) {
        let _ = isEnabled
    }
    func setAuthenticatedUserID(_ userID: String?) {}
    func refreshSnapshots() {}
    func observeState() -> AsyncStream<BackupGatewayState> {
        AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }

    @discardableResult
    func performManualBackup() async -> Bool {
        false
    }

    @discardableResult
    func performAutomaticBackupIfNeeded() async -> Bool {
        false
    }

    @discardableResult
    func restore(snapshotId: BackupSnapshotDescriptor.ID) async -> Bool {
        false
    }

    func listSnapshots() -> [BackupSnapshotDescriptor] {
        []
    }
}

@MainActor
final class SupabaseAppDataProvider: AppDataProvider {
    let backend: BackendType = .supabase

    let medicines: any MedicinesGateway = SupabaseMedicinesGateway()
    let catalog: any CatalogGateway = SupabaseCatalogGateway()
    let search: any SearchGateway = SupabaseSearchGateway()
    let adherence: any AdherenceGateway = SupabaseAdherenceGateway()
    let people: any PeopleGateway = SupabasePeopleGateway()
    let settings: any SettingsGateway = SupabaseSettingsGateway()
    let notifications: any NotificationsGateway = SupabaseNotificationsGateway()
    let intents: any IntentsGateway = SupabaseIntentsGateway()
    let auth: any AuthGateway = SupabaseAuthGateway()
    let backup: any BackupGateway = SupabaseBackupGateway()

    func observe(scopes: Set<DataScope>) -> AsyncStream<DataChangeEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
