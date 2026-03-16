import Foundation

// MARK: - Bootstrap Response

/// Top-level response from GET /v1/bootstrap
struct FastAPIBootstrapResponse: Codable {
    let profile: FastAPIProfile
    let settings: FastAPIUserSettings
    let people: [FastAPIPerson]
    let doctors: [FastAPIDoctor]
    let cabinets: [FastAPICabinet]
    let cabinetMemberships: [FastAPICabinetMembership]
    let trackedMedicines: [FastAPITrackedMedicine]
    let trackedPackages: [FastAPITrackedPackage]
    let medicineEntries: [FastAPIMedicineEntry]
    let therapies: [FastAPITherapyWithDoses]
    let stocks: [FastAPIStock]
    let activityLogs: [FastAPIActivityLog]
    let doseEvents: [FastAPIDoseEvent]
    let monitoringMeasurements: [FastAPIMonitoringMeasurement]
    let customFilters: [FastAPICustomFilter]
    let notificationLocks: [FastAPINotificationLock]

    enum CodingKeys: String, CodingKey {
        case profile, settings, people, doctors, cabinets
        case cabinetMemberships = "cabinet_memberships"
        case trackedMedicines = "tracked_medicines"
        case trackedPackages = "tracked_packages"
        case medicineEntries = "medicine_entries"
        case therapies, stocks
        case activityLogs = "activity_logs"
        case doseEvents = "dose_events"
        case monitoringMeasurements = "monitoring_measurements"
        case customFilters = "custom_filters"
        case notificationLocks = "notification_locks"
    }
}

// MARK: - Profile & Settings

