//
//  AddDoctorView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//

import SwiftUI

struct AddDoctorView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) var dismiss
    
    @State private var nome: String = ""
    @State private var mail: String = ""
    @State private var telefono: String = ""
    @State private var specializzazione: String = ""
    @State private var segreteriaNome: String = ""
    @State private var segreteriaMail: String = ""
    @State private var segreteriaTelefono: String = ""
    @State private var schedule = DoctorScheduleDTO()
    @State private var segreteriaSchedule = DoctorScheduleDTO()
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome e cognome", text: $nome)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Specializzazione", text: $specializzazione)
            }

            Section(header: Text("Orari reperibilità")) {
                NavigationLink {
                    DoctorSchedulePageView(
                        title: "Orari reperibilità",
                        sectionTitle: "Orari reperibilità",
                        schedule: $schedule
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apri pagina orari reperibilità")
                            .foregroundStyle(.primary)
                        Text(scheduleSummary(schedule))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Segreteria")) {
                NavigationLink {
                    DoctorSecretaryEditorView(
                        nome: $segreteriaNome,
                        mail: $segreteriaMail,
                        telefono: $segreteriaTelefono,
                        schedule: $segreteriaSchedule
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apri pagina segreteria")
                            .foregroundStyle(.primary)
                        Text(secretarySummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
        let nuovoDottore = Doctor(context: managedObjectContext)
        nuovoDottore.id = UUID()
        nuovoDottore.nome = normalizedValue(from: nome)
        nuovoDottore.cognome = nil
        nuovoDottore.mail = normalizedValue(from: mail)
        nuovoDottore.telefono = normalizedValue(from: telefono)
        nuovoDottore.specializzazione = normalizedValue(from: specializzazione)
        nuovoDottore.scheduleDTO = schedule
        nuovoDottore.segreteria_nome = normalizedValue(from: segreteriaNome)
        nuovoDottore.segreteria_mail = normalizedValue(from: segreteriaMail)
        nuovoDottore.segreteria_telefono = normalizedValue(from: segreteriaTelefono)
        nuovoDottore.secretaryScheduleDTO = segreteriaSchedule
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var secretarySummary: String {
        let values = [
            normalizedValue(from: segreteriaNome),
            normalizedValue(from: segreteriaTelefono),
            normalizedValue(from: segreteriaMail)
        ].compactMap { $0 }
        return values.isEmpty ? "Nessuna segreteria configurata" : values.joined(separator: " · ")
    }

    private func scheduleSummary(_ schedule: DoctorScheduleDTO) -> String {
        let configuredDays = schedule.days.filter { $0.mode != .closed }.count
        return configuredDays == 0 ? "Nessun orario configurato" : "\(configuredDays) giorni configurati"
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
    @Binding var nome: String
    @Binding var mail: String
    @Binding var telefono: String
    @Binding var schedule: DoctorScheduleDTO

    var body: some View {
        Form {
            Section(header: Text("Contatti segreteria")) {
                TextField("Nome segreteria", text: $nome)
                TextField("Email segreteria", text: $mail)
                    .keyboardType(.emailAddress)
                TextField("Telefono segreteria", text: $telefono)
                    .keyboardType(.phonePad)
            }

            Section(header: Text("Orari segreteria")) {
                DoctorScheduleEditor(schedule: $schedule)
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
