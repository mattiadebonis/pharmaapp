import Foundation
import CoreData

struct RefillDoctorOpenInfo: Equatable {
    let name: String
    let hoursText: String
}

protocol RefillDoctorHoursResolving {
    func preferredDoctorOpenInfo(now: Date) -> RefillDoctorOpenInfo
}

@MainActor
final class RefillDoctorHoursResolver: RefillDoctorHoursResolving {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func preferredDoctorOpenInfo(now: Date = Date()) -> RefillDoctorOpenInfo {
        let request = Doctor.extractDoctors()
        let doctors = (try? context.fetch(request)) ?? []
        guard let doctor = preferredDoctor(from: doctors, now: now) else {
            return RefillDoctorOpenInfo(name: "Medico", hoursText: "orari non disponibili")
        }

        let doctorName = displayName(for: doctor)
        guard let slotText = todaySlotText(for: doctor, now: now) else {
            return RefillDoctorOpenInfo(name: doctorName, hoursText: "orari non disponibili")
        }

        if let active = OpeningHoursParser.activeInterval(from: slotText, now: now) {
            return RefillDoctorOpenInfo(
                name: doctorName,
                hoursText: "aperto fino alle \(OpeningHoursParser.timeString(from: active.end))"
            )
        }

        return RefillDoctorOpenInfo(name: doctorName, hoursText: "oggi \(slotText)")
    }

    private func preferredDoctor(from doctors: [Doctor], now: Date) -> Doctor? {
        if let openDoctor = doctors.first(where: { activeInterval(for: $0, now: now) != nil }) {
            return openDoctor
        }
        if let todayDoctor = doctors.first(where: { todaySlotText(for: $0, now: now) != nil }) {
            return todayDoctor
        }
        return doctors.first
    }

    private func activeInterval(for doctor: Doctor, now: Date) -> (start: Date, end: Date)? {
        guard let slot = todaySlotText(for: doctor, now: now) else { return nil }
        return OpeningHoursParser.activeInterval(from: slot, now: now)
    }

    private func todaySlotText(for doctor: Doctor, now: Date) -> String? {
        let schedule = doctor.scheduleDTO
        let weekday = weekday(for: now)
        guard let daySchedule = schedule.days.first(where: { $0.day == weekday }) else { return nil }

        switch daySchedule.mode {
        case .closed:
            return nil
        case .continuous:
            let start = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = daySchedule.primary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty, !end.isEmpty else { return nil }
            return "\(start)-\(end)"
        case .split:
            let firstStart = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstEnd = daySchedule.primary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondStart = daySchedule.secondary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondEnd = daySchedule.secondary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !firstStart.isEmpty, !firstEnd.isEmpty, !secondStart.isEmpty, !secondEnd.isEmpty else {
                return nil
            }
            return "\(firstStart)-\(firstEnd) / \(secondStart)-\(secondEnd)"
        }
    }

    private func weekday(for date: Date) -> DoctorScheduleDTO.DaySchedule.Weekday {
        switch Calendar.current.component(.weekday, from: date) {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    private func displayName(for doctor: Doctor) -> String {
        let firstName = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return fullName.isEmpty ? "Medico" : fullName
    }
}
