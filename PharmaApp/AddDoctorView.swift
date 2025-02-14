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
    @State private var cognome: String = ""
    @State private var mail: String = ""
    @State private var telefono: String = ""
    @State private var indirizzo: String = ""
    @State private var orari: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome", text: $nome)
                TextField("Cognome", text: $cognome)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Indirizzo", text: $indirizzo)
                TextField("Orari", text: $orari)
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
        nuovoDottore.cognome = cognome
        nuovoDottore.mail = mail
        nuovoDottore.telefono = telefono
        nuovoDottore.indirizzo = indirizzo
        nuovoDottore.orari = orari
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
    }
}
