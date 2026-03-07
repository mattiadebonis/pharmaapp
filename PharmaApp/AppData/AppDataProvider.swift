import Foundation
import Combine

struct MedicinesCabinetSnapshot {
    let medicinePackages: [MedicinePackage]
    let options: [Option]
    let cabinets: [Cabinet]
}

struct MedicinesDetailSnapshot {
    let options: [Option]
    let doctors: [Doctor]
    let allMedicines: [Medicine]
    let therapies: [Therapy]
    let intakeLogs: [Log]
}

struct MedicinesTherapyFormSnapshot {
    let persons: [Person]
    let doctors: [Doctor]
}

struct TherapyDoseDraft: Hashable {
    let id: UUID
    let time: Date
    let amount: Double

    init(id: UUID = UUID(), time: Date, amount: Double) {
        self.id = id
        self.time = time
        self.amount = amount
    }
}

struct TherapyWriteInput {
    let medicine: Medicine
    let package: Package
    let medicinePackage: MedicinePackage?
    let freq: String?
    let interval: Int?
    let until: Date?
    let count: Int?
    let byDay: [String]
    let cycleOnDays: Int?
    let cycleOffDays: Int?
    let startDate: Date
    let doses: [TherapyDoseDraft]
    let importance: String
    let person: Person
    let prescribingDoctor: Doctor?
    let manualIntake: Bool
    let notificationsSilenced: Bool
    let notificationLevel: TherapyNotificationLevel
    let snoozeMinutes: Int
    let clinicalRules: ClinicalRules?
}

@MainActor
protocol MedicinesGateway {
    func fetchCabinetSnapshot() throws -> MedicinesCabinetSnapshot
    func fetchCurrentOption() throws -> Option?
    func fetchMedicineDetailSnapshot(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?
    ) throws -> MedicinesDetailSnapshot
    func fetchTherapyFormSnapshot() throws -> MedicinesTherapyFormSnapshot

    @discardableResult
    func createCabinet(name: String) throws -> Cabinet
    func moveEntry(entryId: UUID, toCabinet cabinetId: UUID?) throws
    func hasSufficientStockForIntake(entryId: UUID) -> Bool
    func units(for package: Package) -> Int
    @discardableResult
    func addPurchase(medicine: Medicine, package: Package) -> Bool
    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int)
    func updateDeadline(
        medicine: Medicine,
        package: Package,
        preferredEntry: MedicinePackage?,
        month: Int?,
        year: Int?
    ) throws
    func setCustomStockThreshold(medicine: Medicine, threshold: Int32) throws
    func deleteCabinet(cabinetId: UUID, moveToCabinetId: UUID?) throws
    func deletePackage(medicine: Medicine, package: Package) throws
    func deleteMedicine(_ medicine: Medicine) throws
    func loadLogs(medicine: Medicine) throws -> [Log]

    func missedDoseCandidate(medicine: Medicine, package: Package?, now: Date) -> MissedDoseCandidate?
    @discardableResult
    func recordMissedDoseIntake(
        candidate: MissedDoseCandidate,
        takenAt: Date,
        nextAction: MissedDoseNextAction,
        operationId: UUID
    ) -> Bool
    @discardableResult
    func recordIntake(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool
    func createTherapy(_ input: TherapyWriteInput) throws
    func updateTherapy(_ therapy: Therapy, input: TherapyWriteInput) throws
    func deleteTherapy(_ therapy: Therapy) throws
}
protocol CatalogGateway {}
struct SearchDataSnapshot {
    let medicines: [Medicine]
    let medicineEntries: [MedicinePackage]
    let therapies: [Therapy]
    let doctors: [Doctor]
    let persons: [Person]
    let option: Option?
}

struct SearchCatalogResolvedContext: Identifiable {
    let selection: CatalogSelection
    let medicine: Medicine
    let package: Package
    let entry: MedicinePackage

    var id: UUID { entry.id }
}

struct SearchCatalogStockEditorPreparation {
    let context: SearchCatalogResolvedContext
    let defaultTargetUnits: Int
    let deadlineMonth: String
    let deadlineYear: String
}

enum SearchGatewayError: Error {
    case persistence
    case purchaseRegistrationFailed
    case purchasedEntryNotFound
}

@MainActor
protocol SearchGateway {
    func fetchSnapshot() throws -> SearchDataSnapshot
    func addCatalogSelectionToCabinet(_ selection: CatalogSelection) throws
    func prepareCatalogPackageEditor(_ selection: CatalogSelection) throws -> SearchCatalogStockEditorPreparation
    func prepareCatalogTherapy(_ selection: CatalogSelection) throws -> SearchCatalogResolvedContext
    func applyCatalogStockEditor(
        _ context: SearchCatalogResolvedContext,
        targetUnits: Int,
        deadlineMonth: Int?,
        deadlineYear: Int?
    ) throws
}
@MainActor
protocol AdherenceGateway {
    func fetchTherapies() throws -> [Therapy]
    func fetchIntakeLogs() throws -> [Log]
    func fetchMedicines() throws -> [Medicine]
    func fetchPurchaseLogs(since cutoff: Date) throws -> [Log]
    func fetchMonitoringMeasurements(from start: Date, to endExclusive: Date) throws -> [MonitoringMeasurement]
}
protocol PeopleGateway {}
@MainActor
protocol NotificationsGateway {
    func start()
    func refreshAfterStoreChange(reason: String)
    func refreshCriticalLiveActivity(reason: String, now: Date?) async
    func markCriticalDoseTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool
    func remindCriticalDoseLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool
    func showCriticalDoseConfirmationThenRefresh(medicineName: String) async
}
@MainActor
protocol IntentsGateway {
    func queueRoute(_ route: AppRoute)
    func suggestedMedicines(limit: Int) -> [MedicineIntentEntity]
    func medicines(matching query: String, limit: Int) -> [MedicineIntentEntity]
    func medicines(withIDs ids: [String]) -> [MedicineIntentEntity]
    func markTaken(medicineID: String) -> SiriActionExecution
    func markPurchased(medicineID: String) -> SiriActionExecution
    func markPrescriptionReceived(medicineID: String) -> SiriActionExecution
    func nextDoseNow(now: Date) -> SiriNextDoseNow?
    func doneTodayStatus(now: Date) -> SiriDoneTodayStatus
    func purchaseSummary(maxItems: Int) -> SiriPurchaseSummary
}

@MainActor
protocol AppDataProvider {
    var backend: BackendType { get }
    func observe(scopes: Set<DataScope>) -> AsyncStream<DataChangeEvent>

    var medicines: any MedicinesGateway { get }
    var catalog: any CatalogGateway { get }
    var search: any SearchGateway { get }
    var adherence: any AdherenceGateway { get }
    var people: any PeopleGateway { get }
    var settings: any SettingsGateway { get }
    var notifications: any NotificationsGateway { get }
    var intents: any IntentsGateway { get }
    var auth: any AuthGateway { get }
    var backup: any BackupGateway { get }
}

@MainActor
final class AppDataStore: ObservableObject {
    let provider: any AppDataProvider

    init(provider: any AppDataProvider) {
        self.provider = provider
    }
}
