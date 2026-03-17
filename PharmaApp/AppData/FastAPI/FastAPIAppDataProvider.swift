import Foundation
import CoreData
import Combine

// MARK: - FastAPIAppDataProvider

/// AppDataProvider backed by the FastAPI backend.
///
/// Architecture:
/// - **Reads**: Delegated to an internal CoreDataAppDataProvider. Core Data acts as a local
///   mirror populated via bootstrap sync.
/// - **Writes**: Delegated to the CoreData gateway first (optimistic, instant UI feedback),
///   then synced to the FastAPI backend in a background Task. A bootstrap refresh after each
///   successful write ensures eventual consistency.
/// - **Catalog**: Routed directly through FastAPIClient (async).
/// - **Auth**: Reuses SupabaseAuthGatewayAdapter (login/token stays on Supabase SDK).
/// - **Backup**: Disabled (data lives server-side; iCloud backup removed).
/// - **Notifications / Intents**: Delegated to CoreData gateways (iOS-local scheduling).
@MainActor
final class FastAPIAppDataProvider: AppDataProvider {
    let backend: BackendType = .fastapi

    let medicines: any MedicinesGateway
    let catalog: any CatalogGateway
    let search: any SearchGateway
    let adherence: any AdherenceGateway
    let people: any PeopleGateway
    let settings: any SettingsGateway
    let notifications: any NotificationsGateway
    let intents: any IntentsGateway
    let auth: any AuthGateway
    let backup: any BackupGateway

    let client: FastAPIClient
    let dataSync: FastAPIDataSync
    let syncCoordinator: SyncCoordinator
    let networkMonitor: NetworkMonitor
    let syncState: SyncState

    /// The internal CoreData provider that handles all local read/write logic.
    private let coreDataProvider: CoreDataAppDataProvider

    init(
        client: FastAPIClient,
        persistenceController: PersistenceController = .shared,
        networkMonitor: NetworkMonitor = NetworkMonitor()
    ) {
        self.client = client
        self.networkMonitor = networkMonitor
        self.dataSync = FastAPIDataSync(
            client: client,
            persistenceController: persistenceController
        )

        let coordinator = SyncCoordinator(
            client: client,
            dataSync: dataSync,
            networkMonitor: networkMonitor
        )
        self.syncCoordinator = coordinator
        self.syncState = coordinator.state

        let authGateway = SupabaseAuthGatewayAdapter()
        let backupGateway = FastAPIBackupGateway()
        let context = persistenceController.container.viewContext

        self.coreDataProvider = CoreDataAppDataProvider(
            authGateway: authGateway,
            backupGateway: backupGateway,
            context: context
        )

        self.medicines = FastAPIMedicinesGateway(
            coreData: coreDataProvider.medicines,
            client: client,
            dataSync: dataSync,
            syncCoordinator: coordinator,
            networkMonitor: networkMonitor
        )
        self.catalog = FastAPICatalogGateway(client: client)
        self.search = FastAPISearchGateway(
            coreData: coreDataProvider.search,
            client: client,
            dataSync: dataSync,
            syncCoordinator: coordinator,
            networkMonitor: networkMonitor
        )
        self.adherence = coreDataProvider.adherence
        self.people = coreDataProvider.people
        self.settings = FastAPISettingsGateway(
            coreData: coreDataProvider.settings,
            client: client,
            dataSync: dataSync,
            syncCoordinator: coordinator,
            networkMonitor: networkMonitor
        )
        self.notifications = coreDataProvider.notifications
        self.intents = coreDataProvider.intents
        self.auth = authGateway
        self.backup = backupGateway
    }

    func observe(scopes: Set<DataScope>) -> AsyncStream<DataChangeEvent> {
        coreDataProvider.observe(scopes: scopes)
    }

    /// Performs the initial bootstrap sync, populating the Core Data mirror from the API.
    /// Also starts the network monitor and sync coordinator.
    func performInitialSync() async throws {
        networkMonitor.start()
        try await dataSync.performBootstrapSync()
        await syncCoordinator.start()
    }
}

// MARK: - Logging Helper

private func fastAPILog(_ message: String, id: UUID? = nil) {
    if let id {
        print("[FastAPI] \(message) [\(id.uuidString.prefix(8))]")
    } else {
        print("[FastAPI] \(message)")
    }
}

// MARK: - IgnoredDecodable

/// A decodable type that accepts any JSON response when we don't need the response body.
private struct IgnoredDecodable: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}

// MARK: - FastAPIMedicinesGateway

