import Foundation

public struct RecordIntakeRequest {
    public let operationId: UUID
    public let medicineId: MedicineId
    public let therapyId: TherapyId?
    public let packageId: PackageId

    public init(
        operationId: UUID,
        medicineId: MedicineId,
        therapyId: TherapyId?,
        packageId: PackageId
    ) {
        self.operationId = operationId
        self.medicineId = medicineId
        self.therapyId = therapyId
        self.packageId = packageId
    }
}

public struct RecordIntakeResult: Equatable {
    public let eventId: UUID
    public let operationId: UUID
    public let wasDuplicate: Bool

    public init(eventId: UUID, operationId: UUID, wasDuplicate: Bool) {
        self.eventId = eventId
        self.operationId = operationId
        self.wasDuplicate = wasDuplicate
    }
}

public final class RecordIntakeUseCase {
    private let eventStore: EventStore
    private let clock: Clock

    public init(eventStore: EventStore, clock: Clock) {
        self.eventStore = eventStore
        self.clock = clock
    }

    public func execute(_ request: RecordIntakeRequest) throws -> RecordIntakeResult {
        do {
            if try eventStore.exists(operationId: request.operationId) {
                return RecordIntakeResult(
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
            type: .intakeRecorded,
            timestamp: clock.now(),
            medicineId: request.medicineId,
            therapyId: request.therapyId,
            packageId: request.packageId
        )

        do {
            try eventStore.append(event)
        } catch let error as PharmaError {
            if error.code == .duplicateOperation {
                return RecordIntakeResult(
                    eventId: request.operationId,
                    operationId: request.operationId,
                    wasDuplicate: true
                )
            }
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        return RecordIntakeResult(
            eventId: event.id,
            operationId: event.operationId,
            wasDuplicate: false
        )
    }
}
