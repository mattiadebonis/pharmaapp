import Foundation
import CoreData

struct TodayMedicineStatus: Equatable {
    let needsPrescription: Bool
    let isOutOfStock: Bool
    let isDepleted: Bool
    let purchaseStockStatus: String?
    let personName: String?
}

struct TodayBlockedTherapyStatus: Equatable {
    let medicineID: NSManagedObjectID
    let needsPrescription: Bool
    let isOutOfStock: Bool
    let isDepleted: Bool
    let personName: String?
}

struct TodayState: Equatable {
    let computedTodos: [TodayTodoItem]
    let pendingItems: [TodayTodoItem]
    let therapyItems: [TodayTodoItem]
    let purchaseItems: [TodayTodoItem]
    let otherItems: [TodayTodoItem]
    let showPharmacyCard: Bool
    let timeLabels: [String: String]
    let medicineStatuses: [NSManagedObjectID: TodayMedicineStatus]
    let blockedTherapyStatuses: [String: TodayBlockedTherapyStatus]
    let syncToken: String

    func timeLabel(for item: TodayTodoItem) -> String? {
        timeLabels[item.id]
    }

    static let empty = TodayState(
        computedTodos: [],
        pendingItems: [],
        therapyItems: [],
        purchaseItems: [],
        otherItems: [],
        showPharmacyCard: false,
        timeLabels: [:],
        medicineStatuses: [:],
        blockedTherapyStatuses: [:],
        syncToken: ""
    )
}