/// Wraps the CoreData MedicinesGateway, adding background API synchronisation for writes.
/// When offline, mutations are queued via SyncCoordinator and flushed when connectivity restores.
@MainActor
private final class FastAPIMedicinesGateway: MedicinesGateway {
    private let coreData: any MedicinesGateway
    private let client: FastAPIClient
    private let dataSync: FastAPIDataSync
    private let syncCoordinator: SyncCoordinator
    private let networkMonitor: NetworkMonitor

    init(
        coreData: any MedicinesGateway,
        client: FastAPIClient,
        dataSync: FastAPIDataSync,
        syncCoordinator: SyncCoordinator,
        networkMonitor: NetworkMonitor
    ) {
        self.coreData = coreData
        self.client = client
        self.dataSync = dataSync
        self.syncCoordinator = syncCoordinator
        self.networkMonitor = networkMonitor
    }

    // MARK: Read Methods — delegated to CoreData

    func fetchCabinetSnapshot() throws -> MedicinesCabinetSnapshot {
        try coreData.fetchCabinetSnapshot()
    }

    func fetchCurrentOption() throws -> Option? {
        try coreData.fetchCurrentOption()
    }

    func fetchMedicineDetailSnapshot(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?
    ) throws -> MedicinesDetailSnapshot {
        try coreData.fetchMedicineDetailSnapshot(
            medicine: medicine,
            package: package,
            medicinePackage: medicinePackage
        )
    }

    func fetchTherapyFormSnapshot() throws -> MedicinesTherapyFormSnapshot {
        try coreData.fetchTherapyFormSnapshot()
    }

    func hasSufficientStockForIntake(entryId: UUID) -> Bool {
        coreData.hasSufficientStockForIntake(entryId: entryId)
    }

    func units(for package: Package) -> Int {
        coreData.units(for: package)
    }

    func deadlineMonthYear(
        medicine: Medicine,
        package: Package,
        preferredEntry: MedicinePackage?
    ) -> (month: Int, year: Int)? {
        coreData.deadlineMonthYear(
            medicine: medicine,
            package: package,
            preferredEntry: preferredEntry
        )
    }

    func recurrenceRule(for therapy: Therapy) -> RecurrenceRule {
        coreData.recurrenceRule(for: therapy)
    }

    func missedDoseCandidate(
        medicine: Medicine,
        package: Package?,
        now: Date
    ) -> MissedDoseCandidate? {
        coreData.missedDoseCandidate(medicine: medicine, package: package, now: now)
    }

    func loadLogs(medicine: Medicine) throws -> [Log] {
        try coreData.loadLogs(medicine: medicine)
    }

    // MARK: Write Methods — CoreData optimistic + offline-safe API sync

    @discardableResult
    func createCabinet(name: String) throws -> Cabinet {
        let cabinet = try coreData.createCabinet(name: name)
        let req = FastAPICreateCabinetRequest(name: name, isShared: false)
        syncOrEnqueue(endpoint: "/v1/cabinets", method: .post, body: req, label: "createCabinet", id: cabinet.id)
        return cabinet
    }

    @discardableResult
    func createCustomFilter(name: String, query: String) throws -> CabinetCustomFilterRecord {
        let record = try coreData.createCustomFilter(name: name, query: query)
        let req = FastAPICreateCustomFilterRequest(name: name, query: query)
        syncOrEnqueue(endpoint: "/v1/custom-filters", method: .post, body: req, label: "createCustomFilter")
        return record
    }

    @discardableResult
    func updateCustomFilter(id: UUID, name: String, query: String) throws -> CabinetCustomFilterRecord {
        let record = try coreData.updateCustomFilter(id: id, name: name, query: query)
        let req = FastAPIUpdateCustomFilterRequest(name: name, query: query)
        syncOrEnqueue(endpoint: "/v1/custom-filters/\(id.uuidString)", method: .put, body: req, label: "updateCustomFilter", id: id)
        return record
    }

    func deleteCustomFilter(id: UUID) throws {
        try coreData.deleteCustomFilter(id: id)
        syncOrEnqueue(endpoint: "/v1/custom-filters/\(id.uuidString)", method: .delete, label: "deleteCustomFilter", id: id)
    }

    func moveEntry(entryId: UUID, toCabinet cabinetId: UUID?) throws {
        try coreData.moveEntry(entryId: entryId, toCabinet: cabinetId)
        let req = FastAPIMoveCabinetRequest(cabinetId: cabinetId)
        syncOrEnqueue(endpoint: "/v1/entries/\(entryId.uuidString)/cabinet", method: .put, body: req, label: "moveEntry", id: entryId)
    }

