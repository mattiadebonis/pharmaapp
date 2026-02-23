import Foundation

public enum TodayTodoCategory: String, CaseIterable, Hashable, Codable {
    case therapy
    case monitoring
    case missedDose
    case purchase
    case deadline
    case prescription
    case upcoming
    case pharmacy

    public static var displayOrder: [TodayTodoCategory] {
        [.monitoring, .therapy, .missedDose, .purchase, .deadline, .prescription, .upcoming, .pharmacy]
    }
}

public struct TodayTodoItem: Identifiable, Hashable, Codable {
    public typealias Category = TodayTodoCategory

    public let id: String
    public let title: String
    public let detail: String?
    public let category: Category
    public let medicineId: MedicineId?

    public init(
        id: String,
        title: String,
        detail: String?,
        category: Category,
        medicineId: MedicineId?
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.medicineId = medicineId
    }
}

public struct TodayMedicineStatus: Equatable, Codable {
    public let needsPrescription: Bool
    public let isOutOfStock: Bool
    public let isDepleted: Bool
    public let purchaseStockStatus: String?
    public let personName: String?

    public init(
        needsPrescription: Bool,
        isOutOfStock: Bool,
        isDepleted: Bool,
        purchaseStockStatus: String?,
        personName: String?
    ) {
        self.needsPrescription = needsPrescription
        self.isOutOfStock = isOutOfStock
        self.isDepleted = isDepleted
        self.purchaseStockStatus = purchaseStockStatus
        self.personName = personName
    }
}

public struct TodayBlockedTherapyStatus: Equatable, Codable {
    public let medicineId: MedicineId
    public let needsPrescription: Bool
    public let isOutOfStock: Bool
    public let isDepleted: Bool
    public let personName: String?

    public init(
        medicineId: MedicineId,
        needsPrescription: Bool,
        isOutOfStock: Bool,
        isDepleted: Bool,
        personName: String?
    ) {
        self.medicineId = medicineId
        self.needsPrescription = needsPrescription
        self.isOutOfStock = isOutOfStock
        self.isDepleted = isDepleted
        self.personName = personName
    }
}

public enum TodayTimeLabelKind: String, Hashable, Codable {
    case purchase
    case deadline
}

public enum TodayTimeLabel: Hashable, Codable {
    case time(Date)
    case category(TodayTimeLabelKind)
}

public struct TodayState: Equatable {
    public let computedTodos: [TodayTodoItem]
    public let pendingItems: [TodayTodoItem]
    public let therapyItems: [TodayTodoItem]
    public let purchaseItems: [TodayTodoItem]
    public let otherItems: [TodayTodoItem]
    public let showPharmacyCard: Bool
    public let timeLabels: [String: TodayTimeLabel]
    public let medicineStatuses: [MedicineId: TodayMedicineStatus]
    public let blockedTherapyStatuses: [String: TodayBlockedTherapyStatus]
    public let syncToken: String

    public init(
        computedTodos: [TodayTodoItem],
        pendingItems: [TodayTodoItem],
        therapyItems: [TodayTodoItem],
        purchaseItems: [TodayTodoItem],
        otherItems: [TodayTodoItem],
        showPharmacyCard: Bool,
        timeLabels: [String: TodayTimeLabel],
        medicineStatuses: [MedicineId: TodayMedicineStatus],
        blockedTherapyStatuses: [String: TodayBlockedTherapyStatus],
        syncToken: String
    ) {
        self.computedTodos = computedTodos
        self.pendingItems = pendingItems
        self.therapyItems = therapyItems
        self.purchaseItems = purchaseItems
        self.otherItems = otherItems
        self.showPharmacyCard = showPharmacyCard
        self.timeLabels = timeLabels
        self.medicineStatuses = medicineStatuses
        self.blockedTherapyStatuses = blockedTherapyStatuses
        self.syncToken = syncToken
    }

    public func timeLabel(for item: TodayTodoItem) -> TodayTimeLabel? {
        timeLabels[item.id]
    }

    public static let empty = TodayState(
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
