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
    }

    private static func storeURL(filename: String) -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(filename)
    }
}