struct FastAPIProfile: Codable {
    let id: UUID
    let displayName: String?
    let photoUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case photoUrl = "photo_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FastAPIUserSettings: Codable {
    let userId: UUID
    let catalogCountry: String
    let businessCountry: String
    let dayThresholdStocksAlarm: Int
    let therapyNotificationLevel: String
    let therapySnoozeMinutes: Int
    let manualIntakeRegistration: Bool
    let prescriptionMessageTemplate: String?
    let graceMinutes: Int
    let notifyCaregivers: Bool
    let notifyShared: Bool
    let createdAt: Date
    let updatedAt: Date

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
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - People & Doctors

struct FastAPIPerson: Codable {
    let id: UUID
    let ownerUserId: UUID
    let name: String?
    let surname: String?
    let condition: String?
    let codiceFiscale: String?
    let isAccount: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name, surname, condition
        case codiceFiscale = "codice_fiscale"
        case isAccount = "is_account"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FastAPIDoctor: Codable {
    let id: UUID
    let ownerUserId: UUID
    let name: String?
    let surname: String?
    let email: String?
    let phone: String?
    let address: String?
    let specialization: String?
    let scheduleJson: [String: AnyCodable]?
    let secretaryName: String?
    let secretaryEmail: String?
    let secretaryPhone: String?
    let secretaryScheduleJson: [String: AnyCodable]?
    let prescriptionMessageTemplate: String?
    let createdAt: Date
    let updatedAt: Date

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
}

// MARK: - Cabinets

struct FastAPICabinet: Codable {
    let id: UUID
    let ownerUserId: UUID
    let name: String
    let isShared: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name
        case isShared = "is_shared"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FastAPICabinetMembership: Codable {
    let id: UUID
    let cabinetId: UUID
    let userId: UUID
    let role: String
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cabinetId = "cabinet_id"
        case userId = "user_id"
        case role, status
        case createdAt = "created_at"
    }
}

// MARK: - Medicines

struct FastAPITrackedMedicine: Codable {
    let id: UUID
    let ownerUserId: UUID
    let cabinetId: UUID?
    let catalogProductId: String?
    let catalogCountry: String?
    let displayName: String
    let genericName: String?
    let principle: String?
    let requiresPrescription: Bool
    let labels: [String]?
    let customStockThreshold: Int?
    let imageUrl: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case cabinetId = "cabinet_id"
        case catalogProductId = "catalog_product_id"
        case catalogCountry = "catalog_country"
        case displayName = "display_name"
        case genericName = "generic_name"
        case principle
        case requiresPrescription = "requires_prescription"
        case labels
        case customStockThreshold = "custom_stock_threshold"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FastAPITrackedPackage: Codable {
    let id: UUID
    let trackedMedicineId: UUID
    let catalogPackageId: String?
    let packageLabel: String
    let dosageValue: Double?
    let dosageUnit: String?
    let volume: String?
    let unitsPerPackage: Int
    let formType: String?
    let catalogCode: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case catalogPackageId = "catalog_package_id"
        case packageLabel = "package_label"
        case dosageValue = "dosage_value"
        case dosageUnit = "dosage_unit"
        case volume
        case unitsPerPackage = "units_per_package"
        case formType = "form_type"
        case catalogCode = "catalog_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct FastAPIMedicineEntry: Codable {
    let id: UUID
    let trackedMedicineId: UUID
    let trackedPackageId: UUID
    let cabinetId: UUID?
    let deadlineMonth: Int?
    let deadlineYear: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case cabinetId = "cabinet_id"
        case deadlineMonth = "deadline_month"
        case deadlineYear = "deadline_year"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Therapies

struct FastAPITherapyWithDoses: Codable {
    let id: UUID
    let trackedMedicineId: UUID
    let trackedPackageId: UUID?
    let personId: UUID?
    let prescribingDoctorId: UUID?
    let condition: String?
    let freq: String?
    let interval: Int?
    let until: Date?
    let count: Int?
    let byDay: [String]?
    let cycleOnDays: Int?
    let cycleOffDays: Int?
    let startDate: Date
    let importance: String
    let notificationLevel: String
    let snoozeMinutes: Int
    let manualIntake: Bool
    let notificationsSilenced: Bool
    let clinicalRulesJson: [String: AnyCodable]?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date
    let doses: [FastAPITherapyDose]

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case personId = "person_id"
        case prescribingDoctorId = "prescribing_doctor_id"
        case condition, freq, interval, until, count
        case byDay = "by_day"
        case cycleOnDays = "cycle_on_days"
        case cycleOffDays = "cycle_off_days"
        case startDate = "start_date"
        case importance
        case notificationLevel = "notification_level"
        case snoozeMinutes = "snooze_minutes"
        case manualIntake = "manual_intake"
        case notificationsSilenced = "notifications_silenced"
        case clinicalRulesJson = "clinical_rules_json"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case doses
    }
}

struct FastAPITherapyDose: Codable {
    let id: UUID
    let therapyId: UUID
    let timeOfDay: String
    let amount: Double
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case therapyId = "therapy_id"
        case timeOfDay = "time_of_day"
        case amount
        case sortOrder = "sort_order"
    }
}

// MARK: - Stocks

struct FastAPIStock: Codable {
    let id: UUID
    let trackedMedicineId: UUID
    let trackedPackageId: UUID
    let contextKey: String
    let stockUnits: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case contextKey = "context_key"
        case stockUnits = "stock_units"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Activity Logs

struct FastAPIActivityLog: Codable {
    let id: UUID
    let ownerUserId: UUID
    let trackedMedicineId: UUID?
    let trackedPackageId: UUID?
    let therapyId: UUID?
    let operationId: UUID?
    let reversalOfOperationId: UUID?
    let type: String
    let timestamp: Date
    let scheduledDueAt: Date?
    let actorUserId: UUID?
    let actorDeviceId: String?
    let source: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
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
        case createdAt = "created_at"
    }
}

// MARK: - Dose Events

struct FastAPIDoseEvent: Codable {
    let id: UUID
    let therapyId: UUID
    let trackedMedicineId: UUID?
    let dueAt: Date
    let status: String
    let actorUserId: UUID?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case therapyId = "therapy_id"
        case trackedMedicineId = "tracked_medicine_id"
        case dueAt = "due_at"
        case status
        case actorUserId = "actor_user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Monitoring

struct FastAPIMonitoringMeasurement: Codable {
    let id: UUID
    let trackedMedicineId: UUID?
    let therapyId: UUID?
    let type: String
    let value: Double
    let unit: String?
    let measuredAt: Date
    let scheduledAt: Date?
    let note: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case trackedMedicineId = "tracked_medicine_id"
        case therapyId = "therapy_id"
        case type, value, unit
        case measuredAt = "measured_at"
        case scheduledAt = "scheduled_at"
        case note
        case createdAt = "created_at"
    }
}

// MARK: - Custom Filters

struct FastAPICustomFilter: Codable {
    let id: UUID
    let ownerUserId: UUID
    let name: String
    let query: String
    let position: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerUserId = "owner_user_id"
        case name, query, position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

// MARK: - Notification Locks

struct FastAPINotificationLock: Codable {
    let id: UUID
    let cabinetId: UUID
    let deviceId: String
    let lockedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case cabinetId = "cabinet_id"
        case deviceId = "device_id"
        case lockedAt = "locked_at"
    }
}

// MARK: - Operation Request/Response

struct FastAPIOperationRequest: Codable {
    let operationId: UUID
    let trackedMedicineId: UUID
    let trackedPackageId: UUID?
    let therapyId: UUID?
    let scheduledDueAt: Date?
    let actorDeviceId: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case therapyId = "therapy_id"
        case scheduledDueAt = "scheduled_due_at"
        case actorDeviceId = "actor_device_id"
        case source
    }
}

struct FastAPIOperationResult: Codable {
    let operationId: UUID
    let wasDuplicate: Bool
    let activityLogId: UUID?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case wasDuplicate = "was_duplicate"
        case activityLogId = "activity_log_id"
    }
}

