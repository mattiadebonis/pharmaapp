import Foundation

public struct RecordPurchaseRequest {
    public let operationId: UUID
    public let medicineId: MedicineId
    public let packageId: PackageId

    public init(operationId: UUID, medicineId: MedicineId, packageId: PackageId) {
        self.operationId = operationId
        self.medicineId = medicineId
        self.packageId = packageId
    }
}

public struct RecordPurchaseResult: Equatable {
    public let eventId: UUID
    public let operationId: UUID
    public let wasDuplicate: Bool

    public init(eventId: UUID, operationId: UUID, wasDuplicate: Bool) {
        self.eventId = eventId
        self.operationId = operationId
        self.wasDuplicate = wasDuplicate
    }
}

public final class RecordPurchaseUseCase {
    private let eventStore: EventStore
    private let clock: Clock

    public init(eventStore: EventStore, clock: Clock) {
        self.eventStore = eventStore
        self.clock = clock
    }

    public func execute(_ request: RecordPurchaseRequest) throws -> RecordPurchaseResult {
        do {
            if try eventStore.exists(operationId: request.operationId) {
                return RecordPurchaseResult(
                    eventId: request.operationId,
                    operationId: request.operationId,
                    wasDuplicate: true
                )
            }
        } catch let error as PharmaError {
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        let event = DomainEvent(
            id: UUID(),
            operationId: request.operationId,
            type: .purchaseRecorded,
            timestamp: clock.now(),
            medicineId: request.medicineId,
            therapyId: nil,
            packageId: request.packageId
        )

        do {
            try eventStore.append(event)
        } catch let error as PharmaError {
            if error.code == .duplicateOperation {
                return RecordPurchaseResult(
                    eventId: request.operationId,
                    operationId: request.operationId,
                    wasDuplicate: true
                )
            }
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        return RecordPurchaseResult(
            eventId: event.id,
            operationId: event.operationId,
            wasDuplicate: false
        )
    }
}
