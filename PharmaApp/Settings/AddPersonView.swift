//
//  AddPersonView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//
import SwiftUI

struct AddPersonView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    
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

        do {
            _ = try appDataStore.provider.settings.savePerson(
                PersonWriteInput(
                    id: nil,
                    name: normalizedValue(from: nome),
                    codiceFiscale: normalizedCF.isEmpty ? nil : normalizedCF,
                    isAccount: false
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
