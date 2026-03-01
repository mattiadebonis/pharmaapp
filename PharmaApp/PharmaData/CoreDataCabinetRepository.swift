import Foundation
import CoreData

final class CoreDataCabinetRepository: CabinetRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() throws -> [CabinetSnapshot] {
        let request: NSFetchRequest<Cabinet> = Cabinet.extractCabinets()
        let cabinets = try context.fetch(request)
        return cabinets.map { cabinet in
            CabinetSnapshot(
                id: cabinet.id,
                name: cabinet.name,
                isShared: cabinet.is_shared
            )
        }
    }
}
