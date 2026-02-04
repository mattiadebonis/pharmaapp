import Foundation
import CoreData

@available(*, deprecated, message: "Use TodayStateBuilder.")
protocol TodoBuilderProtocol {
    func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem]
}

@available(*, deprecated, message: "Use TodayStateBuilder.")
struct TodoBuilderService: TodoBuilderProtocol {
    func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem] {
        []
    }
}
