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
            }

            Section(header: Text("Codice fiscale")) {
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
        }
        .navigationTitle("Aggiungi Persona")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Aggiungi") {
                    addPerson()
                }
            }
        }
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
        nuovaPersona.condizione = nil
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