    @discardableResult
    func addPurchase(medicine: Medicine, package: Package) -> Bool {
        let result = coreData.addPurchase(medicine: medicine, package: package)
        guard result else { return false }
        let operationId = UUID()
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: medicine.id,
            trackedPackageId: package.id,
            therapyId: nil,
            scheduledDueAt: nil,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/purchase", method: .post, body: req, label: "addPurchase", operationId: operationId)
        return result
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        coreData.setStockUnits(medicine: medicine, package: package, targetUnits: targetUnits)
        let req = FastAPIStockSetRequest(stockUnits: targetUnits)
        syncOrEnqueue(endpoint: "/v1/stocks/\(package.id.uuidString)", method: .put, body: req, label: "setStockUnits")
    }

    func updateDeadline(
        medicine: Medicine,
        package: Package,
        preferredEntry: MedicinePackage?,
        month: Int?,
        year: Int?
    ) throws {
        try coreData.updateDeadline(
            medicine: medicine, package: package,
            preferredEntry: preferredEntry, month: month, year: year
        )
        if let eid = preferredEntry?.id {
            let req = FastAPIUpdateEntryRequest(cabinetId: nil, deadlineMonth: month, deadlineYear: year)
            syncOrEnqueue(
                endpoint: "/v1/medicines/\(medicine.id.uuidString)/entries/\(eid.uuidString)",
                method: .put, body: req, label: "updateDeadline"
            )
        }
    }

    func setLabels(medicine: Medicine, labels: [String]) throws {
        try coreData.setLabels(medicine: medicine, labels: labels)
        let req = FastAPISetLabelsRequest(labels: labels)
        syncOrEnqueue(endpoint: "/v1/medicines/\(medicine.id.uuidString)/labels", method: .put, body: req, label: "setLabels")
    }

    func setCustomStockThreshold(medicine: Medicine, threshold: Int32) throws {
        try coreData.setCustomStockThreshold(medicine: medicine, threshold: threshold)
        let req = FastAPISetStockThresholdRequest(customStockThreshold: Int(threshold))
        syncOrEnqueue(endpoint: "/v1/medicines/\(medicine.id.uuidString)/stock-threshold", method: .put, body: req, label: "setCustomStockThreshold")
    }

    func deleteCabinet(cabinetId: UUID, moveToCabinetId: UUID?) throws {
        try coreData.deleteCabinet(cabinetId: cabinetId, moveToCabinetId: moveToCabinetId)
        syncOrEnqueue(endpoint: "/v1/cabinets/\(cabinetId.uuidString)", method: .delete, label: "deleteCabinet", id: cabinetId)
    }

    func deletePackage(medicine: Medicine, package: Package) throws {
        let medId = medicine.id
        let pkgId = package.id
        try coreData.deletePackage(medicine: medicine, package: package)
        syncOrEnqueue(endpoint: "/v1/medicines/\(medId.uuidString)/packages/\(pkgId.uuidString)", method: .delete, label: "deletePackage")
    }

    func deleteMedicine(_ medicine: Medicine) throws {
        let medId = medicine.id
        try coreData.deleteMedicine(medicine)
        syncOrEnqueue(endpoint: "/v1/medicines/\(medId.uuidString)", method: .delete, label: "deleteMedicine", id: medId)
    }

    // MARK: Operations — CoreData optimistic + offline-safe API sync

    @discardableResult
    func recordIntake(
        medicine: Medicine,
        package: Package,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let result = coreData.recordIntake(
            medicine: medicine, package: package,
            medicinePackage: medicinePackage, operationId: operationId
        )
        guard result else { return result }
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: medicine.id,
            trackedPackageId: package.id,
            therapyId: nil,
            scheduledDueAt: nil,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/intake", method: .post, body: req, label: "recordIntake", operationId: operationId)
        return result
    }

    @discardableResult
    func recordMissedDoseIntake(
        candidate: MissedDoseCandidate,
        takenAt: Date,
        nextAction: MissedDoseNextAction,
        operationId: UUID
    ) -> Bool {
        let result = coreData.recordMissedDoseIntake(
            candidate: candidate, takenAt: takenAt,
            nextAction: nextAction, operationId: operationId
        )
        guard result else { return result }
        let therapy = candidate.therapy
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: therapy.medicine.id,
            trackedPackageId: therapy.package.id,
            therapyId: therapy.id,
            scheduledDueAt: candidate.scheduledAt,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/intake", method: .post, body: req, label: "recordMissedDoseIntake", operationId: operationId)
        return result
    }

