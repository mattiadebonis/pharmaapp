import CoreData
import Foundation

@MainActor
final class PersonDeletionService {
    static let shared = PersonDeletionService()

    enum DeletionError: LocalizedError {
        case cannotDeleteAccountPerson
        case personNotFound

        var errorDescription: String? {
            switch self {
            case .cannotDeleteAccountPerson:
                return "La persona account non può essere eliminata."
            case .personNotFound:
                return "La persona non è più disponibile."
            }
        }
    }

    private init() {}

    func delete(_ person: Person, in context: NSManagedObjectContext) throws {
        guard !person.is_account else {
            throw DeletionError.cannotDeleteAccountPerson
        }

        let personToDelete: Person
        if person.managedObjectContext === context {
            personToDelete = person
        } else {
            guard let resolvedObject = try? context.existingObject(with: person.objectID),
                  let resolved = resolvedObject as? Person else {
                throw DeletionError.personNotFound
            }
            personToDelete = resolved
        }

        let accountPerson = AccountPersonService.shared.ensureAccountPerson(in: context)
        guard accountPerson.objectID != personToDelete.objectID else {
            throw DeletionError.cannotDeleteAccountPerson
        }

        let therapyRequest = Therapy.extractTherapies()
        therapyRequest.predicate = NSPredicate(format: "person == %@", personToDelete)
        let relatedTherapies = try context.fetch(therapyRequest)
        for therapy in relatedTherapies {
            therapy.person = accountPerson
        }

        context.delete(personToDelete)
        if context.hasChanges {
            try context.save()
        }
    }
}
