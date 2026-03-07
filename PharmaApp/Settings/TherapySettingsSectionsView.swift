import SwiftUI

struct TherapySettingsSectionsView: View {
    @EnvironmentObject private var appDataStore: AppDataStore
    @State private var preferences = TherapyNotificationSettings(
        level: TherapyNotificationPreferences.defaultLevel,
        snoozeMinutes: TherapyNotificationPreferences.defaultSnoozeMinutes
    )
    @State private var saveErrorMessage: String?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            Section(
                header: Text("Notifiche terapia"),
                footer: Text("In modalità Tipo sveglia puoi interrompere o rimandare dal lock screen.")
            ) {
                Picker(
                    "Livello notifiche",
                    selection: Binding<TherapyNotificationLevel>(
                        get: { preferences.level },
                        set: { newLevel in
                            persistPreferences(level: newLevel, snoozeMinutes: preferences.snoozeMinutes)
                        }
                    )
                ) {
                    Text("Normale").tag(TherapyNotificationLevel.normal)
                    Text("Tipo sveglia").tag(TherapyNotificationLevel.alarm)
                }

                .pickerStyle(.segmented)

                if preferences.level == .alarm {
                    Picker(
                        "Durata rimando",
                        selection: Binding<Int>(
                            get: { preferences.snoozeMinutes },
                            set: { newMinutes in
                                persistPreferences(level: preferences.level, snoozeMinutes: newMinutes)
                            }
                        )
                    ) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                    }
                }
            }

            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .task {
            guard !hasLoaded else { return }
            hasLoaded = true
            reloadPreferences()
        }
        .task {
            for await _ in appDataStore.provider.observe(scopes: [.options]) {
                reloadPreferences()
            }
        }
    }

    private func persistPreferences(level: TherapyNotificationLevel, snoozeMinutes: Int) {
        let normalizedSnooze = TherapyNotificationPreferences.normalizedSnoozeMinutes(rawValue: snoozeMinutes)
        let normalized = TherapyNotificationSettings(level: level, snoozeMinutes: normalizedSnooze)
        preferences = normalized

        do {
            try appDataStore.provider.settings.saveTherapyNotificationPreferences(
                level: normalized.level,
                snoozeMinutes: normalized.snoozeMinutes
            )
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func reloadPreferences() {
        do {
            preferences = try appDataStore.provider.settings.therapyNotificationPreferences()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
