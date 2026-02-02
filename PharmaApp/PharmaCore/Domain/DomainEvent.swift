import Foundation

public struct DomainEvent: Hashable, Codable {
    public let id: UUID
    public let operationId: UUID
    public let type: EventType
    public let timestamp: Date
    public let medicineId: MedicineId
    public let therapyId: TherapyId?
    public let packageId: PackageId?
    public let reversalOfOperationId: UUID?

    public init(
        id: UUID,
        operationId: UUID,
        type: EventType,
        timestamp: Date,
        medicineId: MedicineId,
        therapyId: TherapyId?,
        packageId: PackageId?,
        reversalOfOperationId: UUID? = nil
    ) {
        self.id = id
        self.operationId = operationId
        self.type = type
        self.timestamp = timestamp
        self.medicineId = medicineId
        self.therapyId = therapyId
        self.packageId = packageId
        self.reversalOfOperationId = reversalOfOperationId
    }
}
