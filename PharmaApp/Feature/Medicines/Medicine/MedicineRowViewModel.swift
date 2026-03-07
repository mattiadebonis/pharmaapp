//
//  SuppliesViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 04/02/25.
//

import SwiftUI
import CoreData

class MedicineRowViewModel: ObservableObject {
    let managedObjectContext: NSManagedObjectContext
    private let operationIdProvider: OperationIdProviding

    // MARK: - PharmaCore dependencies
    private let pharmaCoreFactory: PharmaCoreFactory
    private(set) lazy var medicineActionUseCase = pharmaCoreFactory.makeMedicineActionUseCase()
    private(set) lazy var sectionCalculator = pharmaCoreFactory.makeSectionCalculator()

    private lazy var snapshotBuilder = CoreDataSnapshotBuilder(context: managedObjectContext)

    init(
        managedObjectContext: NSManagedObjectContext,
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared,
        pharmaCoreFactory: PharmaCoreFactory = PharmaCoreFactory()
    ) {
        self.managedObjectContext = managedObjectContext
        self.operationIdProvider = operationIdProvider
        self.pharmaCoreFactory = pharmaCoreFactory
    }

    func addNewPrescriptionRequest(for medicine: Medicine) {
        guard let packageId = resolvePackageId(for: medicine) else { return }
        let key = OperationKey.medicineAction(
            action: .prescriptionRequest,
            medicineId: medicine.id,
            packageId: packageId.rawValue,
            source: .medicineRow
        )
        let operationId = operationIdProvider.operationId(for: key, ttl: 3)
        do {
            try medicineActionUseCase.requestPrescription(
                medicineId: MedicineId(medicine.id),
                packageId: packageId,
                operationId: operationId
            )
            print("Log salvato: new_prescription_request per \(medicine.nome)")
            scheduleOperationClear(for: key)
        } catch {
            print("Errore requestPrescription: \(error)")
            operationIdProvider.clear(key)
        }
    }

    func addNewPrescription(for medicine: Medicine) {
        guard let packageId = resolvePackageId(for: medicine) else { return }
        let key = OperationKey.medicineAction(
            action: .prescriptionReceived,
            medicineId: medicine.id,
            packageId: packageId.rawValue,
            source: .medicineRow
        )
        let operationId = operationIdProvider.operationId(for: key, ttl: 3)
        do {
            try medicineActionUseCase.markPrescriptionReceived(
                medicineId: MedicineId(medicine.id),
                packageId: packageId,
                operationId: operationId
            )
            print("Log salvato: new_prescription per \(medicine.nome)")
            scheduleOperationClear(for: key)
        } catch {
            print("Errore markPrescriptionReceived: \(error)")
            operationIdProvider.clear(key)
        }
    }

    func addPurchase(for medicine: Medicine, package: Package? = nil) {
        guard let packageId = resolvePackageId(for: medicine, fallback: package) else { return }
        let key = OperationKey.medicineAction(
            action: .purchase,
            medicineId: medicine.id,
            packageId: packageId.rawValue,
            source: .medicineRow
        )
        let operationId = operationIdProvider.operationId(for: key, ttl: 3)
        do {
            try medicineActionUseCase.recordPurchase(
                medicineId: MedicineId(medicine.id),
                packageId: packageId,
                operationId: operationId
            )
            print("Log salvato: purchase per \(medicine.nome)")
            scheduleOperationClear(for: key)
        } catch {
            print("Errore recordPurchase: \(error)")
            operationIdProvider.clear(key)
        }
    }

    func addIntake(for medicine: Medicine, package: Package? = nil, therapy: Therapy? = nil) {
        guard let packageId = resolvePackageId(for: medicine, fallback: package, therapy: therapy) else { return }
        let key = OperationKey.medicineAction(
            action: .intake,
            medicineId: medicine.id,
            packageId: packageId.rawValue,
            source: .medicineRow
        )
        let operationId = operationIdProvider.operationId(for: key, ttl: 3)
        do {
            try medicineActionUseCase.recordIntake(
                medicineId: MedicineId(medicine.id),
                packageId: packageId,
                therapyId: therapy.map { TherapyId($0.id) },
                operationId: operationId
            )
            print("Log salvato: intake per \(medicine.nome)")
            scheduleOperationClear(for: key)
        } catch {
            print("Errore recordIntake: \(error)")
            operationIdProvider.clear(key)
        }
    }

