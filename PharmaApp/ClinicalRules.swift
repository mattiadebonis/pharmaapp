import Foundation

public struct ClinicalRules: Codable, Equatable {
    public var safety: SafetyRules?
    public var course: CoursePlan?
    public var taper: TaperPlan?
    public var interactions: InteractionRules?
    public var monitoring: [MonitoringAction]?
    public var missedDosePolicy: MissedDosePolicy?

    public init(
        safety: SafetyRules? = nil,
        course: CoursePlan? = nil,
        taper: TaperPlan? = nil,
        interactions: InteractionRules? = nil,
        monitoring: [MonitoringAction]? = nil,
        missedDosePolicy: MissedDosePolicy? = nil
    ) {
        self.safety = safety
        self.course = course
        self.taper = taper
        self.interactions = interactions
        self.monitoring = monitoring
        self.missedDosePolicy = missedDosePolicy
    }

    public func encoded() -> Data? {
        ClinicalRulesCodec.encode(self)
    }

    public static func decode(from data: Data?) -> ClinicalRules? {
        ClinicalRulesCodec.decode(from: data)
    }
}

public struct SafetyRules: Codable, Equatable {
    public var maxPerDay: Int?
    public var minIntervalHours: Int?
    public var noDriving: Bool?

    public init(maxPerDay: Int? = nil, minIntervalHours: Int? = nil, noDriving: Bool? = nil) {
        self.maxPerDay = maxPerDay
        self.minIntervalHours = minIntervalHours
        self.noDriving = noDriving
    }
}

public struct CoursePlan: Codable, Equatable {
    public var totalDays: Int

    public init(totalDays: Int) {
        self.totalDays = totalDays
    }
}

public struct TaperPlan: Codable, Equatable {
    public var steps: [TaperStep]

    public init(steps: [TaperStep]) {
        self.steps = steps
    }
}

public struct TaperStep: Codable, Equatable {
    public var startDate: Date?
    public var durationDays: Int?
    public var dosageLabel: String

    public init(startDate: Date? = nil, durationDays: Int? = nil, dosageLabel: String) {
        self.startDate = startDate
        self.durationDays = durationDays
        self.dosageLabel = dosageLabel
    }
}

public struct InteractionRules: Codable, Equatable {
    public var spacing: [SpacingRule]?

    public init(spacing: [SpacingRule]? = nil) {
        self.spacing = spacing
    }
}

public enum MonitoringDoseRelation: String, Codable, CaseIterable {
    case beforeDose
    case afterDose

    public var label: String {
        switch self {
        case .beforeDose:
            return "Prima della dose"
        case .afterDose:
            return "Dopo la dose"
        }
    }
}

public struct MonitoringAction: Codable, Equatable {
    public var kind: MonitoringKind
    public var doseRelation: MonitoringDoseRelation?
    public var offsetMinutes: Int?
    public var requiredBeforeDose: Bool
    public var schedule: MonitoringSchedule?
    public var leadMinutes: Int?

    public init(
        kind: MonitoringKind,
        doseRelation: MonitoringDoseRelation? = nil,
        offsetMinutes: Int? = nil,
        requiredBeforeDose: Bool,
        schedule: MonitoringSchedule? = nil,
        leadMinutes: Int? = nil
    ) {
        self.kind = kind
        self.doseRelation = doseRelation
        self.offsetMinutes = offsetMinutes
        self.requiredBeforeDose = requiredBeforeDose
        self.schedule = schedule
        self.leadMinutes = leadMinutes
    }

    public var resolvedDoseRelation: MonitoringDoseRelation {
        if let doseRelation {
            return doseRelation
        }
        return requiredBeforeDose ? .beforeDose : .afterDose
    }

    public var resolvedOffsetMinutes: Int {
        if let offsetMinutes {
            return max(0, offsetMinutes)
        }
        if let leadMinutes {
            return max(0, leadMinutes)
        }
        return 30
    }
}

public struct MonitoringSchedule: Codable, Equatable {
    public var rrule: String?
    public var times: [Date]?

    public init(rrule: String? = nil, times: [Date]? = nil) {
        self.rrule = rrule
        self.times = times
    }
}

public struct SpacingRule: Codable, Equatable {
    public var substance: SpacingSubstance
    public var hours: Int
    public var direction: String?

    public init(substance: SpacingSubstance, hours: Int, direction: String? = nil) {
        self.substance = substance
        self.hours = hours
        self.direction = direction
    }
}

public enum MissedDosePolicy: Codable, Equatable {
    case none
    case info(title: String?, text: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case text
    }

    private enum PolicyType: String, Codable {
        case none
        case info
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PolicyType.self, forKey: .type)
        switch type {
        case .none:
            self = .none
        case .info:
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            let text = try container.decode(String.self, forKey: .text)
            self = .info(title: title, text: text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode(PolicyType.none, forKey: .type)
        case let .info(title, text):
            try container.encode(PolicyType.info, forKey: .type)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encode(text, forKey: .text)
        }
    }
}

public enum MissedDosePreset: String, CaseIterable, Identifiable {
    case none
    case followPlan
    case contactDoctor
    case checkReminder

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none:
            return "Nessuna indicazione"
        case .followPlan:
            return "Segui indicazioni ricevute"
        case .contactDoctor:
            return "Contatta medico/farmacista"
        case .checkReminder:
            return "Consulta il promemoria"
        }
    }

    public var policy: MissedDosePolicy? {
        switch self {
        case .none:
            return nil
        case .followPlan:
            return .info(title: "Se dimentichi una dose", text: "Segui le indicazioni ricevute.")
        case .contactDoctor:
            return .info(title: "Se dimentichi una dose", text: "Contatta il medico o il farmacista.")
        case .checkReminder:
            return .info(title: "Se dimentichi una dose", text: "Consulta il promemoria della terapia.")
        }
    }

    public static func from(policy: MissedDosePolicy?) -> MissedDosePreset {
        guard let policy else { return .none }
        switch policy {
        case .none:
            return .none
        case let .info(_, text):
            switch text {
            case "Segui le indicazioni ricevute.":
                return .followPlan
            case "Contatta il medico o il farmacista.":
                return .contactDoctor
            case "Consulta il promemoria della terapia.":
                return .checkReminder
            default:
                return .followPlan
            }
        }
    }
}

public enum SpacingSubstance: String, Codable, CaseIterable {
    case iron
    case calcium
    case antacid

    public var label: String {
        switch self {
        case .iron: return "Ferro"
        case .calcium: return "Calcio"
        case .antacid: return "Antiacidi"
        }
    }
}

public enum MonitoringKind: String, Codable, CaseIterable {
    case bloodPressure
    case bloodGlucose
    case temperature
    case heartRate

    public var label: String {
        switch self {
        case .bloodPressure: return "Pressione"
        case .bloodGlucose: return "Glicemia"
        case .temperature: return "Temperatura"
        case .heartRate: return "Frequenza cardiaca"
        }
    }
}

private enum ClinicalRulesCodec {
    static func encode(_ value: ClinicalRules) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    static func decode(from data: Data?) -> ClinicalRules? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ClinicalRules.self, from: data)
    }
}
