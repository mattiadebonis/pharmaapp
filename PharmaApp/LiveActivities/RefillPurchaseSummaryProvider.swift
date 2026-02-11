import Foundation
import CoreData

struct RefillPurchaseSummary: Equatable {
    let allNames: [String]
    let maxVisible: Int

    var visibleNames: [String] {
        Array(allNames.prefix(maxVisible))
    }

    var totalCount: Int {
        allNames.count
    }

    var remainingCount: Int {
        max(0, totalCount - visibleNames.count)
    }

    var hasItems: Bool {
        !allNames.isEmpty
    }
}

@MainActor
final class RefillPurchaseSummaryProvider {
    private let context: NSManagedObjectContext
    private let stateProvider: CoreDataTodayStateProvider

    init(
        context: NSManagedObjectContext,
        stateProvider: CoreDataTodayStateProvider? = nil
    ) {
        self.context = context
        self.stateProvider = stateProvider ?? CoreDataTodayStateProvider(context: context)
    }

    func summary(maxVisible: Int = 3) -> RefillPurchaseSummary {
        let request = Medicine.extractMedicines()
        let medicines = (try? context.fetch(request)) ?? []

        let state = stateProvider.buildState(
            medicines: medicines,
            logs: fetchLogs(),
            todos: fetchTodos(),
            option: Option.current(in: context),
            completedTodoIDs: []
        )

        let purchaseTitles = state.computedTodos
            .filter { $0.category == .purchase }
            .map { $0.title }

        let deduped = Self.deduplicatedTitles(purchaseTitles)
        return RefillPurchaseSummary(allNames: deduped, maxVisible: max(1, maxVisible))
    }

    static func deduplicatedTitles(_ titles: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []

        for raw in titles {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized.lowercased()).inserted {
                ordered.append(normalized)
            }
        }

        return ordered
    }

    private func fetchLogs() -> [Log] {
        let request = Log.extractLogs()
        return (try? context.fetch(request)) ?? []
    }

    private func fetchTodos() -> [Todo] {
        let request: NSFetchRequest<Todo> = Todo.fetchRequest()
        return (try? context.fetch(request)) ?? []
    }
}
