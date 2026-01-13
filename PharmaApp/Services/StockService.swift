import Foundation
import CoreData

final class StockService {
    static let defaultContextKey = "default"

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func ensureStockEntries(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) {
        let packages = medicine.packages
        guard !packages.isEmpty else { return }
        for package in packages {
            _ = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        }
    }

    func units(for medicine: Medicine, contextKey: String = StockService.defaultContextKey) -> Int {
        let packages = medicine.packages
        guard !packages.isEmpty else { return 0 }
        return packages.reduce(0) { total, package in
            total + units(for: package, contextKey: contextKey)
        }
    }

    func units(for package: Package, contextKey: String = StockService.defaultContextKey) -> Int {
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        return Int(stock.stock_units)
    }

    func setUnits(_ units: Int, for package: Package, contextKey: String = StockService.defaultContextKey) {
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        stock.stock_units = Int32(units)
        stock.updated_at = Date()
    }

    func apply(delta: Int, for package: Package, contextKey: String = StockService.defaultContextKey) {
        guard delta != 0 else { return }
        let stock = stock(for: package, contextKey: contextKey, bootstrapFromLogs: true)
        stock.stock_units += Int32(delta)
        stock.updated_at = Date()
    }

    @discardableResult
    func createLog(
        type: String,
        medicine: Medicine,
        package: Package?,
        therapy: Therapy? = nil,
        timestamp: Date = Date(),
        contextKey: String = StockService.defaultContextKey,
        save: Bool = true
    ) -> Log? {
        let newLog = Log(context: context)
        newLog.id = UUID()
        newLog.type = type
        newLog.timestamp = timestamp
        newLog.medicine = medicine
        newLog.package = package
        newLog.therapy = therapy

        var delta = 0
        if let package {
            delta = applyLogDelta(type: type, package: package, contextKey: contextKey)
        }

        guard save else { return newLog }

        do {
            try context.save()
            return newLog
        } catch {
            if delta != 0, let package {
                apply(delta: -delta, for: package, contextKey: contextKey)
            }
            context.delete(newLog)
            print("Errore nel salvataggio log: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func applyLogDelta(type: String, package: Package, contextKey: String = StockService.defaultContextKey) -> Int {
        let delta = Self.deltaUnits(for: type, package: package)
        guard delta != 0 else { return 0 }
        apply(delta: delta, for: package, contextKey: contextKey)
        return delta
    }

    static func deltaUnits(for type: String, package: Package) -> Int {
        switch type {
        case "purchase":
            return max(1, Int(package.numero))
        case "stock_increment":
            return 1
        case "intake", "stock_adjustment":
            return -1
        default:
            return 0
        }
    }

    private func stock(for package: Package, contextKey: String, bootstrapFromLogs: Bool) -> Stock {
        if let existing = stockFromRelationship(for: package, contextKey: contextKey) {
            return existing
        }
        if let fetched = fetchStock(for: package, contextKey: contextKey) {
            return fetched
        }
        let stock = Stock(context: context)
        stock.id = UUID()
        stock.context_key = contextKey
        stock.package = package
        stock.medicine = package.medicine
        stock.updated_at = Date()
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

    private func unitsFromLogs(medicine: Medicine, package: Package) -> Int {
        let logs = medicine.logs ?? []
        let packSize = max(1, Int(package.numero))
        let matchesPackage: (Log) -> Bool = { log in
            if let pkg = log.package { return pkg.objectID == package.objectID }
            return medicine.packages.count == 1
        }
        let purchases = logs.filter { $0.type == "purchase" && matchesPackage($0) }.count
        let increments = logs.filter { $0.type == "stock_increment" && matchesPackage($0) }.count
        let decrements = logs.filter {
            ($0.type == "intake" || $0.type == "stock_adjustment") && matchesPackage($0)
        }.count
        return purchases * packSize + increments - decrements
    }
}
