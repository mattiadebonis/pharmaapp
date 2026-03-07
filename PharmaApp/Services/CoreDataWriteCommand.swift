import CoreData

enum CoreDataWriteCommand {
    static func saveIfNeeded(_ context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    static func saveOrRollback(_ context: NSManagedObjectContext) throws {
        do {
            try saveIfNeeded(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}
