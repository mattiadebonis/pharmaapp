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

enum StatisticsRange: String, CaseIterable, Identifiable {
    case days
    case weeks
    case months
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days: return "Giorni"
        case .weeks: return "Settimane"
        case .months: return "Mesi"
        case .all: return "Tutto"
        }
    }
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

struct OverallTrendPoint: Identifiable {
    let date: Date
    let adherence: Double
    let punctuality: Double
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

struct MonitoringCorrelationPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct TherapyMonitoringCorrelation {
    let therapyTitle: String
    let parameterTitle: String
    let parameterUnit: String
    let parameterPoints: [MonitoringCorrelationPoint]
    /// Moving-average smoothed version of parameterPoints (same dates, averaged values).
    let smoothedParameterPoints: [MonitoringCorrelationPoint]
    let adherencePoints: [MonitoringCorrelationPoint]
    let correlationCoefficient: Double?
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