    @discardableResult
    func recordPurchase(
        medicine: Medicine,
        package: Package?,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let result = coreData.recordPurchase(
            medicine: medicine, package: package,
            medicinePackage: medicinePackage, operationId: operationId
        )
        guard result else { return result }
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: medicine.id,
            trackedPackageId: package?.id,
            therapyId: nil,
            scheduledDueAt: nil,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/purchase", method: .post, body: req, label: "recordPurchase", operationId: operationId)
        return result
    }

    @discardableResult
    func recordPrescriptionRequest(
        medicine: Medicine,
        package: Package?,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let result = coreData.recordPrescriptionRequest(
            medicine: medicine, package: package,
            medicinePackage: medicinePackage, operationId: operationId
        )
        guard result else { return result }
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: medicine.id,
            trackedPackageId: package?.id,
            therapyId: nil,
            scheduledDueAt: nil,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/prescription-request", method: .post, body: req, label: "recordPrescriptionRequest", operationId: operationId)
        return result
    }

    @discardableResult
    func recordPrescriptionReceived(
        medicine: Medicine,
        package: Package?,
        medicinePackage: MedicinePackage?,
        operationId: UUID
    ) -> Bool {
        let result = coreData.recordPrescriptionReceived(
            medicine: medicine, package: package,
            medicinePackage: medicinePackage, operationId: operationId
        )
        guard result else { return result }
        let req = FastAPIOperationRequest(
            operationId: operationId,
            trackedMedicineId: medicine.id,
            trackedPackageId: package?.id,
            therapyId: nil,
            scheduledDueAt: nil,
            actorDeviceId: UserIdentityProvider.shared.deviceId,
            source: "ios"
        )
        syncOrEnqueue(endpoint: "/v1/operations/prescription-received", method: .post, body: req, label: "recordPrescriptionReceived", operationId: operationId)
        return result
    }

    // MARK: Therapy CRUD — CoreData optimistic + offline-safe API sync

    func createTherapy(_ input: TherapyWriteInput) throws {
        try coreData.createTherapy(input)
        let medId = input.medicine.id
        let clinicalJson = input.clinicalRules?.encoded().flatMap {
            String(data: $0, encoding: .utf8)
        }
        let doseInputs = input.doses.enumerated().map { idx, d in
            FastAPITherapyDoseInput(
                timeOfDay: Self.timeOfDayString(from: d.time),
                amount: d.amount,
                sortOrder: idx
            )
        }
        let req = FastAPICreateTherapyRequest(
            trackedMedicineId: medId,
            trackedPackageId: input.package.id,
            personId: input.person.id,
            prescribingDoctorId: input.prescribingDoctor?.id,
            condition: input.condition,
            freq: input.freq,
            interval: input.interval,
            until: input.until,
            count: input.count,
            byDay: input.byDay.isEmpty ? nil : input.byDay,
            cycleOnDays: input.cycleOnDays,
            cycleOffDays: input.cycleOffDays,
            startDate: input.startDate,
            importance: input.importance,
            notificationLevel: input.notificationLevel.rawValue,
            snoozeMinutes: input.snoozeMinutes,
            manualIntake: input.manualIntake,
            notificationsSilenced: input.notificationsSilenced,
            clinicalRulesJson: clinicalJson,
            isActive: true,
            doses: doseInputs
        )
        syncOrEnqueue(endpoint: "/v1/medicines/\(medId.uuidString)/therapies", method: .post, body: req, label: "createTherapy")
    }

    func updateTherapy(_ therapy: Therapy, input: TherapyWriteInput) throws {
        try coreData.updateTherapy(therapy, input: input)
        let medId = input.medicine.id
        let therapyId = therapy.id
        let clinicalJson = input.clinicalRules?.encoded().flatMap {
            String(data: $0, encoding: .utf8)
        }
        let doseInputs = input.doses.enumerated().map { idx, d in
            FastAPITherapyDoseInput(
                timeOfDay: Self.timeOfDayString(from: d.time),
                amount: d.amount,
                sortOrder: idx
            )
        }
        let req = FastAPICreateTherapyRequest(
            trackedMedicineId: medId,
            trackedPackageId: input.package.id,
            personId: input.person.id,
            prescribingDoctorId: input.prescribingDoctor?.id,
            condition: input.condition,
            freq: input.freq,
            interval: input.interval,
            until: input.until,
            count: input.count,
            byDay: input.byDay.isEmpty ? nil : input.byDay,
            cycleOnDays: input.cycleOnDays,
            cycleOffDays: input.cycleOffDays,
            startDate: input.startDate,
            importance: input.importance,
            notificationLevel: input.notificationLevel.rawValue,
            snoozeMinutes: input.snoozeMinutes,
            manualIntake: input.manualIntake,
            notificationsSilenced: input.notificationsSilenced,
            clinicalRulesJson: clinicalJson,
            isActive: true,
            doses: doseInputs
        )
        syncOrEnqueue(
            endpoint: "/v1/medicines/\(medId.uuidString)/therapies/\(therapyId.uuidString)",
            method: .put, body: req, label: "updateTherapy", id: therapyId
        )
    }

