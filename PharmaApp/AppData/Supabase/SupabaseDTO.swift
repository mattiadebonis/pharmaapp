import Foundation

// MARK: - Supabase DTO types
// These map directly to database table columns using snake_case CodingKeys.

struct SBProfile: Codable {
    let id: UUID
    var displayName: String?
    var photoUrl: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case photoUrl = "photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBUserSettings: Codable {
    let userId: UUID
    var catalogCountry: String
    var businessCountry: String
    var dayThresholdStocksAlarm: Int
    var therapyNotificationLevel: String
    var therapySnoozeMinutes: Int
    var manualIntakeRegistration: Bool
    var prescriptionMessageTemplate: String?
    var graceMinutes: Int
    var notifyCaregivers: Bool
    var notifyShared: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case catalogCountry = "catalog_country"
        case businessCountry = "business_country"
        case dayThresholdStocksAlarm = "day_threshold_stocks_alarm"
        case therapyNotificationLevel = "therapy_notification_level"
        case therapySnoozeMinutes = "therapy_snooze_minutes"
        case manualIntakeRegistration = "manual_intake_registration"
        case prescriptionMessageTemplate = "prescription_message_template"
        case graceMinutes = "grace_minutes"
        case notifyCaregivers = "notify_caregivers"
        case notifyShared = "notify_shared"
    }
}

