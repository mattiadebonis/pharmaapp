import Foundation

enum AdherencePeriod: String, CaseIterable, Identifiable {
    case day1
    case week1
    case month1
    case months6
    case all

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .day1: return "1g"
        case .week1: return "7g"
        case .month1: return "30g"
        case .months6: return "6m"
        case .all: return "Tutto"
        }
    }

    var reportLabel: String {
        switch self {
        case .day1: return "1 giorno"
        case .week1: return "7 giorni"
        case .month1: return "30 giorni"
        case .months6: return "6 mesi"
        case .all: return "Tutto"
        }
    }

    var trendPrefix: String {
        switch self {
        case .day1: return "Oggi"
        case .week1: return "Ultima settimana"
        case .month1: return "Ultimo mese"
        case .months6: return "Ultimi 6 mesi"
        case .all: return "Tutto il periodo"
        }
    }

    var totalDays: Int? {
        switch self {
        case .day1: return 1
        case .week1: return 7
        case .month1: return 30
        case .months6, .all: return nil
        }
    }

    var bucketUnit: AdherenceBucketUnit {
        switch self {
        case .day1, .week1, .month1:
            return .day
        case .months6:
            return .week
        case .all:
            return .month
        }
    }
}

enum AdherenceBucketUnit {
    case day
    case week
    case month
}

struct WeekdayAdherence: Identifiable {
    let label: String
    let percentage: Double
    var id: String { label }
}

struct TimeSlotPunctuality: Identifiable {
    let label: String
    let percentage: Double
    var id: String { label }
}

struct StockSummary {
    let totalCount: Int
    let okCount: Int
    let notOkCount: Int
    let minNotOkDays: Int  // days remaining for the worst not-ok medicine (0 = esaurite)

    var okPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(okCount) / Double(totalCount)
    }

    static let empty = StockSummary(totalCount: 0, okCount: 0, notOkCount: 0, minNotOkDays: 0)
}

struct DayAdherence: Identifiable {
    let date: Date
    let taken: Int
    let planned: Int
    var percentage: Double { planned > 0 ? min(1, Double(taken) / Double(planned)) : -1 }
    var id: Date { date }
}

struct MedicineCoverage: Identifiable {
    let name: String
    let days: Int
    let threshold: Int
    var id: String { name }
    var isOk: Bool { days >= threshold }
}

struct TherapyTimeStat: Identifiable {
    let medicineName: String
    let avgHour: Int
    let avgMinute: Int
    let stdDevMinutes: Int
    var id: String { medicineName }
}

struct ReportRow {
    let name: String
    let taken: Int
    let planned: Int
    let hasMeasurements: Bool
    let note: String?
}

struct ReportData {
    let generatedAt: Date
    let period: AdherencePeriod
    let generalTaken: Int
    let generalPlanned: Int
    let trendLabel: String
    let rows: [ReportRow]
}
