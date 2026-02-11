import Testing
@testable import PharmaApp

struct TherapyNotificationPreferencesTests {
    @Test func normalizesUnknownLevelToNormal() {
        let preferences = TherapyNotificationPreferences(
            levelRawValue: "unsupported",
            snoozeMinutesRawValue: 10
        )
        #expect(preferences.level == .normal)
    }

    @Test func normalizesSnoozeToAllowedValues() {
        let preferences = TherapyNotificationPreferences(
            levelRawValue: "alarm",
            snoozeMinutesRawValue: 9
        )
        #expect(preferences.level == .alarm)
        #expect(preferences.snoozeMinutes == 10)
    }

    @Test func keepsValidSnoozeValues() {
        let validValues = [5, 10, 15]
        for value in validValues {
            let preferences = TherapyNotificationPreferences(
                levelRawValue: "alarm",
                snoozeMinutesRawValue: value
            )
            #expect(preferences.snoozeMinutes == value)
        }
    }
}
