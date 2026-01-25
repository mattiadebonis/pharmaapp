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
    @State private var indirizzo: String = ""
    @State private var schedule = DoctorScheduleDTO()
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome", text: $nome)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Indirizzo", text: $indirizzo)
            }
            
            Section(header: Text("Orari")) {
                DoctorScheduleEditor(schedule: $schedule)
            }
            
            Button("Salva") {
                addDoctor()
            }
        }
        .navigationTitle("Aggiungi Dottore")
    }
    
    private func addDoctor() {
        let nuovoDottore = Doctor(context: managedObjectContext)
        nuovoDottore.id = UUID()
        nuovoDottore.nome = nome
        nuovoDottore.cognome = nil
        nuovoDottore.mail = mail
        nuovoDottore.telefono = telefono
        nuovoDottore.indirizzo = indirizzo
        nuovoDottore.scheduleDTO = schedule
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
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
