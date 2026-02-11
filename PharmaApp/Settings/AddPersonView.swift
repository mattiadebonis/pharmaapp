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
    @State private var codiceFiscale: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
                TextField("Codice fiscale (opzionale)", text: $codiceFiscale)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            
            Button("Salva") {
                addPerson()
            }
        }
        .navigationTitle("Aggiungi Persona")
    }
    
    private func addPerson() {
        let normalizedCF = CodiceFiscaleValidator.normalize(codiceFiscale)
        if !normalizedCF.isEmpty && !CodiceFiscaleValidator.isValid(normalizedCF) {
            errorMessage = "Il Codice Fiscale deve avere 16 caratteri alfanumerici."
            return
        }

        let nuovaPersona = Person(context: managedObjectContext)
        nuovaPersona.id = UUID()
        nuovaPersona.nome = nome
        nuovaPersona.cognome = nil
        nuovaPersona.is_account = false
        nuovaPersona.codice_fiscale = normalizedCF.isEmpty ? nil : normalizedCF
        
        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }
}
