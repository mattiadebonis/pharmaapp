import Foundation

public struct CreateLogRequest {
    public let type: LogType
    public let medicineId: MedicineId
    public let packageId: PackageId?
    public let therapyId: TherapyId?
    public let timestamp: Date
    public let scheduledDueAt: Date?
    public let operationId: UUID

    public init(
        type: LogType,
        medicineId: MedicineId,
        packageId: PackageId?,
        therapyId: TherapyId?,
        timestamp: Date,
        scheduledDueAt: Date?,
        operationId: UUID
    ) {
        self.type = type
        self.medicineId = medicineId
        self.packageId = packageId
        self.therapyId = therapyId
        self.timestamp = timestamp
        self.scheduledDueAt = scheduledDueAt
        self.operationId = operationId
    }
}

public protocol LogRepository {
    func fetchLogs(for medicineId: MedicineId) throws -> [LogEntry]
    func fetchIntakeLogs(for medicineId: MedicineId, on date: Date) throws -> [LogEntry]
    func createLog(_ request: CreateLogRequest) throws -> UUID
    func undoLog(operationId: UUID) throws -> Bool
}
