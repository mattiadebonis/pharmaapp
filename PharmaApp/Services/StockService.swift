import Foundation
import CoreData

final class StockService {
    static let defaultContextKey = "default"

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    private func inContext<T: NSManagedObject>(_ object: T) -> T {
        if object.managedObjectContext === context {
            return object
        }
        return context.object(with: object.objectID) as! T
    }

    private func inContextOptional<T: NSManagedObject>(_ object: T?) -> T? {
        guard let object else { return nil }
        return inContext(object)
    }

    func ensureStockEntries(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) {
        let medicine = inContext(medicine)
        let packages = medicine.packages
        guard !packages.isEmpty else { return }
        for package in packages {
            _ = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        }
    }

    func units(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) -> Int {
        let medicine = inContext(medicine)
        let packages = medicine.packages
        guard !packages.isEmpty else { return 0 }
        return packages.reduce(0) { total, package in
            total + units(for: package, contextKey: contextKey)
        }
    }

    func units(for package: Package, contextKey: String = StockService.defaultContextKey) -> Int {
        let package = inContext(package)
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        return Int(stock.stock_units)
    }

    func setUnits(_ units: Int, for package: Package, contextKey: String = StockService.defaultContextKey) {
        let package = inContext(package)
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        stock.stock_units = Int32(units)
        stock.updated_at = Date()
    }

    @discardableResult
    func apply(delta: Int, for package: Package, contextKey: String = StockService.defaultContextKey) -> Int {
        guard delta != 0 else { return 0 }
        let package = inContext(package)
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        let current = Int(stock.stock_units)
        let proposed = current + delta
        if proposed < 0 {
            stock.stock_units = 0
            stock.updated_at = Date()
            #if DEBUG
            print("⚠️ Stock clamp: \(package.objectID) -> 0 (delta \(delta), current \(current))")
            #endif
            return -current
        }
        stock.stock_units = Int32(proposed)
        stock.updated_at = Date()
        return delta
    }

    @discardableResult
    func createLog(
        type: String,
        medicine: Medicine,
        package: Package?,
        therapy: Therapy? = nil,
        timestamp: Date = Date(),
        operationId: UUID,
        logId: UUID = UUID(),
        reversalOfOperationId: UUID? = nil,
        contextKey: String = StockService.defaultContextKey,
        save: Bool = true,
        errorHandler: ((Error) -> Void)? = nil
    ) -> Log? {
        if let existing = existingLog(operationId: operationId) {
            return existing
        }
        let medicine = inContext(medicine)
        let package = inContextOptional(package)
        let therapy = inContextOptional(therapy)
        guard let newLog = makeLog() else {
            errorHandler?(NSError(domain: "StockService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Log entity description"]))
            return nil
        }
        newLog.id = logId
        newLog.operation_id = operationId
        newLog.reversal_of_operation_id = reversalOfOperationId
        newLog.synced_at = nil
        newLog.type = type
        newLog.timestamp = timestamp
        newLog.medicine = medicine
        newLog.package = package
        newLog.therapy = therapy
        let identity = UserIdentityProvider.shared
        newLog.actor_user_id = identity.userId
        newLog.actor_device_id = identity.deviceId
        newLog.source = "local"

        var delta = 0
        if let package {
            delta = applyLogDelta(type: type, package: package, contextKey: contextKey)
        }

        guard save else { return newLog }

        do {
            try context.save()
            return newLog
        } catch {
            errorHandler?(error)
            if delta != 0, let package {
                _ = apply(delta: -delta, for: package, contextKey: contextKey)
            }
            context.delete(newLog)
            print("Errore nel salvataggio log: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func undoLog(operationId: UUID, contextKey: String = StockService.defaultContextKey) -> Bool {
        guard let log = existingLog(operationId: operationId) else { return false }
        return undoLog(log, contextKey: contextKey)
    }

    @discardableResult
    func undoLog(_ log: Log, contextKey: String = StockService.defaultContextKey) -> Bool {
        guard let operationId = log.operation_id else { return false }
        if let reversalType = reversalType(for: log.type) {
            if existingReversal(for: operationId) != nil { return true }
            return createReversalLog(
                originalLog: log,
                reversalType: reversalType,
                operationId: UUID(),
                contextKey: contextKey
            ) != nil
        }
        return deleteLogAndRevertStock(log, contextKey: contextKey)
    }

    @discardableResult
    func applyLogDelta(type: String, package: Package, contextKey: String = StockService.defaultContextKey) -> Int {
        let package = inContext(package)
        let delta = Self.deltaUnits(for: type, package: package)
        guard delta != 0 else { return 0 }
        return apply(delta: delta, for: package, contextKey: contextKey)
    }

    static func deltaUnits(for type: String, package: Package) -> Int {
        switch type {
        case "purchase":
            return max(1, Int(package.numero))
        case "purchase_undo":
            return -max(1, Int(package.numero))
        case "stock_increment":
            return 1
        case "intake", "stock_adjustment":
            return -1
        case "intake_undo":
            return 1
        default:
            return 0
        }
    }

    private func stock(for package: Package, contextKey: String, bootstrapFromLogs: Bool) -> Stock {
        let package = inContext(package)
        if let existing = stockFromRelationship(for: package, contextKey: contextKey) {
            return existing
        }
        if let fetched = fetchStock(for: package, contextKey: contextKey) {
            return fetched
        }
        let stock = makeStock()
        stock.id = UUID()
        stock.source_id = stock.id
        stock.context_key = contextKey
        stock.package = package
        stock.medicine = package.medicine
        stock.updated_at = Date()
        stock.visibility = "local"
        if bootstrapFromLogs && contextKey == StockService.defaultContextKey {
            stock.stock_units = Int32(unitsFromLogs(medicine: package.medicine, package: package))
        } else {
            stock.stock_units = 0
        }
        return stock
    }

    private func fetchStock(for package: Package, contextKey: String) -> Stock? {
        let request = Stock.fetchRequest(package: package, contextKey: contextKey)
        do {
            return try context.fetch(request).first
        } catch {
            print("Errore nel fetch stock: \(error.localizedDescription)")
            return nil
        }
    }

    private func stockFromRelationship(for package: Package, contextKey: String) -> Stock? {
        guard let stocks = package.stocks else { return nil }
        return stocks.first(where: { $0.context_key == contextKey })
    }

    func rebuildStock(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) {
        let packages = medicine.packages
        guard !packages.isEmpty else { return }
        let now = Date()
        for package in packages {
            let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: false)
            let units = unitsFromLogs(medicine: medicine, package: package)
            stock.stock_units = Int32(max(0, units))
            stock.updated_at = now
        }
    }