    func deleteTherapy(_ therapy: Therapy) throws {
        let medId = therapy.medicine.id
        let therapyId = therapy.id
        try coreData.deleteTherapy(therapy)
        syncOrEnqueue(
            endpoint: "/v1/medicines/\(medId.uuidString)/therapies/\(therapyId.uuidString)",
            method: .delete, label: "deleteTherapy", id: therapyId
        )
    }

    // MARK: Sync Helpers

    /// Attempts direct API sync when online; falls back to queueing when offline or on failure.
    private func syncOrEnqueue<T: Encodable>(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        body: T? = nil as Data?,
        label: String,
        id: UUID? = nil,
        operationId: UUID? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = body.flatMap { try? encoder.encode($0) }

        if networkMonitor.isOnline {
            // Try direct sync; on failure, enqueue for later
            Task { [client, dataSync, syncCoordinator] in
                do {
                    switch method {
                    case .post:
                        if let data = bodyData {
                            let _: IgnoredDecodable = try await client.postRaw(endpoint, bodyData: data)
                        }
                    case .put:
                        if let data = bodyData {
                            let _: IgnoredDecodable = try await client.putRaw(endpoint, bodyData: data)
                        }
                    case .delete:
                        try await client.delete(endpoint)
                    case .get:
                        break
                    }
                    try await dataSync.refreshFromBootstrap()
                    fastAPILog("\(label) synced", id: id)
                } catch {
                    fastAPILog("\(label) direct sync failed, enqueuing: \(error)", id: id)
                    syncCoordinator.enqueueRaw(
                        endpoint: endpoint,
                        method: method,
                        bodyJSON: bodyData,
                        operationId: operationId
                    )
                }
            }
        } else {
            // Offline — queue immediately
            syncCoordinator.enqueueRaw(
                endpoint: endpoint,
                method: method,
                bodyJSON: bodyData,
                operationId: operationId
            )
            fastAPILog("\(label) queued (offline)", id: id)
        }
    }

    /// Overload for mutations without a body (e.g. DELETE).
    private func syncOrEnqueue(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        label: String,
        id: UUID? = nil,
        operationId: UUID? = nil
    ) {
        syncOrEnqueue(
            endpoint: endpoint,
            method: method,
            body: nil as Data?,
            label: label,
            id: id,
            operationId: operationId
        )
    }

    /// Converts a Date to "HH:mm" string for dose time-of-day.
    nonisolated private static func timeOfDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}

// MARK: - FastAPICatalogGateway

/// Routes catalog queries through the FastAPI backend rather than Supabase directly.
private final class FastAPICatalogGateway: CatalogGateway {
    private let client: FastAPIClient

    init(client: FastAPIClient) {
        self.client = client
    }

    func searchCatalog(
        country: CatalogCountry,
        query: String,
        limit: Int
    ) async throws -> [CatalogSelection] {
        let results: [FastAPICatalogSearchResult] = try await client.get(
            "/v1/catalog/search",
            query: [
                "country": country.rawValue,
                "q": query,
                "limit": String(limit)
            ]
        )
        return results.map { dto in
            CatalogSelection(
                id: dto.packageId,
                name: dto.displayName,
                principle: dto.principle ?? "",
                requiresPrescription: dto.requiresPrescription,
                packageLabel: dto.packageLabel,
                units: dto.unitsPerPackage,
                tipologia: dto.formType ?? "",
                valore: Int32(dto.dosageValue ?? 0),
                unita: dto.dosageUnit ?? "",
                volume: dto.volume ?? "",
                country: CatalogCountry(rawValue: dto.country) ?? .it,
                productKey: dto.productId,
                familyKey: dto.familyId,
                packageKey: dto.packageId,
                catalogCode: dto.catalogCode
            )
        }
    }