    // Svuota tutte le scorte disponibili per la medicina, creando log di stock_adjustment
    func emptyStocks(for medicine: Medicine) {
        let stockService = StockService(context: managedObjectContext)
        // Caso con terapie: svuota per ogni therapy sulla base del suo package
        if let therapies = medicine.therapies, !therapies.isEmpty {
            for t in therapies {
                let left = Int(max(0, t.leftover()))
                guard left > 0 else { continue }
                for _ in 0..<left {
                    addLegacyLog(
                        for: medicine,
                        type: "stock_adjustment",
                        package: t.package,
                        operationId: operationIdProvider.newOperationId(),
                        stockService: stockService
                    )
                }
            }
            return
        }
        // Caso senza terapie: usa remainingUnitsWithoutTherapy
        if let remaining = medicine.remainingUnitsWithoutTherapy(), remaining > 0 {
            let pkg = (medicine.packages.first) ?? getLastPurchasedPackage(for: medicine)
            for _ in 0..<remaining {
                addLegacyLog(
                    for: medicine,
                    type: "stock_adjustment",
                    package: pkg,
                    operationId: operationIdProvider.newOperationId(),
                    stockService: stockService
                )
            }
        }
    }

    func prescriptionStatus(medicine: Medicine, currentOption: Option) -> String? {
        let snapshot = snapshotBuilder.makeMedicineSnapshot(
            medicine: medicine,
            logs: Array(medicine.logs ?? [])
        )
        let optionSnapshot = snapshotBuilder.makeOptionSnapshot(option: currentOption)
        guard snapshot.requiresPrescription else { return nil }
        let needsPrescription = sectionCalculator.needsPrescriptionBeforePurchase(snapshot, option: optionSnapshot)
        guard needsPrescription else { return nil }

        let hasPendingPrescription = snapshot.logs.contains { log in
            log.type == .prescriptionReceived &&
            log.reversalOfOperationId == nil &&
            !snapshot.logs.contains { undo in
                undo.type == .prescriptionReceivedUndo &&
                undo.reversalOfOperationId == log.operationId
            }
        }

        if hasPendingPrescription {
            return "Compra"
        } else {
            return "Richiedi ricetta"
        }
    }

    @ViewBuilder
    func actionButton(for status: String, medicine: Medicine) -> some View {
        switch status {
        case "Richiedi ricetta":
            Button(action: {
                self.addNewPrescriptionRequest(for: medicine)
            }) {
                Text("Richiedi ricetta")
            }
        case "Compra":
            Button(action: {
                self.addPurchase(for: medicine)
            }) {
                Text("Compra")
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Private

    private func resolvePackageId(for medicine: Medicine, fallback: Package? = nil, therapy: Therapy? = nil) -> PackageId? {
        if let fallback { return PackageId(fallback.id) }
        if let therapy { return PackageId(therapy.package.id) }
        if let lastPurchased = getLastPurchasedPackage(for: medicine) {
            return PackageId(lastPurchased.id)
        }
        if let first = medicine.packages.sorted(by: { $0.numero > $1.numero }).first {
            return PackageId(first.id)
        }
        return nil
    }

    private func getLastPurchasedPackage(for medicine: Medicine) -> Package? {
        let logs = medicine.effectivePurchaseLogs()
        return logs
            .sorted(by: { $0.timestamp > $1.timestamp })
            .first?.package
    }

    /// Legacy log creation for stock_adjustment (not yet in MedicineActionUseCase)
    private func addLegacyLog(
        for medicine: Medicine,
        type: String,
        package: Package?,
        operationId: UUID,
        stockService: StockService
    ) {
        _ = stockService.createLog(
            type: type,
            medicine: medicine,
            package: package,
            operationId: operationId,
            save: false
        )

        do {
            try CoreDataWriteCommand.saveIfNeeded(managedObjectContext)
        } catch {
            managedObjectContext.rollback()
            print("Errore nel salvataggio del log: \(error)")
        }
    }

    private func scheduleOperationClear(for key: OperationKey, delay: TimeInterval = 2.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.operationIdProvider.clear(key)
        }
    }
}