    #if DEBUG
    func debugCheckStockConsistency(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) -> Bool {
        let packages = medicine.packages
        guard !packages.isEmpty else { return true }
        for package in packages {
            let expected = unitsFromLogs(medicine: medicine, package: package)
            let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: false)
            if Int(stock.stock_units) != expected {
                return false
            }
        }
        return true
    }
    #endif

    private func existingLog(operationId: UUID) -> Log? {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
        do {
            return try context.fetch(request).first
        } catch {
            print("Errore nel fetch log: \(error.localizedDescription)")
            return nil
        }
    }

    private func unitsFromLogs(medicine: Medicine, package: Package) -> Int {
        let logs = medicine.logs ?? []
        let packSize = max(1, Int(package.numero))
        let matchesPackage: (Log) -> Bool = { log in
            if let pkg = log.package { return pkg.objectID == package.objectID }
            return medicine.packages.count == 1
        }
        let purchases = logs.filter { $0.type == "purchase" && matchesPackage($0) }.count
        let purchaseUndo = logs.filter { $0.type == "purchase_undo" && matchesPackage($0) }.count
        let increments = logs.filter {
            ($0.type == "stock_increment" || $0.type == "intake_undo") && matchesPackage($0)
        }.count
        let decrements = logs.filter {
            ($0.type == "intake" || $0.type == "stock_adjustment") && matchesPackage($0)
        }.count
        return purchases * packSize + increments - decrements - (purchaseUndo * packSize)
    }

    private func reversalType(for type: String) -> String? {
        switch type {
        case "intake":
            return "intake_undo"
        case "purchase":
            return "purchase_undo"
        case "new_prescription_request":
            return "prescription_request_undo"
        case "new_prescription":
            return "prescription_received_undo"
        default:
            return nil
        }
    }

    private func existingReversal(for operationId: UUID) -> Log? {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "reversal_of_operation_id == %@", operationId as CVarArg)
        do {
            return try context.fetch(request).first
        } catch {
            print("Errore nel fetch undo log: \(error.localizedDescription)")
            return nil
        }
    }

    private func createReversalLog(
        originalLog: Log,
        reversalType: String,
        operationId: UUID,
        contextKey: String
    ) -> Log? {
        guard let package = originalLog.package else { return nil }

        guard let newLog = makeLog() else { return nil }
        newLog.id = UUID()
        newLog.operation_id = operationId
        newLog.reversal_of_operation_id = originalLog.operation_id
        newLog.synced_at = nil
        newLog.type = reversalType
        newLog.timestamp = Date()
        newLog.medicine = originalLog.medicine
        newLog.package = package
        newLog.therapy = originalLog.therapy

        let delta = applyLogDelta(type: reversalType, package: package, contextKey: contextKey)

        do {
            try context.save()
            return newLog
        } catch {
            if delta != 0 {
                apply(delta: -delta, for: package, contextKey: contextKey)
            }
            context.delete(newLog)
            print("Errore nel salvataggio undo log: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeLog() -> Log? {
        guard let entity = NSEntityDescription.entity(forEntityName: "Log", in: context) else { return nil }
        return Log(entity: entity, insertInto: context)
    }

    private func makeStock() -> Stock {
        guard let entity = NSEntityDescription.entity(forEntityName: "Stock", in: context) else {
            fatalError("Missing Stock entity description")
        }
        return Stock(entity: entity, insertInto: context)
    }

    private func deleteLogAndRevertStock(_ log: Log, contextKey: String) -> Bool {
        let appliedDelta: Int
        if let package = log.package {
            let delta = Self.deltaUnits(for: log.type, package: package)
            if delta != 0 {
                appliedDelta = apply(delta: -delta, for: package, contextKey: contextKey)
            } else {
                appliedDelta = 0
            }
        } else {
            appliedDelta = 0
        }

        context.delete(log)

        do {
            try context.save()
            return true
        } catch {
            if appliedDelta != 0, let package = log.package {
                _ = apply(delta: -appliedDelta, for: package, contextKey: contextKey)
            }
            context.rollback()
            print("Errore nel salvataggio undo log: \(error.localizedDescription)")
            return false
        }
    }
}

extension StockService {
    static func isConstraintError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSManagedObjectConstraintValidationError {
                return true
            }
            if nsError.code == NSValidationMultipleErrorsError,
               let detailed = nsError.userInfo[NSDetailedErrorsKey] as? [NSError] {
                return detailed.contains { $0.code == NSManagedObjectConstraintValidationError }
            }
        }
        return false
    }
}
