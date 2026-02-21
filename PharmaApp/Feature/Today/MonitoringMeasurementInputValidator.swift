import Foundation

struct MonitoringMeasurementValidatedInput: Equatable {
    let primaryValue: Double
    let secondaryValue: Double?
    let unit: String
}

enum MonitoringMeasurementValidationError: LocalizedError, Equatable {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }
}

enum MonitoringMeasurementInputValidator {
    static func validate(
        kind: MonitoringKind,
        primary: String,
        secondary: String?
    ) -> Result<MonitoringMeasurementValidatedInput, MonitoringMeasurementValidationError> {
        switch kind {
        case .temperature:
            guard let value = parseDecimal(primary), value >= 0 else {
                return .failure(.invalidInput("Inserisci una temperatura valida in °C."))
            }
            return .success(.init(primaryValue: value, secondaryValue: nil, unit: "°C"))

        case .bloodPressure:
            guard let systolic = parseInteger(primary), systolic > 0 else {
                return .failure(.invalidInput("Inserisci la sistolica in mmHg."))
            }
            guard let secondary, let diastolic = parseInteger(secondary), diastolic > 0 else {
                return .failure(.invalidInput("Inserisci la diastolica in mmHg."))
            }
            return .success(.init(primaryValue: Double(systolic), secondaryValue: Double(diastolic), unit: "mmHg"))

        case .bloodGlucose:
            guard let value = parseInteger(primary), value > 0 else {
                return .failure(.invalidInput("Inserisci una glicemia valida in mg/dL."))
            }
            return .success(.init(primaryValue: Double(value), secondaryValue: nil, unit: "mg/dL"))

        case .heartRate:
            guard let value = parseInteger(primary), value > 0 else {
                return .failure(.invalidInput("Inserisci una frequenza cardiaca valida in bpm."))
            }
            return .success(.init(primaryValue: Double(value), secondaryValue: nil, unit: "bpm"))
        }
    }

    private static func parseDecimal(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private static func parseInteger(_ raw: String) -> Int? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.range(of: "^-?[0-9]+$", options: .regularExpression) != nil else {
            return nil
        }
        return Int(cleaned)
    }
}
