//
//  Persistence.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    @MainActor
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "PharmaApp")

        let storeURL = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : Self.storeURL(filename: "PharmaApp.shared.sqlite")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "local"
        Self.repairTherapiesWithoutPerson(in: container.viewContext)
    }

    private static func storeURL(filename: String) -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(filename)
    }

    private static func repairTherapiesWithoutPerson(in context: NSManagedObjectContext) {
        context.performAndWait {
            let therapyRequest = Therapy.extractTherapies()
            therapyRequest.predicate = NSPredicate(format: "person == nil")
            let orphanTherapies = (try? context.fetch(therapyRequest)) ?? []
            guard !orphanTherapies.isEmpty else { return }

            let accountRequest = Person.fetchAccountPerson()
            accountRequest.predicate = NSPredicate(format: "is_account == YES")
            let account = (try? context.fetch(accountRequest).first) ?? {
                let person = Person(context: context)
                person.id = UUID()
                person.nome = "Account"
                person.is_account = true
                return person
            }()

            for therapy in orphanTherapies {
                therapy.person = account
            }

            guard context.hasChanges else { return }
            do {
                try context.save()
            } catch {
                context.rollback()
                print("Repair therapies without person failed: \(error.localizedDescription)")
            }
        }
    }
} 
