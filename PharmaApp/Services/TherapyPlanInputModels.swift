import Foundation

public struct TodayStateInput {
    public let medicines: [MedicineSnapshot]
    public let todos: [TodoSnapshot]
    public let option: OptionSnapshot?
    public let completedTodoIDs: Set<String>
    public let now: Date
    public let calendar: Calendar

    public init(
        medicines: [MedicineSnapshot],
        todos: [TodoSnapshot],
        option: OptionSnapshot?,
        completedTodoIDs: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.medicines = medicines
        self.todos = todos
        self.option = option
        self.completedTodoIDs = completedTodoIDs
        self.now = now
        self.calendar = calendar
    }
}

public struct MedicineSnapshot {
    public let id: MedicineId
    public let externalKey: String
    public let name: String
    public let requiresPrescription: Bool
    public let inCabinet: Bool
    public let manualIntakeRegistration: Bool
    public let hasPackages: Bool
    public let hasMedicinePackages: Bool
    public let deadlineMonth: Int?
    public let deadlineYear: Int?
    public let stockUnitsWithoutTherapy: Int?
    public let therapies: [TherapySnapshot]
    public let logs: [LogEntry]

    public init(
        id: MedicineId,
        externalKey: String,
        name: String,
        requiresPrescription: Bool,
        inCabinet: Bool,
        manualIntakeRegistration: Bool,
        hasPackages: Bool,
        hasMedicinePackages: Bool,
        deadlineMonth: Int?,
        deadlineYear: Int?,
        stockUnitsWithoutTherapy: Int?,
        therapies: [TherapySnapshot],
        logs: [LogEntry]
    ) {
        self.id = id
        self.externalKey = externalKey
        self.name = name
        self.requiresPrescription = requiresPrescription
        self.inCabinet = inCabinet
        self.manualIntakeRegistration = manualIntakeRegistration
        self.hasPackages = hasPackages
        self.hasMedicinePackages = hasMedicinePackages
        self.deadlineMonth = deadlineMonth
        self.deadlineYear = deadlineYear
        self.stockUnitsWithoutTherapy = stockUnitsWithoutTherapy
        self.therapies = therapies
        self.logs = logs
    }
}

public struct TherapySnapshot {
    public let id: TherapyId
    public let externalKey: String
    public let medicineId: MedicineId
    public let packageId: PackageId
    public let packageKey: String
    public let startDate: Date?
    public let rrule: String?
    public let doses: [DoseSnapshot]
    public let leftoverUnits: Int
    public let manualIntakeRegistration: Bool
    public let clinicalRules: ClinicalRules?
    public let personName: String?

    public init(
        id: TherapyId,
        externalKey: String,
        medicineId: MedicineId,
        packageId: PackageId,
        packageKey: String,
        startDate: Date?,
        rrule: String?,
        doses: [DoseSnapshot],
        leftoverUnits: Int,
        manualIntakeRegistration: Bool,
        clinicalRules: ClinicalRules?,
        personName: String?
    ) {
        self.id = id
        self.externalKey = externalKey
        self.medicineId = medicineId
        self.packageId = packageId
        self.packageKey = packageKey
        self.startDate = startDate
        self.rrule = rrule
        self.doses = doses
        self.leftoverUnits = leftoverUnits
        self.manualIntakeRegistration = manualIntakeRegistration
        self.clinicalRules = clinicalRules
        self.personName = personName
    }
}

public struct DoseSnapshot {
    public let time: Date
    public let amount: Double

    public init(time: Date, amount: Double) {
        self.time = time
        self.amount = amount
    }
}

public enum LogType: String, Codable {
    case intake
    case intakeUndo
    case purchase
    case purchaseUndo
    case prescriptionRequest
    case prescriptionRequestUndo
    case prescriptionReceived
    case prescriptionReceivedUndo
    case stockAdjustment

    public var undoType: LogType? {
        switch self {
        case .intake:
            return .intakeUndo
        case .purchase:
            return .purchaseUndo
        case .prescriptionRequest:
            return .prescriptionRequestUndo
        case .prescriptionReceived:
            return .prescriptionReceivedUndo
        default:
            return nil
        }
    }
}

public struct LogEntry {
    public let type: LogType
    public let timestamp: Date
    public let operationId: UUID?
    public let reversalOfOperationId: UUID?
    public let therapyId: TherapyId?
    public let packageId: PackageId?

    public init(
        type: LogType,
        timestamp: Date,
        operationId: UUID?,
        reversalOfOperationId: UUID?,
        therapyId: TherapyId?,
        packageId: PackageId?
    ) {
        self.type = type
        self.timestamp = timestamp
        self.operationId = operationId
        self.reversalOfOperationId = reversalOfOperationId
        self.therapyId = therapyId
        self.packageId = packageId
    }
}

public struct TodoSnapshot {
    public let sourceId: String
    public let title: String
    public let detail: String?
    public let category: String
    public let medicineId: MedicineId?

    public init(
        sourceId: String,
        title: String,
        detail: String?,
        category: String,
        medicineId: MedicineId?
    ) {
        self.sourceId = sourceId
        self.title = title
        self.detail = detail
        self.category = category
        self.medicineId = medicineId
    }
}

public struct OptionSnapshot {
    public let manualIntakeRegistration: Bool
    public let dayThresholdStocksAlarm: Int

    public init(manualIntakeRegistration: Bool, dayThresholdStocksAlarm: Int) {
        self.manualIntakeRegistration = manualIntakeRegistration
        self.dayThresholdStocksAlarm = dayThresholdStocksAlarm
    }
}
