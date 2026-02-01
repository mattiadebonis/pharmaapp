import CoreData

/// Centralized stock mutations used by medicine flows.
struct MedicineStockService {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func addPurchase(medicine: Medicine, package: Package) {
        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID(),
            save: false
        )

        do {
            try context.save()
        } catch {
            context.rollback()
            print("Error saving purchase log: \(error.localizedDescription)")
        }
    }

    func setStockUnits(medicine: Medicine, package: Package, targetUnits: Int) {
        let stockService = StockService(context: context)
        let currentUnits = max(0, stockService.units(for: package))
        let desiredUnits = max(0, targetUnits)
        let delta = desiredUnits - currentUnits

        guard delta != 0 else { return }

        let packSize = max(1, Int(package.numero))

        if delta > 0 {
            let fullPackages = delta / packSize
            let remainingUnits = delta % packSize

            for _ in 0..<fullPackages {
                _ = stockService.createLog(
                    type: "purchase",
                    medicine: medicine,
                    package: package,
                    operationId: UUID(),
                    save: false
                )
            }

            if remainingUnits > 0 {
                for _ in 0..<remainingUnits {
                    _ = stockService.createLog(
                        type: "stock_increment",
                        medicine: medicine,
                        package: package,
                        operationId: UUID(),
                        save: false
                    )
                }
            }
        } else {
            for _ in 0..<abs(delta) {
                _ = stockService.createLog(
                    type: "stock_adjustment",
                    medicine: medicine,
                    package: package,
                    operationId: UUID(),
                    save: false
                )
            }
        }

        stockService.setUnits(desiredUnits, for: package)

        do {
            try context.save()
        } catch {
            context.rollback()
            print("Error updating stock units: \(error.localizedDescription)")
        }
    }
}
