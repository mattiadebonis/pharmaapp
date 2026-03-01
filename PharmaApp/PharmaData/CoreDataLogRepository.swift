import Foundation
import CoreData

final class CoreDataLogRepository: LogRepository {
    private let context: NSManagedObjectContext
    private let stockService: StockService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.stockService = StockService(context: context)
    }

    func fetchLogs(for medicineId: MedicineId) throws -> [LogEntry] {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "medicine.id == %@", medicineId.rawValue as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        let logs = try context.fetch(request)
        return logs.compactMap { logEntry(from: $0) }
    }

    func fetchIntakeLogs(for medicineId: MedicineId, on date: Date) throws -> [LogEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "medicine.id == %@", medicineId.rawValue as CVarArg),
            NSPredicate(format: "type == %@", "intake"),
            NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay as NSDate, endOfDay as NSDate)
        ])
        let logs = try context.fetch(request)
        return logs.compactMap { logEntry(from: $0) }
    }

    func createLog(_ request: CreateLogRequest) throws -> UUID {
        let logTypeString = logTypeToString(request.type)

        // Find medicine and package CoreData objects
        let medicineRequest: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        medicineRequest.predicate = NSPredicate(format: "id == %@", request.medicineId.rawValue as CVarArg)
        medicineRequest.fetchLimit = 1
        guard let medicine = try context.fetch(medicineRequest).first else {
            throw PharmaError(code: .notFound, message: "Medicine not found")
        }

        var package: Package? = nil
        if let packageId = request.packageId {
            let packageRequest: NSFetchRequest<Package> = Package.fetchRequest() as! NSFetchRequest<Package>
            packageRequest.predicate = NSPredicate(format: "id == %@", packageId.rawValue as CVarArg)
            packageRequest.fetchLimit = 1
            package = try context.fetch(packageRequest).first
        }

        var therapy: Therapy? = nil
        if let therapyId = request.therapyId {
            let therapyRequest: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
            therapyRequest.predicate = NSPredicate(format: "id == %@", therapyId.rawValue as CVarArg)
            therapyRequest.fetchLimit = 1
            therapy = try context.fetch(therapyRequest).first
        }

        guard let log = stockService.createLog(
            type: logTypeString,
            medicine: medicine,
            package: package,
            therapy: therapy,
            timestamp: request.timestamp,
            scheduledDueAt: request.scheduledDueAt,
            operationId: request.operationId
        ) else {
            throw PharmaError(code: .saveFailed, message: "Failed to create log")
        }

        return log.id
    }

    func undoLog(operationId: UUID) throws -> Bool {
        stockService.undoLog(operationId: operationId)
    }

    // MARK: - Helpers

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
        case "intake": return .intake
        case "intake_undo": return .intakeUndo
        case "purchase": return .purchase
        case "purchase_undo": return .purchaseUndo
        case "new_prescription_request": return .prescriptionRequest
        case "prescription_request_undo": return .prescriptionRequestUndo
        case "new_prescription": return .prescriptionReceived
        case "prescription_received_undo": return .prescriptionReceivedUndo
        case "stock_adjustment": return .stockAdjustment
        default: return nil
        }
    }

    private func logTypeToString(_ type: LogType) -> String {
        switch type {
        case .intake: return "intake"
        case .intakeUndo: return "intake_undo"
        case .purchase: return "purchase"
        case .purchaseUndo: return "purchase_undo"
        case .prescriptionRequest: return "new_prescription_request"
        case .prescriptionRequestUndo: return "prescription_request_undo"
        case .prescriptionReceived: return "new_prescription"
        case .prescriptionReceivedUndo: return "prescription_received_undo"
        case .stockAdjustment: return "stock_adjustment"
        }
    }
}
