import Foundation

public struct UndoActionRequest {
    public let originalOperationId: UUID
    public let undoOperationId: UUID

    public init(originalOperationId: UUID, undoOperationId: UUID) {
        self.originalOperationId = originalOperationId
        self.undoOperationId = undoOperationId
    }
}

public struct UndoActionResult: Equatable {
    public let eventId: UUID
    public let operationId: UUID
    public let wasDuplicate: Bool

    public init(eventId: UUID, operationId: UUID, wasDuplicate: Bool) {
        self.eventId = eventId
        self.operationId = operationId
        self.wasDuplicate = wasDuplicate
    }
}

public final class UndoActionUseCase {
    private let eventStore: EventStore
    private let clock: Clock

    public init(eventStore: EventStore, clock: Clock) {
        self.eventStore = eventStore
        self.clock = clock
    }

    public func execute(_ request: UndoActionRequest) throws -> UndoActionResult {
        do {
            if try eventStore.exists(operationId: request.undoOperationId) {
                return UndoActionResult(
                    eventId: request.undoOperationId,
                    operationId: request.undoOperationId,
                    wasDuplicate: true
                )
            }
            if try eventStore.hasReversal(for: request.originalOperationId) {
                return UndoActionResult(
                    eventId: request.originalOperationId,
                    operationId: request.originalOperationId,
                    wasDuplicate: true
                )
            }
        } catch let error as PharmaError {
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        let originalEvent: DomainEvent
        do {
            guard let fetched = try eventStore.fetch(operationId: request.originalOperationId) else {
                throw PharmaError(code: .notFound)
            }
            originalEvent = fetched
        } catch let error as PharmaError {
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        guard let undoType = originalEvent.type.undoType else {
            throw PharmaError(code: .invalidInput)
        }

        let undoEvent = DomainEvent(
            id: UUID(),
            operationId: request.undoOperationId,
            type: undoType,
            timestamp: clock.now(),
            medicineId: originalEvent.medicineId,
            therapyId: originalEvent.therapyId,
            packageId: originalEvent.packageId,
            reversalOfOperationId: originalEvent.operationId
        )

        do {
            try eventStore.append(undoEvent)
        } catch let error as PharmaError {
            if error.code == .duplicateOperation {
                return UndoActionResult(
                    eventId: request.undoOperationId,
                    operationId: request.undoOperationId,
                    wasDuplicate: true
                )
            }
            throw error
        } catch {
            throw PharmaError(code: .saveFailed)
        }

        return UndoActionResult(
            eventId: undoEvent.id,
            operationId: undoEvent.operationId,
            wasDuplicate: false
        )
    }
}
