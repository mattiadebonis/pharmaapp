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
    
    @Environment(\.dismiss) var dismiss
    
    // Campi di testo locali per aggiungere un nuovo dottore
    @State private var nomeDottore: String = ""
    @State private var cognomeDottore: String = ""
    @State private var mailDottore: String = ""
    @State private var telefonoDottore: String = ""
    @State private var indirizzoDottore: String = ""
    @State private var orariDottore: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    // Esempio: le tue impostazioni già esistenti per 'Option'
                    let option = options.first!
                    
                    Button(action: {
                        option.manual_intake_registration.toggle()
                        saveContext()
                    }) {
                        if option.manual_intake_registration {
                            Text("Registrazione manuale assunzioni")
                        } else {
                            Text("Registrazione automatica assunzioni")
                        }
                    }
                    
                    Picker("Soglia giorni allarme scorte", selection: Binding(
                        get: {
                            Int(option.day_threeshold_stocks_alarm)
                        },
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
                
                // SEZIONE PER I DOTTORI
                Section(header: Text("Gestione Dottori")) {
                    // Lista dei dottori esistenti
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
                    
                    // Campi per aggiungere un nuovo dottore
                    TextField("Nome", text: $nomeDottore)
                    TextField("Cognome", text: $cognomeDottore)
                    TextField("Email", text: $mailDottore)
                        .keyboardType(.emailAddress)
                    TextField("Telefono", text: $telefonoDottore)
                        .keyboardType(.phonePad)
                    TextField("Indirizzo", text: $indirizzoDottore)
                    TextField("Orari", text: $orariDottore)
                    
                    Button("Aggiungi Dottore") {
                        aggiungiDottore()
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
    
    private func aggiungiDottore() {
        let nuovoDottore = Doctor(context: managedObjectContext)
        nuovoDottore.id = UUID()
        nuovoDottore.nome = nomeDottore
        nuovoDottore.cognome = cognomeDottore
        nuovoDottore.mail = mailDottore
        nuovoDottore.telefono = telefonoDottore
        nuovoDottore.indirizzo = indirizzoDottore
        nuovoDottore.orari = orariDottore
        
        // Esegui il salvataggio
        saveContext()
        
        // Pulisci i campi di input
        nomeDottore = ""
        cognomeDottore = ""
        mailDottore = ""
        telefonoDottore = ""
        indirizzoDottore = ""
        orariDottore = ""
    }
    
    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio: \(error.localizedDescription)")
        }
    }
}