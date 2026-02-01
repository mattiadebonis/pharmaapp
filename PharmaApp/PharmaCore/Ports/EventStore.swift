import Foundation

public protocol EventStore {
    func exists(operationId: UUID) throws -> Bool
    func append(_ event: DomainEvent) throws
    func fetchUnsyncedEvents(limit: Int) throws -> [DomainEvent]
}
