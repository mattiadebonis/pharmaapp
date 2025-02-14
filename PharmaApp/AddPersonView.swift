//
//  AddPersonView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//
import SwiftUI

struct AddPersonView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) var dismiss
    
    @State private var nome: String = ""
    @State private var cognome: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
                TextField("Cognome", text: $cognome)
            }
            
            Button("Salva") {
                addPerson()
            }
        }
        .navigationTitle("Aggiungi Persona")
    }
    
    private func addPerson() {
        let nuovaPersona = Person(context: managedObjectContext)
        nuovaPersona.id = UUID()
        nuovaPersona.nome = nome
        nuovaPersona.cognome = cognome
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }
}
