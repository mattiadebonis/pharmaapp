import Foundation

struct CriticalDoseLiveActivityConfig: Equatable {
    let leadTimeMinutes: Int
    let overdueToleranceMinutes: Int
    let snoozeMinutes: Int

    static let `default` = CriticalDoseLiveActivityConfig(
        leadTimeMinutes: 10,
        overdueToleranceMinutes: 30,
        snoozeMinutes: 10
    )

    var leadTimeInterval: TimeInterval {
        TimeInterval(leadTimeMinutes * 60)
    }

    var overdueToleranceInterval: TimeInterval {
        TimeInterval(overdueToleranceMinutes * 60)
    }

    var snoozeInterval: TimeInterval {
        TimeInterval(snoozeMinutes * 60)
    }
}

struct CriticalDoseCandidate: Equatable {
    let therapyId: UUID
    let medicineId: UUID
    let medicineName: String
    let doseText: String
    let scheduledAt: Date
}

struct CriticalDoseAggregate: Equatable {
    let primary: CriticalDoseCandidate
    let additionalCount: Int
    let subtitleDisplay: String
    let expiryAt: Date
}

struct CriticalDosePlan: Equatable {
    let aggregate: CriticalDoseAggregate?
    let nextRefreshAt: Date?

    static let empty = CriticalDosePlan(aggregate: nil, nextRefreshAt: nil)
}
