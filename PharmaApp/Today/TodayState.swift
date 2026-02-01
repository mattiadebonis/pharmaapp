import Foundation

struct TodayState: Equatable {
    let computedTodos: [TodayTodoItem]
    let pendingItems: [TodayTodoItem]
    let therapyItems: [TodayTodoItem]
    let purchaseItems: [TodayTodoItem]
    let otherItems: [TodayTodoItem]
    let showPharmacyCard: Bool
    let syncToken: String

    static let empty = TodayState(
        computedTodos: [],
        pendingItems: [],
        therapyItems: [],
        purchaseItems: [],
        otherItems: [],
        showPharmacyCard: false,
        syncToken: ""
    )
}