// MARK: - Catalog DTOs

struct FastAPICatalogSearchResult: Codable {
    let country: String
    let productId: String
    let familyId: String?
    let packageId: String
    let displayName: String
    let genericName: String?
    let principle: String?
    let packageLabel: String
    let requiresPrescription: Bool
    let unitsPerPackage: Int
    let dosageValue: Double?
    let dosageUnit: String?
    let volume: String?
    let formType: String?
    let catalogCode: String?

    enum CodingKeys: String, CodingKey {
        case country
        case productId = "product_id"
        case familyId = "family_id"
        case packageId = "package_id"
        case displayName = "display_name"
        case genericName = "generic_name"
        case principle
        case packageLabel = "package_label"
        case requiresPrescription = "requires_prescription"
        case unitsPerPackage = "units_per_package"
        case dosageValue = "dosage_value"
        case dosageUnit = "dosage_unit"
        case volume
        case formType = "form_type"
        case catalogCode = "catalog_code"
    }
}

// MARK: - Paginated Response

struct FastAPIPaginatedLogs: Codable {
    let data: [FastAPIActivityLog]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Write Request Bodies

struct FastAPICreateCabinetRequest: Codable {
    let name: String
    let isShared: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isShared = "is_shared"
    }
}

struct FastAPICreatePersonRequest: Codable {
    let name: String?
    let surname: String?
    let condition: String?
    let codiceFiscale: String?
    let isAccount: Bool

    enum CodingKeys: String, CodingKey {
        case name, surname, condition
        case codiceFiscale = "codice_fiscale"
        case isAccount = "is_account"
    }
}

struct FastAPICreateDoctorRequest: Codable {
    let name: String?
    let surname: String?
    let email: String?
    let phone: String?
    let address: String?
    let specialization: String?
    let scheduleJson: [String: AnyCodable]?
    let secretaryName: String?
    let secretaryEmail: String?
    let secretaryPhone: String?
    let secretaryScheduleJson: [String: AnyCodable]?
    let prescriptionMessageTemplate: String?

    enum CodingKeys: String, CodingKey {
        case name, surname, email, phone, address, specialization
        case scheduleJson = "schedule_json"
        case secretaryName = "secretary_name"
        case secretaryEmail = "secretary_email"
        case secretaryPhone = "secretary_phone"
        case secretaryScheduleJson = "secretary_schedule_json"
        case prescriptionMessageTemplate = "prescription_message_template"
    }
}

