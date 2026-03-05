//
//  MedicinePackage.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 24/01/26.
//

import Foundation
import CoreData

@objc(MedicinePackage)
public class MedicinePackage: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var created_at: Date?
    @NSManaged public var deadline_month: Int32
    @NSManaged public var deadline_year: Int32
    @NSManaged public var purchase_operation_id: UUID?
    @NSManaged public var reversed_by_operation_id: UUID?
    @NSManaged public var source_id: UUID?
    @NSManaged public var visibility: String?
    @NSManaged public var cabinet: Cabinet?
    @NSManaged public var medicine: Medicine
    @NSManaged public var package: Package
    @NSManaged public var therapies: Set<Therapy>?
}

extension MedicinePackage {
    private static let deadlineYearRange = 2000...2100

    static func extractEntries() -> NSFetchRequest<MedicinePackage> {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        let sortDescriptor = NSSortDescriptor(key: "created_at", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        return request
    }

    var isReversed: Bool {
        reversed_by_operation_id != nil
    }

    var isPurchased: Bool {
        purchase_operation_id != nil
    }

    var isPlaceholder: Bool {
        purchase_operation_id == nil
    }

    var deadlineMonthYear: (month: Int, year: Int)? {
        guard let month = normalizedDeadlineMonth,
              let year = normalizedDeadlineYear else {
            return nil
        }
        return (month, year)
    }

    var deadlineLabel: String? {
        guard let info = deadlineMonthYear else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        let monthName = formatter.monthSymbols[info.month - 1]
        return "Scade a \(monthName) \(info.year)"
    }

    var deadlineMonthStartDate: Date? {
        resolvedDeadlineMonthStartDate(calendar: .current)
    }

    func deadlineStatus(referenceDate: Date = Date(), calendar: Calendar = .current) -> Medicine.DeadlineStatus {
        guard let months = monthsUntilDeadline(referenceDate: referenceDate, calendar: calendar) else { return .none }
        if months < 0 { return .expired }
        if months <= 1 { return .expiringSoon }
        return .ok
    }

    var deadlineStatus: Medicine.DeadlineStatus {
        deadlineStatus(referenceDate: Date(), calendar: .current)
    }

    func deadlineDisplay(referenceDate: Date = Date(), calendar: Calendar = .current) -> Medicine.DeadlineDisplay? {
        guard let label = deadlineLabel else { return nil }
        let status = deadlineStatus(referenceDate: referenceDate, calendar: calendar)

        switch status {
        case .none:
            return nil
        case .expired:
            return Medicine.DeadlineDisplay(label: "Scaduto · \(label)", status: .expired)
        case .expiringSoon:
            let months = monthsUntilDeadline(referenceDate: referenceDate, calendar: calendar) ?? 0
            let remainingLabel: String
            if months <= 0 {
                remainingLabel = "Scade questo mese"
            } else if months == 1 {
                remainingLabel = "Scade tra 1 mese"
            } else {
                remainingLabel = "Scade tra \(months) mesi"
            }
            return Medicine.DeadlineDisplay(label: remainingLabel, status: .expiringSoon)
        case .ok:
            return Medicine.DeadlineDisplay(label: label, status: .ok)
        }
    }

    func updateDeadline(month: Int?, year: Int?) {
        if let month, let year, isValidDeadline(month: month, year: year) {
            deadline_month = Int32(month)
            deadline_year = Int32(year)
        } else {
            deadline_month = 0
            deadline_year = 0
        }
    }

    static func fetchByPurchaseOperationId(
        _ operationId: UUID,
        in context: NSManagedObjectContext
    ) -> MedicinePackage? {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.predicate = NSPredicate(format: "purchase_operation_id == %@", operationId as CVarArg)
        return try? context.fetch(request).first
    }

    static func latestActiveEntry(
        for medicine: Medicine,
        package: Package,
        in context: NSManagedObjectContext
    ) -> MedicinePackage? {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: false)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "medicine == %@", medicine),
            NSPredicate(format: "package == %@", package),
            NSPredicate(format: "reversed_by_operation_id == nil")
        ])
        return try? context.fetch(request).first
    }

    private var normalizedDeadlineMonth: Int? {
        let month = Int(deadline_month)
        return (1...12).contains(month) ? month : nil
    }

    private var normalizedDeadlineYear: Int? {
        let year = Int(deadline_year)
        return Self.deadlineYearRange.contains(year) ? year : nil
    }

    private func isValidDeadline(month: Int, year: Int) -> Bool {
        (1...12).contains(month) && Self.deadlineYearRange.contains(year)
    }

    private func resolvedDeadlineMonthStartDate(calendar: Calendar) -> Date? {
        guard let info = deadlineMonthYear else { return nil }
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = info.year
        comps.month = info.month
        comps.day = 1
        return calendar.date(from: comps)
    }

    private func monthsUntilDeadline(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let deadlineStart = resolvedDeadlineMonthStartDate(calendar: calendar) else { return nil }
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate
        return calendar.dateComponents([.month], from: monthStart, to: deadlineStart).month
    }
}
