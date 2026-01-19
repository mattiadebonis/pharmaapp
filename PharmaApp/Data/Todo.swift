//
//  Todo.swift
//  PharmaApp
//
//  Created by Cursor on 19/01/26.
//

import Foundation
import CoreData

@objc(Todo)
public class Todo: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var source_id: String
    @NSManaged public var title: String
    @NSManaged public var detail: String?
    @NSManaged public var category: String
    @NSManaged public var created_at: Date
    @NSManaged public var updated_at: Date
    @NSManaged public var due_at: Date?
    @NSManaged public var medicine: Medicine?
}

extension Todo {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Todo> {
        NSFetchRequest<Todo>(entityName: "Todo")
    }

    static func extractTodos() -> NSFetchRequest<Todo> {
        let request: NSFetchRequest<Todo> = Todo.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        return request
    }
}