struct FastAPICreateCustomFilterRequest: Codable {
    let name: String
    let query: String
}

struct FastAPIUpdateCustomFilterRequest: Codable {
    let name: String
    let query: String
}

struct FastAPIUpdateEntryRequest: Codable {
    let cabinetId: UUID?
    let deadlineMonth: Int?
    let deadlineYear: Int?

    enum CodingKeys: String, CodingKey {
        case cabinetId = "cabinet_id"
        case deadlineMonth = "deadline_month"
        case deadlineYear = "deadline_year"
    }
}

struct FastAPISetLabelsRequest: Codable {
    let labels: [String]
}

struct FastAPISetStockThresholdRequest: Codable {
    let customStockThreshold: Int

    enum CodingKeys: String, CodingKey {
        case customStockThreshold = "custom_stock_threshold"
    }
}

struct FastAPIStockSetRequest: Codable {
    let stockUnits: Int

    enum CodingKeys: String, CodingKey {
        case stockUnits = "stock_units"
    }
}

struct FastAPIMoveCabinetRequest: Codable {
    let cabinetId: UUID?

    enum CodingKeys: String, CodingKey {
        case cabinetId = "cabinet_id"
    }
}

struct FastAPICreateTherapyRequest: Codable {
    let trackedMedicineId: UUID
    let trackedPackageId: UUID?
    let personId: UUID?
    let prescribingDoctorId: UUID?
    let condition: String?
    let freq: String?
    let interval: Int?
    let until: Date?
    let count: Int?
    let byDay: [String]?
    let cycleOnDays: Int?
    let cycleOffDays: Int?
    let startDate: Date
    let importance: String
    let notificationLevel: String
    let snoozeMinutes: Int
    let manualIntake: Bool
    let notificationsSilenced: Bool
    let clinicalRulesJson: String?
    let isActive: Bool
    let doses: [FastAPITherapyDoseInput]

    enum CodingKeys: String, CodingKey {
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case personId = "person_id"
        case prescribingDoctorId = "prescribing_doctor_id"
        case condition, freq, interval, until, count
        case byDay = "by_day"
        case cycleOnDays = "cycle_on_days"
        case cycleOffDays = "cycle_off_days"
        case startDate = "start_date"
        case importance
        case notificationLevel = "notification_level"
        case snoozeMinutes = "snooze_minutes"
        case manualIntake = "manual_intake"
        case notificationsSilenced = "notifications_silenced"
        case clinicalRulesJson = "clinical_rules_json"
        case isActive = "is_active"
        case doses
    }
}

struct FastAPITherapyDoseInput: Codable {
    let timeOfDay: String
    let amount: Double
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case timeOfDay = "time_of_day"
        case amount
        case sortOrder = "sort_order"
    }
}

struct FastAPIUpdateSettingsRequest: Codable {
    let therapyNotificationLevel: String?
    let therapySnoozeMinutes: Int?
    let prescriptionMessageTemplate: String?

    enum CodingKeys: String, CodingKey {
        case therapyNotificationLevel = "therapy_notification_level"
        case therapySnoozeMinutes = "therapy_snooze_minutes"
        case prescriptionMessageTemplate = "prescription_message_template"
    }
}

struct FastAPIUndoOperationRequest: Codable {
    let operationId: UUID
    let reversalOfOperationId: UUID
    let trackedMedicineId: UUID
    let trackedPackageId: UUID?
    let therapyId: UUID?
    let actorDeviceId: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case reversalOfOperationId = "reversal_of_operation_id"
        case trackedMedicineId = "tracked_medicine_id"
        case trackedPackageId = "tracked_package_id"
        case therapyId = "therapy_id"
        case actorDeviceId = "actor_device_id"
        case source
    }
}

// NOTE: AnyCodable is defined in SupabaseDTO.swift and shared across modules.
