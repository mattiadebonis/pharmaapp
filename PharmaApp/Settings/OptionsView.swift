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
    @EnvironmentObject private var appVM: AppViewModel
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>
    
    var body: some View {
        Form {
            // SECTION 1: Gestione Dottori
            Section(header: HStack {
                Text("Gestione Dottori")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    NavigationLink {
                        DoctorDetailView(doctor: doctor)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(doctor.nome ?? "")
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
            }
            
            // SECTION 2: Gestione Persone
            Section(header: HStack {
                Text("Gestione Persone")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(persons) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(person.nome ?? "")
                                .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fine") {
                    appVM.isSettingsPresented = false
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
