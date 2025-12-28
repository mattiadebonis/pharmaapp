import Foundation
import CoreData

protocol TodoBuilderProtocol {
    func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem]
}

/// Adapter che riusa l'implementazione esistente TodayTodoBuilder.
struct TodoBuilderService: TodoBuilderProtocol {
    func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem] {
        TodayTodoBuilder.makeTodos(from: context, medicines: medicines, urgentIDs: urgentIDs)
    }
}
