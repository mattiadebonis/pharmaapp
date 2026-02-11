import Foundation

enum OperationAction: String {
    case intake
    case purchase
    case prescriptionRequest
    case prescriptionReceived
    case autoIntake
    case stockAdjustment
}

enum OperationSource: String {
    case today
    case cabinet
    case medicineRow
    case autoIntake
    case siri
    case liveActivity
    case system
    case unknown
}

struct OperationKey: Hashable {
    let rawValue: String

    static func intake(completionKey: String, source: OperationSource) -> OperationKey {
        OperationKey(rawValue: "intake|completion|\(completionKey)|\(source.rawValue)")
    }

    static func medicineAction(
        action: OperationAction,
        medicineId: UUID,
        packageId: UUID? = nil,
        source: OperationSource
    ) -> OperationKey {
        let packagePart = packageId.map { "|pkg|\($0.uuidString)" } ?? ""
        return OperationKey(rawValue: "\(action.rawValue)|med|\(medicineId.uuidString)\(packagePart)|\(source.rawValue)")
    }

    static func autoIntake(therapyId: UUID, scheduledAt: Date) -> OperationKey {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        return OperationKey(rawValue: "autoIntake|therapy|\(therapyId.uuidString)|t|\(bucket)")
    }

    static func liveActivityIntake(therapyId: UUID, scheduledAt: Date) -> OperationKey {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        return OperationKey(rawValue: "liveActivity|intake|therapy|\(therapyId.uuidString)|t|\(bucket)")
    }
}

protocol OperationIdProviding {
    func operationId(for key: OperationKey, ttl: TimeInterval) -> UUID
    func clear(_ key: OperationKey)
    func newOperationId() -> UUID
}

final class OperationIdProvider: OperationIdProviding {
    static let shared = OperationIdProvider()

    private struct Entry {
        let id: UUID
        let createdAt: Date
        let ttl: TimeInterval
    }

    private let queue = DispatchQueue(label: "pharma.operationid")
    private var storage: [String: Entry] = [:]

    private init() {}

    func operationId(for key: OperationKey, ttl: TimeInterval = 120) -> UUID {
        let now = Date()
        return queue.sync {
            if let entry = storage[key.rawValue] {
                if now.timeIntervalSince(entry.createdAt) <= entry.ttl {
                    return entry.id
                }
                storage.removeValue(forKey: key.rawValue)
            }

            let id = UUID()
            storage[key.rawValue] = Entry(id: id, createdAt: now, ttl: ttl)
            return id
        }
    }

    func clear(_ key: OperationKey) {
        queue.sync {
            storage.removeValue(forKey: key.rawValue)
        }
    }

    func clearExpired() {
        let now = Date()
        queue.sync {
            storage = storage.filter { now.timeIntervalSince($0.value.createdAt) <= $0.value.ttl }
        }
    }

    func newOperationId() -> UUID {
        UUID()
    }
}
