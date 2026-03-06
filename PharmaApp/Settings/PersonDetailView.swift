//
//  PersonDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct PersonDetailView: View {
    private enum Field: Hashable {
        case nome
        case codiceFiscale
    }

    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject var person: Person
    private let showsLogoutAction: Bool

    @State private var nome: String
    @State private var codiceFiscale: String
    @State private var isScannerPresented = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isDeleting = false
    @FocusState private var focusedField: Field?

    init(person: Person, showsLogoutAction: Bool = true) {
        self.person = person
        self.showsLogoutAction = showsLogoutAction
        _nome = State(initialValue: person.nome ?? "")
        _codiceFiscale = State(initialValue: person.codice_fiscale ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
                    .focused($focusedField, equals: .nome)
            }

            Section(header: Text("Codice fiscale")) {
                TextField("Codice fiscale (opzionale)", text: $codiceFiscale)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .codiceFiscale)

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

            if person.is_account {
                Section(header: Text("Account")) {
                    LabeledContent("Provider", value: providerText)
                    LabeledContent("Nome", value: accountDisplayName)
                    LabeledContent("Stato", value: accountStatusText)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if person.is_account, auth.user != nil, showsLogoutAction {
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Text("Esci")
                    }
                }
            }

            if !person.is_account {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Elimina persona")
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle("Dettaglio Persona")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: nome) { _ in
            scheduleAutosave()
        }
        .onChange(of: codiceFiscale) { _ in
            scheduleAutosave()
        }
        .onChange(of: focusedField) { newValue in
            if newValue != .codiceFiscale {
                scheduleAutosave(immediate: true)
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveChanges(showValidationMessage: false)
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
        .alert("Eliminare questa persona?", isPresented: $showDeleteConfirmation) {
            Button("Elimina", role: .destructive) {
                deletePerson()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Le terapie associate verranno assegnate all'account.")
        }
        .confirmationDialog("Uscire dall'account?", isPresented: $showLogoutConfirmation, titleVisibility: .visible) {
            Button("Esci", role: .destructive) {
                auth.signOut()
                dismiss()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("I dati locali resteranno su questo dispositivo anche dopo l'uscita.")
        }
    }

    private var scannerAvailable: Bool {
        if #available(iOS 16.0, *) {
            return CodiceFiscaleScannerView.isAvailable
        }
        return false
    }

    private var accountDisplayName: String {
        let fallbackName = normalizedValue(from: nome) ?? normalizedValue(from: person.nome ?? "") ?? "Account"
        guard let authUser = auth.user else { return fallbackName }
        return normalizedValue(from: authUser.displayName ?? "") ?? fallbackName
    }

    private var accountStatusText: String {
        auth.user == nil ? "Non connesso" : "Connesso"
    }

    private var providerText: String {
        switch auth.user?.provider {
        case .apple:
            return "Apple"
        case .google:
            return "Google"
        case .none:
            return "Locale"
        }
    }

    private func saveChanges(showValidationMessage: Bool = true) {
        guard !isDeleting, !person.isDeleted else { return }

        let normalizedCF = CodiceFiscaleValidator.normalize(codiceFiscale)
        let canPersistCodiceFiscale = normalizedCF.isEmpty || CodiceFiscaleValidator.isValid(normalizedCF)

        person.nome = normalizedValue(from: nome)
        person.cognome = nil
        person.condizione = nil

        if canPersistCodiceFiscale {
            person.codice_fiscale = normalizedCF.isEmpty ? nil : normalizedCF
            errorMessage = nil
        } else if showValidationMessage {
            errorMessage = "Il Codice Fiscale deve avere 16 caratteri alfanumerici."
        } else {
            errorMessage = nil
        }

        let context = person.managedObjectContext ?? managedObjectContext
        do {
            if context.hasChanges {
                try context.save()
            }
            if canPersistCodiceFiscale {
                errorMessage = nil
            }
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }

    private func deletePerson() {
        isDeleting = true
        autosaveTask?.cancel()
        let context = person.managedObjectContext ?? managedObjectContext
        do {
            try PersonDeletionService.shared.delete(person, in: context)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
            print("Errore nell'eliminazione della persona: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func scheduleAutosave(immediate: Bool = false) {
        guard !isDeleting else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveChanges(showValidationMessage: focusedField != .codiceFiscale)
            }
        }
    }
}