    func fetchCatalogProduct(
        country: CatalogCountry,
        productId: String
    ) async throws -> CatalogProduct {
        try await client.get(
            "/v1/catalog/products/\(country.rawValue)/\(productId)"
        )
    }

    func fetchCatalogPackage(
        country: CatalogCountry,
        packageId: String
    ) async throws -> CatalogPackage {
        try await client.get(
            "/v1/catalog/packages/\(country.rawValue)/\(packageId)"
        )
    }
}

// MARK: - FastAPISearchGateway

/// Wraps the CoreData SearchGateway with background API sync for writes.
/// Uses SyncCoordinator for offline-resilient syncing.
@MainActor
private final class FastAPISearchGateway: SearchGateway {
    private let coreData: any SearchGateway
    private let client: FastAPIClient
    private let dataSync: FastAPIDataSync
    private let syncCoordinator: SyncCoordinator
    private let networkMonitor: NetworkMonitor

    init(
        coreData: any SearchGateway,
        client: FastAPIClient,
        dataSync: FastAPIDataSync,
        syncCoordinator: SyncCoordinator,
        networkMonitor: NetworkMonitor
    ) {
        self.coreData = coreData
        self.client = client
        self.dataSync = dataSync
        self.syncCoordinator = syncCoordinator
        self.networkMonitor = networkMonitor
    }

    func fetchSnapshot() throws -> SearchDataSnapshot {
        try coreData.fetchSnapshot()
    }

    func addCatalogSelectionToCabinet(_ selection: CatalogSelection) throws {
        try coreData.addCatalogSelectionToCabinet(selection)

        // Build request to POST the medicine to the server
        let req = FastAPICreateMedicineFromCatalogRequest(
            cabinetId: nil,
            catalogCountry: selection.country.rawValue,
            catalogSource: selection.source,
            catalogProductId: selection.productKey,
            catalogFamilyKey: selection.familyKey,
            displayName: selection.name,
            principle: selection.principle,
            requiresPrescription: selection.requiresPrescription,
            labels: [],
            customStockThreshold: 0,
            manualIntakeRegistration: false,
            catalogSnapshot: [:],
            catalogPackageId: selection.packageKey,
            catalogCode: selection.catalogCode,
            formType: selection.tipologia.isEmpty ? nil : selection.tipologia,
            unitsPerPackage: selection.units,
            dosageValue: Double(selection.valore),
            dosageUnit: selection.unita.isEmpty ? nil : selection.unita,
            volume: selection.volume.isEmpty ? nil : selection.volume,
            packageSnapshot: [:]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let bodyData = try? encoder.encode(req) else {
            print("[FastAPI] addCatalogSelectionToCabinet: failed to encode request")
            return
        }

        if networkMonitor.isOnline {
            Task { [client, dataSync, syncCoordinator] in
                do {
                    let _: IgnoredDecodable = try await client.postRaw("/v1/medicines", bodyData: bodyData)
                    try await dataSync.refreshFromBootstrap()
                    print("[FastAPI] addCatalogSelectionToCabinet synced")
                } catch {
                    print("[FastAPI] addCatalogSelectionToCabinet sync failed, enqueuing: \(error)")
                    syncCoordinator.enqueueRaw(
                        endpoint: "/v1/medicines",
                        method: .post,
                        bodyJSON: bodyData,
                        operationId: nil
                    )
                }
            }
        } else {
            syncCoordinator.enqueueRaw(
                endpoint: "/v1/medicines",
                method: .post,
                bodyJSON: bodyData,
                operationId: nil
            )
            print("[FastAPI] addCatalogSelectionToCabinet queued (offline)")
        }
    }

    func prepareCatalogPackageEditor(
        _ selection: CatalogSelection
    ) throws -> SearchCatalogStockEditorPreparation {
        try coreData.prepareCatalogPackageEditor(selection)
    }

    func prepareCatalogTherapy(
        _ selection: CatalogSelection
    ) throws -> SearchCatalogResolvedContext {
        try coreData.prepareCatalogTherapy(selection)
    }

    func applyCatalogStockEditor(
        _ context: SearchCatalogResolvedContext,
        targetUnits: Int,
        deadlineMonth: Int?,
        deadlineYear: Int?
    ) throws {
        try coreData.applyCatalogStockEditor(
            context, targetUnits: targetUnits,
            deadlineMonth: deadlineMonth, deadlineYear: deadlineYear
        )
        Task { [dataSync, networkMonitor] in
            guard networkMonitor.isOnline else { return }
            do {
                try await dataSync.refreshFromBootstrap()
            } catch {
                print("[FastAPI] applyCatalogStockEditor sync error: \(error)")
            }
        }
    }
}

// MARK: - FastAPISettingsGateway

/// Wraps the CoreData SettingsGateway with background API sync for writes.
/// Uses SyncCoordinator for offline-resilient syncing.
@MainActor
private final class FastAPISettingsGateway: SettingsGateway {
    private let coreData: any SettingsGateway
    private let client: FastAPIClient
    private let dataSync: FastAPIDataSync
    private let syncCoordinator: SyncCoordinator
    private let networkMonitor: NetworkMonitor

