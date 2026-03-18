import SwiftUI

struct NonAccountPersonDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore

    private let personId: UUID

    @State private var nome: String
    @State private var codiceFiscale: String
    @State private var conditions: [String]
    @State private var saveErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isDeleting = false
    @State private var didLoadFromStore = false

    init(person: SettingsPersonRecord) {
        self.personId = person.id
        _nome = State(initialValue: person.name ?? "")
        _codiceFiscale = State(initialValue: person.codiceFiscale ?? "")
        _conditions = State(initialValue: ConditionListFormatter.parsed(from: person.condition))
    }

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

            ConditionsEditorSection(conditions: $conditions)

            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

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
        .navigationTitle("Dettaglio Persona")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: nome) { _ in
            scheduleAutosave()
        }
        .onChange(of: codiceFiscale) { _ in
            scheduleAutosave()
        }
        .onChange(of: conditions) { _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveChanges()
        }
        .onAppear {
            guard !didLoadFromStore else { return }
            didLoadFromStore = true
            reloadPersonFromStore()
        }
        .alert("Errore salvataggio", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "Errore sconosciuto.")
        }
        .alert("Eliminare questa persona?", isPresented: $showDeleteConfirmation) {
            Button("Elimina", role: .destructive) {
                deletePerson()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Le terapie associate verranno riassegnate al tuo account.")
        }
    }

    private func saveChanges() {
        guard !isDeleting else { return }
        let normalizedCF = CodiceFiscaleValidator.normalize(codiceFiscale)
        if !normalizedCF.isEmpty && !CodiceFiscaleValidator.isValid(normalizedCF) {
            saveErrorMessage = "Il Codice Fiscale deve avere 16 caratteri alfanumerici."
            return
        }
        do {
            _ = try appDataStore.provider.settings.savePerson(
                PersonWriteInput(
                    id: personId,
                    name: normalizedValue(from: nome),
                    codiceFiscale: normalizedCF.isEmpty ? nil : normalizedCF,
                    condition: ConditionListFormatter.serialized(from: conditions),
                    isAccount: false
                )
            )
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deletePerson() {
        isDeleting = true
        autosaveTask?.cancel()
        do {
            try appDataStore.provider.settings.deletePerson(id: personId)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func scheduleAutosave() {
        guard !isDeleting else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveChanges()
            }
        }
    }

    private func reloadPersonFromStore() {
        guard !isDeleting else { return }
        do {
            guard let person = try appDataStore.provider.settings.person(id: personId) else { return }
            nome = person.name ?? ""
            codiceFiscale = person.codiceFiscale ?? ""
            conditions = ConditionListFormatter.parsed(from: person.condition)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
