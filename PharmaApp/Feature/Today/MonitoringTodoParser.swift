import Foundation

struct MonitoringTodoDescriptor: Equatable {
    enum SourceKind: String, Equatable {
        case dose
        case schedule
    }

    let sourceKind: SourceKind
    let kind: MonitoringKind
    let doseRelation: MonitoringDoseRelation?
    let therapyExternalKey: String
    let doseTimestamp: Date?
    let triggerTimestamp: Date

    var todoTimestamp: Date {
        triggerTimestamp
    }

    static func parse(id: String) -> MonitoringTodoDescriptor? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5, parts[0] == "monitoring" else { return nil }
        guard let sourceKind = SourceKind(rawValue: parts[1]) else { return nil }
        guard let kind = MonitoringKind(rawValue: parts[2]) else { return nil }

        switch sourceKind {
        case .dose:
            // New format: monitoring|dose|kind|relation|therapyKey|doseTs|triggerTs
            if parts.count >= 7,
               let relation = MonitoringDoseRelation(rawValue: parts[3]),
               let doseSeconds = TimeInterval(parts[5]),
               let triggerSeconds = TimeInterval(parts[6]) {
                return MonitoringTodoDescriptor(
                    sourceKind: .dose,
                    kind: kind,
                    doseRelation: relation,
                    therapyExternalKey: parts[4],
                    doseTimestamp: Date(timeIntervalSince1970: doseSeconds),
                    triggerTimestamp: Date(timeIntervalSince1970: triggerSeconds)
                )
            }

            // Legacy format: monitoring|dose|kind|therapyKey|doseTs
            if parts.count >= 5,
               let doseSeconds = TimeInterval(parts[4]) {
                let doseDate = Date(timeIntervalSince1970: doseSeconds)
                return MonitoringTodoDescriptor(
                    sourceKind: .dose,
                    kind: kind,
                    doseRelation: .beforeDose,
                    therapyExternalKey: parts[3],
                    doseTimestamp: doseDate,
                    triggerTimestamp: doseDate
                )
            }

        case .schedule:
            // monitoring|schedule|kind|therapyKey|scheduleTs
            if parts.count >= 5,
               let scheduleSeconds = TimeInterval(parts[4]) {
                let scheduleDate = Date(timeIntervalSince1970: scheduleSeconds)
                return MonitoringTodoDescriptor(
                    sourceKind: .schedule,
                    kind: kind,
                    doseRelation: nil,
                    therapyExternalKey: parts[3],
                    doseTimestamp: nil,
                    triggerTimestamp: scheduleDate
                )
            }
        }

        return nil
    }
}
