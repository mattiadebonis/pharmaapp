import Foundation

struct SettingsPersonRecord: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var codiceFiscale: String?
    var isAccount: Bool
}

struct SettingsDoctorRecord: Identifiable, Equatable {
    let id: UUID
    var name: String?
    var email: String?
    var phone: String?
    var specialization: String?
    var schedule: DoctorScheduleDTO
    var secretaryName: String?
    var secretaryEmail: String?
    var secretaryPhone: String?
    var secretarySchedule: DoctorScheduleDTO
    var prescriptionMessageTemplate: String?
}

struct TherapyNotificationSettings: Equatable {
    var level: TherapyNotificationLevel
    var snoozeMinutes: Int
}

struct PersonWriteInput {
    var id: UUID?
    var name: String?
    var codiceFiscale: String?
    var isAccount: Bool
}

struct DoctorWriteInput {
    var id: UUID?
    var name: String?
    var email: String?
    var phone: String?
    var specialization: String?
    var schedule: DoctorScheduleDTO
    var secretaryName: String?
    var secretaryEmail: String?
    var secretaryPhone: String?
    var secretarySchedule: DoctorScheduleDTO
}

enum SettingsGatewayError: Error, LocalizedError, Equatable {
    case notFound(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case let .notFound(message), let .persistence(message):
            return message
        }
    }
}

@MainActor
protocol SettingsGateway {
    func listPersons(includeAccount: Bool) throws -> [SettingsPersonRecord]

    func person(id: UUID) throws -> SettingsPersonRecord?

    func listDoctors() throws -> [SettingsDoctorRecord]

    func doctor(id: UUID) throws -> SettingsDoctorRecord?

    func therapyNotificationPreferences() throws -> TherapyNotificationSettings

    @discardableResult
    func savePerson(_ input: PersonWriteInput) throws -> UUID

    func deletePerson(id: UUID) throws

    @discardableResult
    func saveDoctor(_ input: DoctorWriteInput) throws -> UUID

    func deleteDoctor(id: UUID) throws

    func savePrescriptionMessageTemplate(doctorId: UUID, template: String?) throws

    func saveTherapyNotificationPreferences(level: TherapyNotificationLevel, snoozeMinutes: Int) throws
}
