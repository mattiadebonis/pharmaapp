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
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
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
        nuovaPersona.cognome = nil
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }
}
