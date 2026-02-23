import Foundation

public enum TodoCategory: String, CaseIterable, Hashable, Codable {
    case therapy
    case monitoring
    case missedDose
    case purchase
    case deadline
    case prescription
    case upcoming
    case pharmacy

    public static var displayOrder: [TodoCategory] {
        [.monitoring, .therapy, .missedDose, .purchase, .deadline, .prescription, .upcoming, .pharmacy]
    }
}

public struct TodoItem: Identifiable, Hashable, Codable {
    public typealias Category = TodoCategory

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

public struct MedicineStatusInfo: Equatable, Codable {
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

public struct BlockedTherapyStatus: Equatable, Codable {
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

public enum TimeLabelKind: String, Hashable, Codable {
    case purchase
    case deadline
}

public enum TimeLabel: Hashable, Codable {
    case time(Date)
    case category(TimeLabelKind)
}

public struct TherapyPlanState: Equatable {
    public let computedTodos: [TodoItem]
    public let pendingItems: [TodoItem]
    public let therapyItems: [TodoItem]
    public let purchaseItems: [TodoItem]
    public let otherItems: [TodoItem]
    public let showPharmacyCard: Bool
    public let timeLabels: [String: TimeLabel]
    public let medicineStatuses: [MedicineId: MedicineStatusInfo]
    public let blockedTherapyStatuses: [String: BlockedTherapyStatus]
    public let syncToken: String

    public init(
        computedTodos: [TodoItem],
        pendingItems: [TodoItem],
        therapyItems: [TodoItem],
        purchaseItems: [TodoItem],
        otherItems: [TodoItem],
        showPharmacyCard: Bool,
        timeLabels: [String: TimeLabel],
        medicineStatuses: [MedicineId: MedicineStatusInfo],
        blockedTherapyStatuses: [String: BlockedTherapyStatus],
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

    public func timeLabel(for item: TodoItem) -> TimeLabel? {
        timeLabels[item.id]
    }

    public static let empty = TherapyPlanState(
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
