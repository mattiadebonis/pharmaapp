import Foundation
import CoreData

struct CoreDataSnapshotBuilder {
    private let context: NSManagedObjectContext
    private let stockService: StockService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.stockService = StockService(context: context)
    }

    func makeInput(
        medicines: [Medicine],
        logs: [Log],
        option: Option?,
        completedTodoIDs: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) -> TherapyPlanInput {
        let medicineSnapshots = makeMedicineSnapshots(medicines: medicines, logs: logs)
        let optionSnapshot = makeOptionSnapshot(option: option)
        return TherapyPlanInput(
            medicines: medicineSnapshots,
            todos: [],
            option: optionSnapshot,
            completedTodoIDs: completedTodoIDs,
            now: now,
            calendar: calendar
        )
    }

    func makeMedicineSnapshots(medicines: [Medicine], logs: [Log]) -> [MedicineSnapshot] {
        let logsByMedicine: [NSManagedObjectID: [Log]] = {
            guard !logs.isEmpty else { return [:] }
            return Dictionary(grouping: logs, by: { $0.medicine.objectID })
        }()

        return medicines.map { medicine in
            let logsForMedicine: [Log] = {
                if logsByMedicine.isEmpty {
                    return Array(medicine.logs ?? [])
                }
                return logsByMedicine[medicine.objectID] ?? []
            }()
            return makeMedicineSnapshot(medicine: medicine, logs: logsForMedicine)
        }
    }

    func makeMedicineSnapshot(medicine: Medicine, logs: [Log]) -> MedicineSnapshot {
        let therapySnapshots = (medicine.therapies ?? []).map { therapy in
            makeTherapySnapshot(therapy: therapy)
        }
        let logEntries = logs.compactMap { logEntry(from: $0) }
        let deadlineMonth = medicine.deadlineMonthYear?.month
        let deadlineYear = medicine.deadlineMonthYear?.year
        let stockUnits = stockService.unitsReadOnly(for: medicine)
        return MedicineSnapshot(
            id: MedicineId(medicine.id),
            externalKey: medicine.objectID.uriRepresentation().absoluteString,
            name: medicine.nome,
            requiresPrescription: medicine.obbligo_ricetta,
            inCabinet: medicine.in_cabinet,
            manualIntakeRegistration: medicine.manual_intake_registration,
            hasPackages: !medicine.packages.isEmpty,
            hasMedicinePackages: !(medicine.medicinePackages?.isEmpty ?? true),
            deadlineMonth: deadlineMonth,
            deadlineYear: deadlineYear,
            stockUnitsWithoutTherapy: stockUnits,
            therapies: therapySnapshots,
            logs: logEntries
        )
    }

    func makeTherapySnapshot(therapy: Therapy) -> TherapySnapshot {
        let doses: [DoseSnapshot] = (therapy.doses ?? []).map { dose in
            DoseSnapshot(time: dose.time, amount: dose.amountValue)
        }
        let personName = (therapy.person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = personName.isEmpty ? nil : personName
        let leftover = stockService.unitsReadOnly(for: therapy.package)
        return TherapySnapshot(
            id: TherapyId(therapy.id),
            externalKey: therapy.objectID.uriRepresentation().absoluteString,
            medicineId: MedicineId(therapy.medicine.id),
            packageId: PackageId(therapy.package.id),
            packageKey: therapy.package.objectID.uriRepresentation().absoluteString,
            startDate: therapy.start_date,
            rrule: therapy.rrule,
            doses: doses,
            leftoverUnits: leftover,
            manualIntakeRegistration: therapy.manual_intake_registration,
            clinicalRules: therapy.clinicalRulesValue,
            personName: resolvedName
        )
    }

    /// Creates a MedicineSnapshot scoped to a specific MedicinePackage entry.
    /// Only includes therapies relevant to the entry's package, and stock units for that package.
    func makeEntrySnapshot(entry: MedicinePackage) -> MedicineSnapshot {
        let medicine = entry.medicine
        let package = entry.package

        // Resolve therapies for this entry
        let entryTherapies: [Therapy]
        if let set = entry.therapies, !set.isEmpty {
            entryTherapies = Array(set)
        } else {
            let all = medicine.therapies ?? []
            entryTherapies = all.filter { $0.package == package }
        }

        let therapySnapshots = entryTherapies.map { makeTherapySnapshot(therapy: $0) }
        let logEntries = (medicine.logs ?? []).compactMap { logEntry(from: $0) }
        let deadlineMonth = entry.deadline_month > 0 ? Int(entry.deadline_month) : nil
        let deadlineYear = entry.deadline_year > 0 ? Int(entry.deadline_year) : nil

        // Stock for this specific package (not whole medicine)
        let packageStock: Int?
        if entryTherapies.isEmpty {
            packageStock = stockService.unitsReadOnly(for: package)
        } else {
            packageStock = nil
        }

        return MedicineSnapshot(
            id: MedicineId(medicine.id),
            externalKey: entry.objectID.uriRepresentation().absoluteString,
            name: medicine.nome,
            requiresPrescription: medicine.obbligo_ricetta,
            inCabinet: medicine.in_cabinet,
            manualIntakeRegistration: medicine.manual_intake_registration,
            hasPackages: !medicine.packages.isEmpty,
            hasMedicinePackages: !(medicine.medicinePackages?.isEmpty ?? true),
            deadlineMonth: deadlineMonth,
            deadlineYear: deadlineYear,
            stockUnitsWithoutTherapy: packageStock,
            therapies: therapySnapshots,
            logs: logEntries
        )
    }

    func makeOptionSnapshot(option: Option?) -> OptionSnapshot? {
        guard let option else { return nil }
        return OptionSnapshot(
            manualIntakeRegistration: option.manual_intake_registration,
            dayThresholdStocksAlarm: Int(option.day_threeshold_stocks_alarm)
        )
    }

    private func logEntry(from log: Log) -> LogEntry? {
        guard let type = logType(from: log.type) else { return nil }
        return LogEntry(
            type: type,
            timestamp: log.timestamp,
            scheduledDueAt: log.scheduled_due_at,
            operationId: log.operation_id,
            reversalOfOperationId: log.reversal_of_operation_id,
            therapyId: log.therapy.map { TherapyId($0.id) },
            packageId: log.package.map { PackageId($0.id) }
        )
    }

    private func logType(from raw: String) -> LogType? {
        switch raw {
        case "intake":
            return .intake
        case "intake_undo":
            return .intakeUndo
        case "purchase":
            return .purchase
        case "purchase_undo":
            return .purchaseUndo
        case "new_prescription_request":
            return .prescriptionRequest
        case "prescription_request_undo":
            return .prescriptionRequestUndo
        case "new_prescription":
            return .prescriptionReceived
        case "prescription_received_undo":
            return .prescriptionReceivedUndo
        case "stock_adjustment":
            return .stockAdjustment
        default:
            return nil
        }
    }
}
