import SwiftUI

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var auth: AuthViewModel

    @State private var doctors: [SettingsDoctorRecord] = []
    @State private var persons: [SettingsPersonRecord] = []

    @State private var personPendingDeletion: SettingsPersonRecord?
    @State private var personDeleteErrorMessage: String?
    @State private var didStartObservation = false

    private let navigationTitleText: String
    private let showsBackupLink: Bool
    private let showsDoneButton: Bool

    init(
        navigationTitleText: String = "Dati",
        showsBackupLink: Bool = false,
        showsDoneButton: Bool = false
    ) {
        self.navigationTitleText = navigationTitleText
        self.showsBackupLink = showsBackupLink
        self.showsDoneButton = showsDoneButton
    }

    var body: some View {
        Form {
            Section(header: HStack {
                Label("Persone", systemImage: "person.2.fill")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(persons) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        personLabel(for: person)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !person.isAccount {
                            Button(role: .destructive) {
                                personPendingDeletion = person
                            } label: {
                                Text("Elimina")
                            }
                        }
                    }
                }
            }

            Section(header: HStack {
                Label("Medici", systemImage: "stethoscope")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    NavigationLink {
                        DoctorDetailView(doctor: doctor)
                    } label: {
                        Text(doctorDisplayName(for: doctor))
                            .foregroundStyle(.primary)
                    }
                }
            }

            if showsBackupLink {
                Section(header: Label("Backup", systemImage: "icloud")) {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Backup iCloud", systemImage: "icloud")
                    }
                }
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            reloadFetchedState()
        }
        .onChange(of: auth.user) { _ in
            reloadFetchedState()
        }
        .task {
            guard !didStartObservation else { return }
            didStartObservation = true
            await observeDataChanges()
        }
        .alert(
            "Eliminare questa persona?",
            isPresented: Binding(
                get: { personPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        personPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Elimina", role: .destructive) {
                if let person = personPendingDeletion {
                    deletePerson(person)
                }
                personPendingDeletion = nil
            }
            Button("Annulla", role: .cancel) {
                personPendingDeletion = nil
            }
        } message: {
            Text("Le terapie associate verranno assegnate all'account.")
        }
        .alert("Errore", isPresented: Binding(
            get: { personDeleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    personDeleteErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(personDeleteErrorMessage ?? "Errore sconosciuto.")
        }
    }

    private func personDisplayName(for person: SettingsPersonRecord) -> String {
        let full = (person.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Persona" : full
    }

    @ViewBuilder
    private func personLabel(for person: SettingsPersonRecord) -> some View {
        HStack(spacing: 8) {
            Text(personDisplayName(for: person))
                .foregroundStyle(.primary)

            if person.isAccount {
                Text("Account")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    private func doctorDisplayName(for doctor: SettingsDoctorRecord) -> String {
        let full = (doctor.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Dottore" : full
    }

    private func deletePerson(_ person: SettingsPersonRecord) {
        do {
            try appDataStore.provider.settings.deletePerson(id: person.id)
            reloadFetchedState()
        } catch {
            personDeleteErrorMessage = error.localizedDescription
            print("Errore nell'eliminazione della persona: \(error.localizedDescription)")
        }
    }

    private func reloadFetchedState() {
        do {
            persons = try appDataStore.provider.settings.listPersons(includeAccount: true)
            doctors = try appDataStore.provider.settings.listDoctors()
            personDeleteErrorMessage = nil
        } catch {
            personDeleteErrorMessage = error.localizedDescription
        }
    }

    private func observeDataChanges() async {
        for await _ in appDataStore.provider.observe(scopes: [.people, .doctors]) {
            reloadFetchedState()
        }
    }
}

#Preview {
    NavigationStack {
        DataManagementView()
    }
    .environmentObject(AuthViewModel())
    .environmentObject(
        AppDataStore(
            provider: CoreDataAppDataProvider(
                authGateway: FirebaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
            )
        )
    )
}
