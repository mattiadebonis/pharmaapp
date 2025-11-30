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
                Text("Le impostazioni di soglia e registrazione assunzioni ora si configurano per singolo farmaco.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
