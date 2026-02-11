import Foundation

enum TherapyNotificationLevel: String, CaseIterable {
    case normal
    case alarm
}

enum TherapyAlarmNotificationConstants {
    static let categoryIdentifier = "therapy_alarm"
    static let stopActionIdentifier = "THERAPY_STOP"
    static let snoozeActionIdentifier = "THERAPY_SNOOZE"
    static let alarmSeriesIdKey = "alarmSeriesId"
    static let alarmIdentifierPrefix = "therapy-alarm"
}

struct TherapyNotificationPreferences: Equatable {
    static let defaultLevel: TherapyNotificationLevel = .normal
    static let defaultSnoozeMinutes = 10
    static let allowedSnoozeMinutes: Set<Int> = [5, 10, 15]

    static let alarmRepeatCount = 6
    static let alarmRepeatIntervalMinutes = 1

    let level: TherapyNotificationLevel
    let snoozeMinutes: Int

    init(option: Option?) {
        self.level = Self.normalizedLevel(rawValue: option?.therapy_notification_level)
        self.snoozeMinutes = Self.normalizedSnoozeMinutes(rawValue: Int(option?.therapy_snooze_minutes ?? 0))
    }

    init(levelRawValue: String?, snoozeMinutesRawValue: Int) {
        self.level = Self.normalizedLevel(rawValue: levelRawValue)
        self.snoozeMinutes = Self.normalizedSnoozeMinutes(rawValue: snoozeMinutesRawValue)
    }

    static func normalizedLevel(rawValue: String?) -> TherapyNotificationLevel {
        guard let rawValue, let level = TherapyNotificationLevel(rawValue: rawValue) else {
            return defaultLevel
        }
        return level
    }

    static func normalizedSnoozeMinutes(rawValue: Int) -> Int {
        guard allowedSnoozeMinutes.contains(rawValue) else {
            return defaultSnoozeMinutes
        }
        return rawValue
    }

    static func alarmIdentifier(seriesId: String, index: Int) -> String {
        "\(TherapyAlarmNotificationConstants.alarmIdentifierPrefix)-\(seriesId)-\(index)"
    }

    static func alarmIdentifiers(seriesId: String) -> [String] {
        (0...alarmRepeatCount).map { index in
            alarmIdentifier(seriesId: seriesId, index: index)
        }
    }

    static func alarmDate(baseDate: Date, index: Int) -> Date {
        baseDate.addingTimeInterval(Double(index * alarmRepeatIntervalMinutes * 60))
    }
}
