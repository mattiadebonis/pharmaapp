import Foundation

/// DTO che descrive gli orari di un dottore in modo strutturato e serializzabile.
/// Viene salvato come JSON nel campo `Doctor.orari`.
struct DoctorScheduleDTO: Codable, Equatable {
    struct TimeSlot: Codable, Equatable {
        var start: String
        var end: String

        static let continuousDefault = TimeSlot(start: "09:00", end: "18:00")
        static let morningDefault = TimeSlot(start: "09:00", end: "12:30")
        static let afternoonDefault = TimeSlot(start: "15:00", end: "18:30")

        var isEmpty: Bool { start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    struct DaySchedule: Codable, Identifiable, Equatable {
        enum Weekday: String, Codable, CaseIterable, Identifiable {
            case monday, tuesday, wednesday, thursday, friday, saturday, sunday

            var id: String { rawValue }

            var displayName: String {
                switch self {
                case .monday: return "Lunedì"
                case .tuesday: return "Martedì"
                case .wednesday: return "Mercoledì"
                case .thursday: return "Giovedì"
                case .friday: return "Venerdì"
                case .saturday: return "Sabato"
                case .sunday: return "Domenica"
                }
            }
        }

        enum Mode: String, Codable, CaseIterable, Identifiable {
            case closed
            case continuous
            case split

            var id: String { rawValue }

            var displayName: String {
                switch self {
                case .closed: return "Chiuso"
                case .continuous: return "Continuato"
                case .split: return "Spezzato"
                }
            }
        }

        var day: Weekday
        var mode: Mode
        var primary: TimeSlot
        var secondary: TimeSlot

        var id: Weekday { day }

        init(day: Weekday, mode: Mode = .closed, primary: TimeSlot = TimeSlot.continuousDefault, secondary: TimeSlot = TimeSlot.afternoonDefault) {
            self.day = day
            self.mode = mode
            self.primary = primary
            self.secondary = secondary
            normalizeForCurrentMode()
        }

        /// Garantisce che esistano valori di default coerenti con la modalità selezionata.
        mutating func normalizeForCurrentMode() {
            switch mode {
            case .closed:
                // Nessun vincolo: lasciamo i valori memorizzati per eventuali ripristini
                break
            case .continuous:
                if primary.isEmpty {
                    primary = .continuousDefault
                }
            case .split:
                if primary.isEmpty {
                    primary = .morningDefault
                }
                if secondary.isEmpty {
                    secondary = .afternoonDefault
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case day
            case mode
            case periods
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            day = try container.decode(Weekday.self, forKey: .day)
            mode = try container.decode(Mode.self, forKey: .mode)
            var periods = try container.decodeIfPresent([TimeSlot].self, forKey: .periods) ?? []
            if let first = periods.first {
                primary = first
            } else {
                primary = (mode == .split) ? .morningDefault : .continuousDefault
            }
            if periods.count > 1 {
                secondary = periods[1]
            } else {
                secondary = .afternoonDefault
            }
            normalizeForCurrentMode()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(day, forKey: .day)
            try container.encode(mode, forKey: .mode)
            let periods: [TimeSlot]
            switch mode {
            case .closed:
                periods = []
            case .continuous:
                periods = [primary]
            case .split:
                periods = [primary, secondary]
            }
            try container.encode(periods, forKey: .periods)
        }
    }

    var days: [DaySchedule]

    init(days: [DaySchedule] = DaySchedule.Weekday.allCases.map { DaySchedule(day: $0) }) {
        self.days = days
    }

    /// Ritorna la rappresentazione JSON codificata in UTF8 da salvare nel campo `orari`.
    func encodedJSONString(prettyPrinted: Bool = false) throws -> String {
        let encoder = JSONEncoder()
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        } else {
            encoder.outputFormatting = [.sortedKeys]
        }
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DoctorScheduleDTO", code: -1, userInfo: [NSLocalizedDescriptionKey: "Impossibile convertire il JSON in stringa UTF8"])
        }
        return string
    }

    static func decode(from string: String?) -> DoctorScheduleDTO? {
        guard let raw = string, let data = raw.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(DoctorScheduleDTO.self, from: data)
        } catch {
            print("Impossibile decodificare DoctorScheduleDTO: \(error)")
            return nil
        }
    }
}

extension Doctor {
    /// Restituisce gli orari decodificati come DTO, creando una struttura vuota se non presente o non valida.
    var scheduleDTO: DoctorScheduleDTO {
        get {
            if let decoded = DoctorScheduleDTO.decode(from: orari) {
                return decoded
            }
            return DoctorScheduleDTO()
        }
        set {
            do {
                orari = try newValue.encodedJSONString()
            } catch {
                print("Errore nella codifica degli orari del dottore: \(error)")
            }
        }
    }
}
