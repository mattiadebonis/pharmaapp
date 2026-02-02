import CoreData

/// Centralized stock mutations used by medicine flows.
struct MedicineStockService {
    private let context: NSManagedObjectContext
    private let operationIdProvider: OperationIdProviding

    init(
        context: NSManagedObjectContext,
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared
    ) {
        self.context = context
        self.operationIdProvider = operationIdProvider
    }

    func addPurchase(medicine: Medicine, package: Package) {
        let stockService = StockService(context: context)
        let token = purchaseOperationToken(medicine: medicine, package: package)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: token.id,
            save: false
        )

        do {
            try context.save()
            scheduleOperationClear(for: token.key)
        } catch {
            context.rollback()
            print("Error saving purchase log: \(error.localizedDescription)")
            operationIdProvider.clear(token.key)
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
                    operationId: operationIdProvider.newOperationId(),
                    save: false
                )
            }

            if remainingUnits > 0 {
                for _ in 0..<remainingUnits {
                    _ = stockService.createLog(
                        type: "stock_increment",
                        medicine: medicine,
                        package: package,
                        operationId: operationIdProvider.newOperationId(),
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
                    operationId: operationIdProvider.newOperationId(),
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

    private func purchaseOperationToken(medicine: Medicine, package: Package) -> (id: UUID, key: OperationKey) {
        let key = OperationKey.medicineAction(
            action: .purchase,
            medicineId: medicine.id,
            packageId: package.id,
            source: .unknown
        )
        let id = operationIdProvider.operationId(for: key, ttl: 3)
        return (id, key)
    }

    private func scheduleOperationClear(for key: OperationKey, delay: TimeInterval = 2.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.operationIdProvider.clear(key)
        }
    }
}
