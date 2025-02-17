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
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                // SECTION 1: Impostazioni generali
                Section(header: Text("Opzioni")) {
                    // Assumiamo che esista sempre almeno un Option
                    let option = options.first!
                    
                    Button(action: {
                        option.manual_intake_registration.toggle()
                        saveContext()
                    }) {
                        Text(option.manual_intake_registration ? "Registrazione manuale assunzioni" : "Registrazione automatica assunzioni")
                    }
                    
                    Picker("Soglia giorni allarme scorte", selection: Binding(
                        get: { Int(option.day_threeshold_stocks_alarm) },
                        set: { newValue in
                            option.day_threeshold_stocks_alarm = Int32(newValue)
                            saveContext()
                        }
                    )) {
                        ForEach(1..<31) { day in
                            Text("\(day) giorni").tag(day)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    
                    Text("Soglia attuale: \(option.day_threeshold_stocks_alarm) giorni")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
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
}