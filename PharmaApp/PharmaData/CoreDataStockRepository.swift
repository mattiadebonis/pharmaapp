import Foundation
import CoreData

final class CoreDataStockRepository: StockRepository {
    private let context: NSManagedObjectContext
    private let stockService: StockService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.stockService = StockService(context: context)
    }

    func units(for packageId: PackageId) throws -> Int {
        guard let package = try fetchPackage(id: packageId) else { return 0 }
        return stockService.unitsReadOnly(for: package)
    }

    func applyDelta(_ delta: Int, for packageId: PackageId) throws -> Int {
        guard let package = try fetchPackage(id: packageId) else { return 0 }
        return stockService.apply(delta: delta, for: package)
    }

    func setUnits(_ units: Int, for packageId: PackageId) throws {
        guard let package = try fetchPackage(id: packageId) else { return }
        stockService.setUnits(units, for: package)
    }

    private func fetchPackage(id: PackageId) throws -> Package? {
        let request: NSFetchRequest<Package> = Package.fetchRequest() as! NSFetchRequest<Package>
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