    init(
        coreData: any SettingsGateway,
        client: FastAPIClient,
        dataSync: FastAPIDataSync,
        syncCoordinator: SyncCoordinator,
        networkMonitor: NetworkMonitor
    ) {
        self.coreData = coreData
        self.client = client
        self.dataSync = dataSync
        self.syncCoordinator = syncCoordinator
        self.networkMonitor = networkMonitor
    }

    // MARK: Reads — delegated

    func listPersons(includeAccount: Bool) throws -> [SettingsPersonRecord] {
        try coreData.listPersons(includeAccount: includeAccount)
    }

    func person(id: UUID) throws -> SettingsPersonRecord? {
        try coreData.person(id: id)
    }

    func listDoctors() throws -> [SettingsDoctorRecord] {
        try coreData.listDoctors()
    }

    func doctor(id: UUID) throws -> SettingsDoctorRecord? {
        try coreData.doctor(id: id)
    }

    func therapyNotificationPreferences() throws -> TherapyNotificationSettings {
        try coreData.therapyNotificationPreferences()
    }

    func prescriptionCodiceFiscaleEntriesForLowStock() throws -> [PrescriptionCFEntry] {
        try coreData.prescriptionCodiceFiscaleEntriesForLowStock()
    }

    // MARK: Writes — CoreData optimistic + offline-safe API sync

    @discardableResult
    func savePerson(_ input: PersonWriteInput) throws -> UUID {
        let personId = try coreData.savePerson(input)
        let isNew = input.id == nil
        let req = FastAPICreatePersonRequest(
            name: input.name,
            surname: nil,
            condition: input.condition,
            codiceFiscale: input.codiceFiscale,
            isAccount: input.isAccount
        )
        let endpoint = isNew ? "/v1/people" : "/v1/people/\(personId.uuidString)"
        let method: PendingMutation.HTTPMethod = isNew ? .post : .put
        syncOrEnqueue(endpoint: endpoint, method: method, body: req, label: "savePerson", id: personId)
        return personId
    }

    func deletePerson(id: UUID) throws {
        try coreData.deletePerson(id: id)
        syncOrEnqueue(endpoint: "/v1/people/\(id.uuidString)", method: .delete, label: "deletePerson", id: id)
    }

    @discardableResult
    func saveDoctor(_ input: DoctorWriteInput) throws -> UUID {
        let doctorId = try coreData.saveDoctor(input)
        let isNew = input.id == nil
        let req = FastAPICreateDoctorRequest(
            name: input.name,
            surname: nil,
            email: input.email,
            phone: input.phone,
            address: nil,
            specialization: input.specialization,
            scheduleJson: Self.scheduleToAnyCodable(input.schedule),
            secretaryName: input.secretaryName,
            secretaryEmail: input.secretaryEmail,
            secretaryPhone: input.secretaryPhone,
            secretaryScheduleJson: Self.scheduleToAnyCodable(input.secretarySchedule),
            prescriptionMessageTemplate: nil
        )
        let endpoint = isNew ? "/v1/doctors" : "/v1/doctors/\(doctorId.uuidString)"
        let method: PendingMutation.HTTPMethod = isNew ? .post : .put
        syncOrEnqueue(endpoint: endpoint, method: method, body: req, label: "saveDoctor", id: doctorId)
        return doctorId
    }

    func deleteDoctor(id: UUID) throws {
        try coreData.deleteDoctor(id: id)
        syncOrEnqueue(endpoint: "/v1/doctors/\(id.uuidString)", method: .delete, label: "deleteDoctor", id: id)
    }

    /// Converts a DoctorScheduleDTO into [String: AnyCodable]? suitable for FastAPI's schedule_json field.
    private static func scheduleToAnyCodable(_ schedule: DoctorScheduleDTO) -> [String: AnyCodable]? {
        guard let data = try? JSONEncoder().encode(schedule),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.mapValues { AnyCodable($0) }
    }

