//
//  AddDoctorView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//

import SwiftUI

struct AddDoctorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    
    @State private var nome: String = ""
    @State private var specializzazione: String = ""
    @State private var mail: String = ""
    @State private var telefono: String = ""
    @State private var segreteriaNome: String = ""
    @State private var segreteriaMail: String = ""
    @State private var segreteriaTelefono: String = ""
    @State private var schedule: DoctorScheduleDTO = DoctorScheduleDTO()
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome e cognome", text: $nome)
                TextField("Specializzazione", text: $specializzazione)
            }

            Section(header: Text("Contatti dottore")) {
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
            }

            Section(header: Text("Orari dottore")) {
                DoctorScheduleEditor(schedule: $schedule)
            }

            Section(header: Text("Segreteria")) {
                TextField("Nome segreteria", text: $segreteriaNome)
                TextField("Telefono segreteria", text: $segreteriaTelefono)
                    .keyboardType(.phonePad)
                TextField("Email segreteria", text: $segreteriaMail)
                    .keyboardType(.emailAddress)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Aggiungi Dottore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Aggiungi") {
                    addDoctor()
                }
            }
        }
    }
    
    private func addDoctor() {
        do {
            _ = try appDataStore.provider.settings.saveDoctor(
                DoctorWriteInput(
                    id: nil,
                    name: normalizedValue(from: nome),
                    email: normalizedValue(from: mail),
                    phone: normalizedValue(from: telefono),
                    specialization: normalizedValue(from: specializzazione),
                    schedule: schedule,
                    secretaryName: normalizedValue(from: segreteriaNome),
                    secretaryEmail: normalizedValue(from: segreteriaMail),
                    secretaryPhone: normalizedValue(from: segreteriaTelefono),
                    secretarySchedule: DoctorScheduleDTO()
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DoctorScheduleEditor: View {
    @Binding var schedule: DoctorScheduleDTO
    
    var body: some View {
        ForEach(schedule.days.indices, id: \.self) { index in
            let dayBinding = Binding<DoctorScheduleDTO.DaySchedule>(
                get: { schedule.days[index] },
                set: { schedule.days[index] = $0 }
            )
            DisclosureGroup(schedule.days[index].day.displayName) {
                Picker("Modalità", selection: Binding(
                    get: { dayBinding.wrappedValue.mode },
                    set: { newValue in
                        var updated = dayBinding.wrappedValue
                        updated.mode = newValue
                        updated.normalizeForCurrentMode()
                        dayBinding.wrappedValue = updated
                    }
                )) {
                    ForEach(DoctorScheduleDTO.DaySchedule.Mode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                switch dayBinding.wrappedValue.mode {
                case .closed:
                    Text("Giorno chiuso")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .continuous:
                    TimeSlotRow(title: "Orario continuato", slot: binding(for: \.primary, dayBinding: dayBinding))
                case .split:
                    TimeSlotRow(title: "Mattina", slot: binding(for: \.primary, dayBinding: dayBinding))
                    TimeSlotRow(title: "Pomeriggio", slot: binding(for: \.secondary, dayBinding: dayBinding))
                }
            }
            .onAppear {
                var updated = dayBinding.wrappedValue
                updated.normalizeForCurrentMode()
                dayBinding.wrappedValue = updated
            }
        }
    }
    
    private func binding(for keyPath: WritableKeyPath<DoctorScheduleDTO.DaySchedule, DoctorScheduleDTO.TimeSlot>, dayBinding: Binding<DoctorScheduleDTO.DaySchedule>) -> Binding<DoctorScheduleDTO.TimeSlot> {
        Binding(
            get: { dayBinding.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                var updated = dayBinding.wrappedValue
                updated[keyPath: keyPath] = newValue
                dayBinding.wrappedValue = updated
            }
        )
    }
}

struct TimeSlotRow: View {
    let title: String
    @Binding var slot: DoctorScheduleDTO.TimeSlot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
            HStack {
                TextField("Inizio", text: $slot.start)
                    .keyboardType(.numbersAndPunctuation)
                Text("–")
                    .foregroundStyle(.secondary)
                TextField("Fine", text: $slot.end)
                    .keyboardType(.numbersAndPunctuation)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DoctorSecretaryEditorView: View {
    @Binding var mail: String
    @Binding var telefono: String

    var body: some View {
        Form {
            Section(header: Text("Contatti segreteria")) {
                TextField("Telefono segreteria", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email segreteria", text: $mail)
                    .keyboardType(.emailAddress)
            }
        }
        .navigationTitle("Segreteria")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DoctorSchedulePageView: View {
    let title: String
    let sectionTitle: String
    @Binding var schedule: DoctorScheduleDTO

    var body: some View {
        Form {
            Section(header: Text(sectionTitle)) {
                DoctorScheduleEditor(schedule: $schedule)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DoctorProfessionalInfoPageView: View {
    let title: String
    @Binding var email: String
    @Binding var telefono: String

    var body: some View {
        Form {
            Section(header: Text("Contatti professionali")) {
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
