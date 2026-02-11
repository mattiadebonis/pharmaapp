//
//  PersonDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct PersonDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject var person: Person

    @State private var nome: String
    @State private var codiceFiscale: String
    @State private var isScannerPresented = false
    @State private var errorMessage: String?

    init(person: Person) {
        self.person = person
        _nome = State(initialValue: person.nome ?? "")
        _codiceFiscale = State(initialValue: person.codice_fiscale ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
                TextField("Codice fiscale (opzionale)", text: $codiceFiscale)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                if scannerAvailable {
                    Button("Scansiona tessera sanitaria") {
                        isScannerPresented = true
                    }
                } else {
                    Text("Scanner non disponibile su questo dispositivo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if person.is_account, auth.user != nil {
                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                        dismiss()
                    } label: {
                        Text("Esci")
                    }
                }
            }
        }
        .navigationTitle("Dettaglio Persona")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    saveChanges()
                }
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            if #available(iOS 16.0, *) {
                CodiceFiscaleScannerSheet { value in
                    codiceFiscale = value
                }
            } else {
                Text("Scanner non disponibile.")
            }
        }
    }

    private var scannerAvailable: Bool {
        if #available(iOS 16.0, *) {
            return CodiceFiscaleScannerView.isAvailable
        }
        return false
    }

    private func saveChanges() {
        let normalizedCF = CodiceFiscaleValidator.normalize(codiceFiscale)
        if !normalizedCF.isEmpty && !CodiceFiscaleValidator.isValid(normalizedCF) {
            errorMessage = "Il Codice Fiscale deve avere 16 caratteri alfanumerici."
            return
        }

        errorMessage = nil
        person.nome = normalizedValue(from: nome)
        person.cognome = nil
        person.codice_fiscale = normalizedCF.isEmpty ? nil : normalizedCF

        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
