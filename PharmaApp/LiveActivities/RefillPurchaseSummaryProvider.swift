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
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")

    init(
        context: NSManagedObjectContext
    ) {
        self.context = context
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
            return underThresholdSummary(maxVisible: maxVisible)
        case .fullTodayState:
            return underThresholdSummary(maxVisible: maxVisible)
        }
    }

    private func underThresholdSummary(maxVisible: Int) -> RefillPurchaseSummary {
        let request = Medicine.extractMedicines()
        let medicines = (try? context.fetch(request)) ?? []
        let option = Option.current(in: context)
        let sections = computeSections(for: medicines, logs: [], option: option)
        let names = sections.purchase.map { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines) }
        return RefillPurchaseSummary(
            allNames: Self.deduplicatedTitles(names),
            maxVisible: max(1, maxVisible)
        )
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
}
