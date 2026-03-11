import SwiftUI

struct PersonDetailView: View {
    private enum Field: Hashable {
        case nome
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var auth: AuthViewModel
    private let personId: UUID
    private let showsLogoutAction: Bool

    @State private var nome: String
    @State private var errorMessage: String?
    @State private var showLogoutConfirmation = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var didLoadFromStore = false
    @FocusState private var focusedField: Field?

    init(person: SettingsPersonRecord, showsLogoutAction: Bool = true) {
        self.personId = person.id
        self.showsLogoutAction = showsLogoutAction
        _nome = State(initialValue: person.name ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                TextField("Nome", text: $nome)
                    .focused($focusedField, equals: .nome)
            }

            Section(header: Text("Stato account")) {
                LabeledContent("Provider", value: providerText)
                LabeledContent("Nome", value: accountDisplayName)
                LabeledContent("Stato", value: accountStatusText)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if auth.user != nil, showsLogoutAction {
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Text("Esci")
                    }
                }
            }
        }
        .navigationTitle("Dettaglio Account")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: nome) { _ in
            scheduleAutosave()
        }
        .onChange(of: focusedField) { _ in
            scheduleAutosave(immediate: true)
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

    private var accountDisplayName: String {
        let fallbackName = normalizedValue(from: nome) ?? "Account"
        guard let authUser = auth.user else { return fallbackName }
        return normalizedValue(from: authUser.displayName) ?? fallbackName
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

    private func saveChanges() {
        do {
            _ = try appDataStore.provider.settings.savePerson(
                PersonWriteInput(
                    id: personId,
                    name: normalizedValue(from: nome),
                    codiceFiscale: nil,
                    condition: nil,
                    isAccount: true
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func scheduleAutosave(immediate: Bool = false) {
        autosaveTask?.cancel()
        autosaveTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveChanges()
            }
        }
    }

    private func reloadPersonFromStore() {
        do {
            guard let person = try appDataStore.provider.settings.person(id: personId) else { return }
            nome = person.name ?? ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