struct SBPerson: Codable, Identifiable {
    var id: UUID
    var ownerUserId: UUID?
    var name: String?
    var surname: String?
    var condition: String?
    var codiceFiscale: String?
    var isAccount: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name
        case surname
        case condition
        case codiceFiscale = "codice_fiscale"
        case isAccount = "is_account"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var fullName: String? {
        [name, surname].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct SBDoctor: Codable, Identifiable {
    var id: UUID
    var ownerUserId: UUID?
    var name: String?
    var surname: String?
    var email: String?
    var phone: String?
    var address: String?
    var specialization: String?
    var scheduleJson: DoctorScheduleDTO?
    var secretaryName: String?
    var secretaryEmail: String?
    var secretaryPhone: String?
    var secretaryScheduleJson: DoctorScheduleDTO?
    var prescriptionMessageTemplate: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name, surname, email, phone, address, specialization
        case scheduleJson = "schedule_json"
        case secretaryName = "secretary_name"
        case secretaryEmail = "secretary_email"
        case secretaryPhone = "secretary_phone"
        case secretaryScheduleJson = "secretary_schedule_json"
        case prescriptionMessageTemplate = "prescription_message_template"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var fullName: String? {
        [name, surname].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct SBCabinet: Codable, Identifiable {
    var id: UUID
    var ownerUserId: UUID?
    var name: String
    var isShared: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name
        case isShared = "is_shared"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBCabinetMembership: Codable, Identifiable {
    var id: UUID
    var cabinetId: UUID
    var userId: UUID
    var role: String
    var status: String
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case cabinetId = "cabinet_id"
        case userId = "user_id"
        case role, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBTrackedMedicine: Codable, Identifiable {
    var id: UUID
    var ownerUserId: UUID?
    var cabinetId: UUID?
    var catalogCountry: String
    var catalogSource: String
    var catalogProductKey: String
    var catalogFamilyKey: String?
    var name: String
    var principle: String?
    var requiresPrescription: Bool
    var labels: [String]
    var customStockThreshold: Int
    var manualIntakeRegistration: Bool
    var catalogSnapshot: AnyCodable
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case cabinetId = "cabinet_id"
        case catalogCountry = "catalog_country"
        case catalogSource = "catalog_source"
        case catalogProductKey = "catalog_product_key"
        case catalogFamilyKey = "catalog_family_key"
        case name, principle
        case requiresPrescription = "requires_prescription"
        case labels
        case customStockThreshold = "custom_stock_threshold"
        case manualIntakeRegistration = "manual_intake_registration"
        case catalogSnapshot = "catalog_snapshot"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBTrackedPackage: Codable, Identifiable {
    var id: UUID
    var trackedMedicineId: UUID
    var catalogCountry: String
    var catalogSource: String
    var catalogPackageKey: String
    var catalogCode: String?
    var tipologia: String?
    var unitsPerPackage: Int
    var unitValue: Double?
    var unitName: String?
    var volume: String?
    var packageSnapshot: AnyCodable
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case catalogCountry = "catalog_country"
        case catalogSource = "catalog_source"
        case catalogPackageKey = "catalog_package_key"
        case catalogCode = "catalog_code"
        case tipologia
        case unitsPerPackage = "units_per_package"
        case unitValue = "unit_value"
        case unitName = "unit_name"
        case volume
        case packageSnapshot = "package_snapshot"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBMedicineEntry: Codable, Identifiable {
    var id: UUID
    var trackedMedicineId: UUID
    var trackedPackageId: UUID
    var cabinetId: UUID?
    var deadlineMonth: Int?
    var deadlineYear: Int?
    var purchaseOperationId: UUID?
    var reversedByOperationId: UUID?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case cabinetId = "cabinet_id"
        case deadlineMonth = "deadline_month"
        case deadlineYear = "deadline_year"
        case purchaseOperationId = "purchase_operation_id"
        case reversedByOperationId = "reversed_by_operation_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBTherapy: Codable, Identifiable {
    var id: UUID
    var trackedMedicineId: UUID
    var trackedPackageId: UUID
    var medicineEntryId: UUID?
    var personId: UUID
    var doctorId: UUID?
    var startDate: Date
    var rrule: String?
    var importance: String
    var notificationLevel: String
    var notificationsSilenced: Bool
    var snoozeMinutes: Int
    var clinicalRules: AnyCodable
    var condition: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case medicineEntryId = "medicine_entry_id"
        case personId = "person_id"
        case doctorId = "doctor_id"
        case startDate = "start_date"
        case rrule, importance
        case notificationLevel = "notification_level"
        case notificationsSilenced = "notifications_silenced"
        case snoozeMinutes = "snooze_minutes"
        case clinicalRules = "clinical_rules"
        case condition
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBTherapyDose: Codable, Identifiable {
    var id: UUID
    var therapyId: UUID
    var time: String // HH:mm:ss format
    var amount: Double
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case therapyId = "therapy_id"
        case time, amount
        case sortOrder = "sort_order"
    }
}

struct SBStock: Codable, Identifiable {
    var id: UUID
    var trackedMedicineId: UUID
    var trackedPackageId: UUID
    var contextKey: String
    var stockUnits: Int
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case contextKey = "context_key"
        case stockUnits = "stock_units"
        case updatedAt = "updated_at"
    }
}

struct SBActivityLog: Codable, Identifiable {
    var id: UUID
    var ownerUserId: UUID?
    var cabinetId: UUID?
    var trackedMedicineId: UUID
    var trackedPackageId: UUID?
    var therapyId: UUID?
    var operationId: UUID
    var reversalOfOperationId: UUID?
    var type: String
    var timestamp: Date
    var scheduledDueAt: Date?
    var actorUserId: UUID?
    var actorDeviceId: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case cabinetId = "cabinet_id"
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case therapyId = "therapy_id"
        case operationId = "operation_id"
        case reversalOfOperationId = "reversal_of_operation_id"
        case type, timestamp
        case scheduledDueAt = "scheduled_due_at"
        case actorUserId = "actor_user_id"
        case actorDeviceId = "actor_device_id"
        case source
    }
}

struct SBDoseEvent: Codable, Identifiable {
    var id: UUID
    var therapyId: UUID
    var trackedMedicineId: UUID
    var dueAt: Date
    var status: String
    var actorUserId: UUID?
    var actorDeviceId: String?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case therapyId = "therapy_id"
        case trackedMedicineId = "tracked_medicine_id"
        case dueAt = "due_at"
        case status
        case actorUserId = "actor_user_id"
        case actorDeviceId = "actor_device_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SBMonitoringMeasurement: Codable, Identifiable {
    var id: UUID
    var trackedMedicineId: UUID?
    var therapyId: UUID?
    var todoSourceId: String?
    var kind: String
    var doseRelation: String?
    var valuePrimary: Double?
    var valueSecondary: Double?
    var unit: String?
    var measuredAt: Date
    var scheduledAt: Date?
    var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case therapyId = "therapy_id"
        case todoSourceId = "todo_source_id"
        case kind
        case doseRelation = "dose_relation"
        case valuePrimary = "value_primary"
        case valueSecondary = "value_secondary"
        case unit
        case measuredAt = "measured_at"
        case scheduledAt = "scheduled_at"
        case createdAt = "created_at"
    }
}

// MARK: - AnyCodable helper

/// A type-erased Codable wrapper for JSONB columns.
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any = [:]) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            value = [String: Any]()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            let wrapped = dict.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        } else if let arr = value as? [Any] {
            let wrapped = arr.map { AnyCodable($0) }
            try container.encode(wrapped)
        } else if let str = value as? String {
            try container.encode(str)
        } else if let num = value as? Double {
            try container.encode(num)
        } else if let num = value as? Int {
            try container.encode(num)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - String extension

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
