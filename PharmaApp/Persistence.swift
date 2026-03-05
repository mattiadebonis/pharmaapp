//
//  Persistence.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import Foundation
import CoreData

extension Notification.Name {
    static let persistenceStoreDidRestore = Notification.Name("PersistenceController.persistenceStoreDidRestore")
}

final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let modelName: String
    let storeURL: URL

    init(
        inMemory: Bool = false,
        modelName: String = "PharmaApp",
        storeURL: URL? = nil
    ) {
        self.modelName = modelName
        self.storeURL = inMemory
            ? URL(fileURLWithPath: "/dev/null")
            : storeURL ?? Self.defaultStoreURL(filename: "PharmaApp.shared.sqlite")
        self.container = NSPersistentContainer(
            name: modelName,
            managedObjectModel: Self.resolveManagedObjectModel(named: modelName)
        )
        self.container.persistentStoreDescriptions = [Self.makeStoreDescription(url: self.storeURL)]

        self.container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        Self.configureViewContext(self.container.viewContext)
        Self.repairTherapiesWithoutPerson(in: self.container.viewContext)
    }

    var activeStoreURL: URL {
        storeURL
    }

    func saveViewContextIfNeeded() throws {
        var capturedError: Error?
        container.viewContext.performAndWait {
            guard container.viewContext.hasChanges else { return }
            do {
                try container.viewContext.save()
            } catch {
                container.viewContext.rollback()
                capturedError = error
            }
        }
        if let capturedError {
            throw capturedError
        }
    }

    func entityCounts() throws -> [String: Int] {
        let context = container.viewContext
        var counts: [String: Int] = [:]
        var capturedError: Error?

        context.performAndWait {
            for entity in context.persistentStoreCoordinator?.managedObjectModel.entities ?? [] {
                guard let entityName = entity.name else { continue }
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                do {
                    counts[entityName] = try context.count(for: request)
                } catch {
                    capturedError = error
                    return
                }
            }
        }

        if let capturedError {
            throw capturedError
        }
        return counts
    }

    func copyStorePackage(to packageURL: URL) throws -> [String] {
        try saveViewContextIfNeeded()

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        var copiedFiles: [String] = []
        for fileURL in storeFileURLs() {
            let destinationURL = packageURL.appendingPathComponent(fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
            copiedFiles.append(fileURL.lastPathComponent)
        }
        return copiedFiles.sorted()
    }

    func replaceStore(with packageURL: URL) throws {
        try saveViewContextIfNeeded()

        let fileManager = FileManager.default
        let coordinator = container.persistentStoreCoordinator
        let context = container.viewContext

        context.performAndWait {
            context.reset()
        }

        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }

        try removeStoreFiles()

        let packageFiles = try fileManager.contentsOfDirectory(
            at: packageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let sqliteFileName = storeURL.lastPathComponent
        guard packageFiles.contains(where: { $0.lastPathComponent == sqliteFileName }) else {
            throw NSError(
                domain: "PersistenceController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Snapshot Core Data incompleta: sqlite principale non trovata."]
            )
        }

        for fileURL in packageFiles where fileURL.lastPathComponent != "manifest.json" {
            let destinationURL = storeDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        }

        _ = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: Self.storeOptions()
        )

        Self.configureViewContext(context)
        Self.repairTherapiesWithoutPerson(in: context)
        NotificationCenter.default.post(name: .persistenceStoreDidRestore, object: self)
    }

    private var storeDirectoryURL: URL {
        storeURL.deletingLastPathComponent()
    }

    private func storeFileURLs() -> [URL] {
        let candidates = [
            storeURL,
            storeDirectoryURL.appendingPathComponent("\(storeURL.lastPathComponent)-wal"),
            storeDirectoryURL.appendingPathComponent("\(storeURL.lastPathComponent)-shm")
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func removeStoreFiles() throws {
        for fileURL in storeFileURLs() {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func defaultStoreURL(filename: String) -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(filename)
    }

    private static func resolveManagedObjectModel(named modelName: String) -> NSManagedObjectModel {
        let candidateBundles = [
            Bundle(for: Medicine.self),
            Bundle.main
        ]

        for bundle in candidateBundles {
            if let modelURL = bundle.url(forResource: modelName, withExtension: "momd"),
               let model = NSManagedObjectModel(contentsOf: modelURL) {
                return model
            }
        }

        for bundle in candidateBundles {
            if let mergedModel = NSManagedObjectModel.mergedModel(from: [bundle]),
               !mergedModel.entities.isEmpty {
                return mergedModel
            }
        }

        fatalError("Unable to load Core Data model named \(modelName)")
    }

    private static func makeStoreDescription(url: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    private static func storeOptions() -> [AnyHashable: Any] {
        [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSPersistentHistoryTrackingKey: true,
            NSPersistentStoreRemoteChangeNotificationPostOptionKey: true
        ]
    }

    private static func configureViewContext(_ context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "local"
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
