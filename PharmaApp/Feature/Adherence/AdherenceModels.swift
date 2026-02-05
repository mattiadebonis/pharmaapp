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

struct AdherencePoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

struct TherapySummary: Identifiable {
    let id: UUID
    let name: String
    let statusLabel: String
    let taken: Int
    let planned: Int
    let adherenceSeries: [Double]
    let hasMeasurements: Bool
    let parameterSeries: [Double]?
    let isSelfReported: Bool
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
