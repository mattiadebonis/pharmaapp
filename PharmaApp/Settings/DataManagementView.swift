import SwiftUI

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    @EnvironmentObject private var auth: AuthViewModel

    @State private var doctors: [SettingsDoctorRecord] = []
    @State private var persons: [SettingsPersonRecord] = []
    @State private var account: SettingsPersonRecord?
    @State private var didStartObservation = false
    @State private var errorMessage: String?

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
            Section(header: Label("Account", systemImage: "person.crop.circle")) {
                if let account {
                    NavigationLink {
                        PersonDetailView(person: account)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountDisplayName(account))
                                .foregroundStyle(.primary)
                            Text("Provider, nome e stato account")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Account non disponibile.")
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: HStack {
                Label("Persone", systemImage: "person.2")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                if persons.isEmpty {
                    Text("Nessuna persona aggiunta")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                } else {
                    ForEach(persons) { person in
                        NavigationLink {
                            NonAccountPersonDetailView(person: person)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(personDisplayName(for: person))
                                    .foregroundStyle(.primary)
                                if let condition = person.condition,
                                   !condition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(condition)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
    }

    private func accountDisplayName(_ account: SettingsPersonRecord) -> String {
        let full = (account.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Account" : full
    }

    private func doctorDisplayName(for doctor: SettingsDoctorRecord) -> String {
        let full = (doctor.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Dottore" : full
    }

    private func personDisplayName(for person: SettingsPersonRecord) -> String {
        let full = (person.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Persona" : full
    }

    private func reloadFetchedState() {
        do {
            let allPersons = try appDataStore.provider.settings.listPersons(includeAccount: true)
            account = allPersons.first(where: { $0.isAccount }) ?? allPersons.first
            persons = allPersons.filter { !$0.isAccount }
            doctors = try appDataStore.provider.settings.listDoctors()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
                authGateway: SupabaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
            )
        )
    )
}