    func savePrescriptionMessageTemplate(doctorId: UUID, template: String?) throws {
        try coreData.savePrescriptionMessageTemplate(doctorId: doctorId, template: template)
        let req = FastAPICreateDoctorRequest(
            name: nil, surname: nil, email: nil, phone: nil,
            address: nil, specialization: nil, scheduleJson: nil,
            secretaryName: nil, secretaryEmail: nil, secretaryPhone: nil,
            secretaryScheduleJson: nil,
            prescriptionMessageTemplate: template
        )
        syncOrEnqueue(endpoint: "/v1/doctors/\(doctorId.uuidString)", method: .put, body: req, label: "savePrescriptionMessageTemplate", id: doctorId)
    }

    func saveTherapyNotificationPreferences(
        level: TherapyNotificationLevel,
        snoozeMinutes: Int
    ) throws {
        try coreData.saveTherapyNotificationPreferences(
            level: level, snoozeMinutes: snoozeMinutes
        )
        let req = FastAPIUpdateSettingsRequest(
            therapyNotificationLevel: level.rawValue,
            therapySnoozeMinutes: snoozeMinutes,
            prescriptionMessageTemplate: nil
        )
        syncOrEnqueue(endpoint: "/v1/settings", method: .put, body: req, label: "saveTherapyNotificationPreferences")
    }

    // MARK: Sync Helpers

    private func syncOrEnqueue<T: Encodable>(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        body: T? = nil as Data?,
        label: String,
        id: UUID? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = body.flatMap { try? encoder.encode($0) }

        if networkMonitor.isOnline {
            Task { [client, dataSync, syncCoordinator] in
                do {
                    switch method {
                    case .post:
                        if let data = bodyData {
                            let _: IgnoredDecodable = try await client.postRaw(endpoint, bodyData: data)
                        }
                    case .put:
                        if let data = bodyData {
                            let _: IgnoredDecodable = try await client.putRaw(endpoint, bodyData: data)
                        }
                    case .delete:
                        try await client.delete(endpoint)
                    case .get:
                        break
                    }
                    try await dataSync.refreshFromBootstrap()
                    fastAPILog("Settings: \(label) synced", id: id)
                } catch {
                    fastAPILog("Settings: \(label) direct sync failed, enqueuing: \(error)", id: id)
                    syncCoordinator.enqueueRaw(endpoint: endpoint, method: method, bodyJSON: bodyData)
                }
            }
        } else {
            syncCoordinator.enqueueRaw(endpoint: endpoint, method: method, bodyJSON: bodyData)
            fastAPILog("Settings: \(label) queued (offline)", id: id)
        }
    }

    private func syncOrEnqueue(
        endpoint: String,
        method: PendingMutation.HTTPMethod,
        label: String,
        id: UUID? = nil
    ) {
        syncOrEnqueue(endpoint: endpoint, method: method, body: nil as Data?, label: label, id: id)
    }
}

// MARK: - FastAPIBackupGateway (Disabled)

/// Backup is disabled when using the FastAPI backend. Data lives server-side.
@MainActor
private final class FastAPIBackupGateway: BackupGateway {
    var state: BackupGatewayState {
        BackupGatewayState(
            status: .unavailable,
            cloudAvailability: .unavailable,
            snapshots: [],
            lastSuccessfulBackupAt: nil,
            lastErrorMessage: "Backup non disponibile. I dati sono sincronizzati con il server.",
            backupEnabled: false,
            restoreRevision: 0
        )
    }

    var status: BackupStatus { .unavailable }
    var cloudAvailability: BackupCloudAvailability { .unavailable }
    var snapshots: [BackupSnapshotDescriptor] { [] }
    var lastSuccessfulBackupAt: Date? { nil }
    var lastErrorMessage: String? {
        "Backup non disponibile. I dati sono sincronizzati con il server."
    }
    var backupEnabled: Bool {
        get { false }
        set {}
    }

    func start() {}
    func setEnabled(_ isEnabled: Bool) {}
    func setAuthenticatedUserID(_ userID: String?) {}
    func refreshSnapshots() {}

    func observeState() -> AsyncStream<BackupGatewayState> {
        AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }

    @discardableResult
    func performManualBackup() async -> Bool { false }

    @discardableResult
    func performAutomaticBackupIfNeeded() async -> Bool { false }

    @discardableResult
    func restore(snapshotId: BackupSnapshotDescriptor.ID) async -> Bool { false }

    func listSnapshots() -> [BackupSnapshotDescriptor] { [] }
}
