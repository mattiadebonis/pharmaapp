//
//  OptionsView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import SwiftUI
import CoreData

struct OptionsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>
    
    var body: some View {
        Form {
                // SECTION 1: Impostazioni generali
                Section(header: Text("Opzioni")) {
                    // Assumiamo che esista sempre almeno un Option
                    let option = options.first!
                    // Interruttore più chiaro in una vista non-modale
                    Toggle(isOn: Binding(
                        get: { option.manual_intake_registration },
                        set: { newValue in
                            option.manual_intake_registration = newValue
                            saveContext()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Registrazione manuale assunzioni")
                            Text("Se disattivo, le assunzioni vengono registrate automaticamente.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Sostituisce il WheelPicker con uno stepper più ‘settings‑like’
                    Stepper(value: Binding(
                        get: { Int(option.day_threeshold_stocks_alarm) },
                        set: { newValue in
                            let clamped = min(max(newValue, 1), 30)
                            option.day_threeshold_stocks_alarm = Int32(clamped)
                            saveContext()
                        }
                    ), in: 1...30) {
                        HStack {
                            Text("Soglia allarme scorte")
                            Spacer()
                            Text("\(option.day_threeshold_stocks_alarm) giorni")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // SECTION 2: Gestione Dottori
                Section(header: HStack {
                    Text("Gestione Dottori")
                    Spacer()
                    NavigationLink(destination: AddDoctorView()) {
                        Image(systemName: "plus")
                    }
                }) {
                    ForEach(doctors) { doctor in
                        VStack(alignment: .leading) {
                            Text("\(doctor.nome ?? "") \(doctor.cognome ?? "")")
                                .font(.headline)
                            if let mail = doctor.mail {
                                Text("Email: \(mail)")
                            }
                            if let telefono = doctor.telefono {
                                Text("Telefono: \(telefono)")
                            }
                        }
                    }
                }
                
                // SECTION 3: Gestione Persone
                Section(header: HStack {
                    Text("Gestione Persone")
                    Spacer()
                    NavigationLink(destination: AddPersonView()) {
                        Image(systemName: "plus")
                    }
                }) {
                    ForEach(persons) { person in
                        VStack(alignment: .leading) {
                            Text("\(person.nome ?? "") \(person.cognome ?? "")")
                                .font(.headline)
                        }
                    }
                }
        }
        .navigationTitle("Impostazioni")
    }
    
    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio: \(error.localizedDescription)")
        }
    }
}
