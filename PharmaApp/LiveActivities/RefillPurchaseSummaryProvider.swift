import Foundation
import CoreData
import os.signpost

enum RefillSummaryStrategy {
    case lightweightTodos
    case fullTodayState
}

struct RefillPurchaseSummary: Equatable {
    let allNames: [String]
    let allItems: [RefillActivityAttributes.PurchaseItem]
    let maxVisible: Int

    var visibleNames: [String] {
        Array(allNames.prefix(maxVisible))
    }

    var visibleItems: [RefillActivityAttributes.PurchaseItem] {
        Array(allItems.prefix(maxVisible))
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
        let recurrenceManager = RecurrenceManager(context: context)

        var names: [String] = []
        var items: [RefillActivityAttributes.PurchaseItem] = []
        var seen = Set<String>()

        for medicine in sections.purchase {
            let name = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard seen.insert(name.lowercased()).inserted else { continue }

            let days = Self.autonomyDays(for: medicine, recurrenceManager: recurrenceManager)
            let units = Self.remainingUnits(for: medicine)
            names.append(name)
            items.append(RefillActivityAttributes.PurchaseItem(name: name, autonomyDays: days, remainingUnits: units))
        }

        return RefillPurchaseSummary(
            allNames: names,
            allItems: items,
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

    private static func remainingUnits(for medicine: Medicine) -> Int? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else {
            return medicine.remainingUnitsWithoutTherapy()
        }
        let total = therapies.reduce(0) { $0 + Int($1.leftover()) }
        return max(0, total)
    }

    private static func autonomyDays(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Int? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        var totalLeftover: Double = 0
        var totalDaily: Double = 0
        for therapy in therapies {
            totalLeftover += Double(therapy.leftover())
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }
        guard totalDaily > 0 else { return nil }
        return max(0, Int(floor(totalLeftover / totalDaily)))
    }
}
