import Foundation
import CoreData

final class CoreDataOptionRepository: OptionRepository {
    private let context: NSManagedObjectContext
    private let snapshotBuilder: CoreDataSnapshotBuilder

    init(context: NSManagedObjectContext) {
        self.context = context
        self.snapshotBuilder = CoreDataSnapshotBuilder(context: context)
    }

    func fetchCurrentOption() throws -> OptionSnapshot? {
        let request: NSFetchRequest<Option> = Option.fetchRequest() as! NSFetchRequest<Option>
        request.fetchLimit = 1
        guard let option = try context.fetch(request).first else { return nil }
        return snapshotBuilder.makeOptionSnapshot(option: option)
    }
}
