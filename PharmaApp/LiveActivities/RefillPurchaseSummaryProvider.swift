import Foundation
import CoreData
import os.signpost

enum RefillSummaryStrategy {
    case lightweightTodos
    case fullTodayState
}

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
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")

    init(
        context: NSManagedObjectContext,
        stateProvider: CoreDataTodayStateProvider? = nil
    ) {
        self.context = context
        self.stateProvider = stateProvider ?? CoreDataTodayStateProvider(context: context)
    }

    func summary(
        maxVisible: Int = 3,
        strategy: RefillSummaryStrategy = .lightweightTodos
    ) -> RefillPurchaseSummary {
        let signpostID = OSSignpostID(log: perfLog)
        os_signpost(.begin, log: perfLog, name: "RefillSummary", signpostID: signpostID)
        defer { os_signpost(.end, log: perfLog, name: "RefillSummary", signpostID: signpostID) }

        switch strategy {
        case .lightweightTodos:
            return lightweightSummary(maxVisible: maxVisible)
        case .fullTodayState:
            return fullStateSummary(maxVisible: maxVisible)
        }
    }

    private func lightweightSummary(maxVisible: Int) -> RefillPurchaseSummary {
        let request: NSFetchRequest<Todo> = Todo.fetchRequest()
        request.predicate = NSPredicate(format: "category == %@", TodayTodoCategory.purchase.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "updated_at", ascending: false)]
        request.fetchLimit = max(60, maxVisible * 8)
        let titles = ((try? context.fetch(request)) ?? []).map(\.title)
        let deduped = Self.deduplicatedTitles(titles)
        return RefillPurchaseSummary(allNames: deduped, maxVisible: max(1, maxVisible))
    }

    private func fullStateSummary(maxVisible: Int) -> RefillPurchaseSummary {
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
