import Foundation
import CoreData

final class CoreDataEventStore: EventStore {
    private let context: NSManagedObjectContext
    private let stockService: StockService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.stockService = StockService(context: context)
    }

    func exists(operationId: UUID) throws -> Bool {
        var result = false
        var capturedError: Error?
        context.performAndWait {
            do {
                result = try hasLog(operationId: operationId)
            } catch {
                capturedError = error
            }
        }
        if capturedError != nil {
            throw PharmaError(code: .saveFailed)
        }
        return result
    }

    func fetch(operationId: UUID) throws -> DomainEvent? {
        var result: DomainEvent?
        var capturedError: Error?
        context.performAndWait {
            let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
            request.fetchLimit = 1
            request.includesSubentities = false
            request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
            do {
                if let log = try context.fetch(request).first {
                    result = domainEvent(from: log)
                }
            } catch {
                capturedError = error
            }
        }
        if capturedError != nil {
            throw PharmaError(code: .saveFailed)
        }
        return result
    }

    func hasReversal(for operationId: UUID) throws -> Bool {
        var result = false
        var capturedError: Error?
        context.performAndWait {
            do {
                result = try hasReversalLog(for: operationId)
            } catch {
                capturedError = error
            }
        }
        if capturedError != nil {
            throw PharmaError(code: .saveFailed)
        }
        return result
    }

    func append(_ event: DomainEvent) throws {
        var capturedError: Error?
        context.performAndWait {
            do {
                if try hasLog(operationId: event.operationId) {
                    throw PharmaError(code: .duplicateOperation)
                }
                if let reversalId = event.reversalOfOperationId,
                   try hasReversalLog(for: reversalId) {
                    throw PharmaError(code: .duplicateOperation)
                }
                let medicine = try fetchMedicine(event.medicineId)
                let package = try fetchPackage(event.packageId)
                let therapy = try fetchTherapy(event.therapyId)
                let logType = try logType(for: event.type)
                var createError: Error?
                guard stockService.createLog(
                    type: logType,
                    medicine: medicine,
                    package: package,
                    therapy: therapy,
                    timestamp: event.timestamp,
                    operationId: event.operationId,
                    logId: event.id,
                    reversalOfOperationId: event.reversalOfOperationId,
                    errorHandler: { error in
                        createError = error
                    }
                ) != nil else {
                    if let createError, StockService.isConstraintError(createError) {
                        throw PharmaError(code: .duplicateOperation)
                    }
                    throw PharmaError(code: .saveFailed)
                }
            } catch {
                capturedError = error
            }
        }
        if let capturedError {
            if let error = capturedError as? PharmaError { throw error }
            throw PharmaError(code: .saveFailed)
        }
    }

    func fetchUnsyncedEvents(limit: Int) throws -> [DomainEvent] {
        guard limit > 0 else { return [] }
        var result: [DomainEvent] = []
        var capturedError: Error?
        context.performAndWait {
            let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
            request.fetchLimit = limit
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            request.predicate = NSPredicate(format: "synced_at == nil AND operation_id != nil")

            do {
                let logs = try context.fetch(request)
                result = logs.compactMap { domainEvent(from: $0) }
            } catch {
                capturedError = error
            }
        }
        if capturedError != nil {
            throw PharmaError(code: .saveFailed)
        }
        return result
    }

    private func logType(for eventType: EventType) throws -> String {
        switch eventType {
        case .intakeRecorded:
            return "intake"
        case .intakeUndone:
            return "intake_undo"
        case .purchaseRecorded:
            return "purchase"
        case .purchaseUndone:
            return "purchase_undo"
        case .prescriptionRequested:
            return "new_prescription_request"
        case .prescriptionRequestUndone:
            return "prescription_request_undo"
        case .prescriptionReceived:
            return "new_prescription"
        case .prescriptionReceivedUndone:
            return "prescription_received_undo"
        case .stockAdjusted:
            return "stock_adjustment"
        }
    }

    private func eventType(for logType: String) -> EventType? {
        switch logType {
        case "intake":
            return .intakeRecorded
        case "intake_undo":
            return .intakeUndone
        case "purchase":
            return .purchaseRecorded
        case "purchase_undo":
            return .purchaseUndone
        case "new_prescription_request":
            return .prescriptionRequested
        case "prescription_request_undo":
            return .prescriptionRequestUndone
        case "new_prescription":
            return .prescriptionReceived
        case "prescription_received_undo":
            return .prescriptionReceivedUndone
        case "stock_adjustment":
            return .stockAdjusted
        default:
            return nil
        }
    }

    private func domainEvent(from log: Log) -> DomainEvent? {
        guard let operationId = log.operation_id,
              let eventType = eventType(for: log.type) else {
            return nil
        }

        let medicineId = MedicineId(log.medicine.id)
        let therapyId = log.therapy.map { TherapyId($0.id) }
        let packageId = log.package.map { PackageId($0.id) }

        return DomainEvent(
            id: log.id,
            operationId: operationId,
            type: eventType,
            timestamp: log.timestamp,
            medicineId: medicineId,
            therapyId: therapyId,
            packageId: packageId,
            reversalOfOperationId: log.reversal_of_operation_id
        )
    }

    private func fetchMedicine(_ id: MedicineId) throws -> Medicine {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        if let medicine = try context.fetch(request).first {
            return medicine
        }
        throw PharmaError(code: .notFound)
    }

    private func fetchPackage(_ id: PackageId?) throws -> Package {
        guard let id else { throw PharmaError(code: .invalidInput) }
        let request: NSFetchRequest<Package> = Package.fetchRequest() as! NSFetchRequest<Package>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        if let package = try context.fetch(request).first {
            return package
        }
        throw PharmaError(code: .notFound)
    }

    private func fetchTherapy(_ id: TherapyId?) throws -> Therapy? {
        guard let id else { return nil }
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        if let therapy = try context.fetch(request).first {
            return therapy
        }
        throw PharmaError(code: .notFound)
    }

    private func hasLog(operationId: UUID) throws -> Bool {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
        return try context.fetch(request).first != nil
    }

    private func hasReversalLog(for operationId: UUID) throws -> Bool {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.fetchLimit = 1
        request.includesSubentities = false
        request.predicate = NSPredicate(format: "reversal_of_operation_id == %@", operationId as CVarArg)
        return try context.fetch(request).first != nil
    }
}
