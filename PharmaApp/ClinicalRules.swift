import Foundation

struct ClinicalRules: Codable, Equatable {
    var safety: SafetyRules?
    var course: CoursePlan?
    var taper: TaperPlan?
    var interactions: InteractionRules?
    var monitoring: [MonitoringAction]?
    var missedDosePolicy: MissedDosePolicy?

    func encoded() -> Data? {
        ClinicalRulesCodec.encode(self)
    }

    static func decode(from data: Data?) -> ClinicalRules? {
        ClinicalRulesCodec.decode(from: data)
    }
}

struct SafetyRules: Codable, Equatable {
    var maxPerDay: Int?
    var minIntervalHours: Int?
    var noDriving: Bool?
}

struct CoursePlan: Codable, Equatable {
    var totalDays: Int
}

struct TaperPlan: Codable, Equatable {
    var steps: [TaperStep]
}

struct TaperStep: Codable, Equatable {
    var startDate: Date?
    var durationDays: Int?
    var dosageLabel: String
}

struct InteractionRules: Codable, Equatable {
    var spacing: [SpacingRule]?
}

struct MonitoringAction: Codable, Equatable {
    var kind: MonitoringKind
    var requiredBeforeDose: Bool
    var schedule: MonitoringSchedule?
    var leadMinutes: Int?
}

struct MonitoringSchedule: Codable, Equatable {
    var rrule: String?
    var times: [Date]?
}

struct SpacingRule: Codable, Equatable {
    var substance: SpacingSubstance
    var hours: Int
    var direction: String?
}

enum MissedDosePolicy: Codable, Equatable {
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

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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

enum MissedDosePreset: String, CaseIterable, Identifiable {
    case none
    case followPlan
    case contactDoctor
    case checkReminder

    var id: String { rawValue }

    var label: String {
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

    var policy: MissedDosePolicy? {
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

    static func from(policy: MissedDosePolicy?) -> MissedDosePreset {
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

enum SpacingSubstance: String, Codable, CaseIterable {
    case iron
    case calcium
    case antacid

    var label: String {
        switch self {
        case .iron: return "Ferro"
        case .calcium: return "Calcio"
        case .antacid: return "Antiacidi"
        }
    }
}

enum MonitoringKind: String, Codable, CaseIterable {
    case bloodPressure
    case bloodGlucose

    var label: String {
        switch self {
        case .bloodPressure: return "Pressione"
        case .bloodGlucose: return "Glicemia"
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
