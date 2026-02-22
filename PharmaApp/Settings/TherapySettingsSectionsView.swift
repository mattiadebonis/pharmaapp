import SwiftUI
import CoreData

struct TherapySettingsSectionsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>

    var body: some View {
        if let option = options.first {
            Section(
                header: Text("Assunzione"),
                footer: Text("Queste impostazioni valgono per tutte le medicine.")
            ) {
                let manualBinding = Binding<Bool>(
                    get: { option.manual_intake_registration },
                    set: { newValue in
                        option.manual_intake_registration = newValue
                        applyManualIntakeSetting(newValue)
                        saveContext()
                    }
                )
                Toggle(isOn: manualBinding) {
                    HStack(spacing: 12) {
                        Image(systemName: "repeat")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Chiedi conferma assunzione")
                            Text("Quando ricevi il promemoria, conferma manualmente l'assunzione.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(
                header: Text("Notifiche terapia"),
                footer: Text("In modalità Tipo sveglia puoi interrompere o rimandare dal lock screen.")
            ) {
                Picker(
                    "Livello notifiche",
                    selection: Binding<TherapyNotificationLevel>(
                        get: {
                            TherapyNotificationPreferences.normalizedLevel(
                                rawValue: option.therapy_notification_level
                            )
                        },
                        set: { newLevel in
                            option.therapy_notification_level = newLevel.rawValue
                            saveContext()
                        }
                    )
                ) {
                    Text("Normale").tag(TherapyNotificationLevel.normal)
                    Text("Tipo sveglia").tag(TherapyNotificationLevel.alarm)
                }
                .pickerStyle(.segmented)

                if TherapyNotificationPreferences.normalizedLevel(
                    rawValue: option.therapy_notification_level
                ) == .alarm {
                    Picker(
                        "Durata rimando",
                        selection: Binding<Int>(
                            get: {
                                TherapyNotificationPreferences.normalizedSnoozeMinutes(
                                    rawValue: Int(option.therapy_snooze_minutes)
                                )
                            },
                            set: { newMinutes in
                                option.therapy_snooze_minutes = Int32(
                                    TherapyNotificationPreferences.normalizedSnoozeMinutes(rawValue: newMinutes)
                                )
                                saveContext()
                            }
                        )
                    ) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                    }
                }
            }
        } else {
            Section {
                Text("Opzioni non disponibili.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio: \(error.localizedDescription)")
        }
    }

    private func applyManualIntakeSetting(_ enabled: Bool) {
        let medicineRequest: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        let therapyRequest: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        if let medicines = try? managedObjectContext.fetch(medicineRequest) {
            for medicine in medicines {
                medicine.manual_intake_registration = enabled
            }
        }
        if let therapies = try? managedObjectContext.fetch(therapyRequest) {
            for therapy in therapies {
                therapy.manual_intake_registration = enabled
            }
        }
    }
}
