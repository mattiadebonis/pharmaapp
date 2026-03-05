import SwiftUI
import CoreData

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject private var auth: AuthViewModel

    @FetchRequest private var doctors: FetchedResults<Doctor>
    @FetchRequest private var persons: FetchedResults<Person>

    @State private var personPendingDeletion: Person?
    @State private var personDeleteErrorMessage: String?

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

        let peopleRequest = Person.extractPersons(includeAccount: true)
        peopleRequest.sortDescriptors = [
            NSSortDescriptor(key: "is_account", ascending: false),
            NSSortDescriptor(key: "nome", ascending: true)
        ]

        _persons = FetchRequest(fetchRequest: peopleRequest)
        _doctors = FetchRequest(fetchRequest: Doctor.extractDoctors())
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
                        if !person.is_account {
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
            AccountPersonService.shared.ensureAccountPerson(in: managedObjectContext)
            AccountPersonService.shared.syncAccountDisplayName(from: auth.user, in: managedObjectContext)
        }
        .onChange(of: auth.user) { user in
            AccountPersonService.shared.syncAccountDisplayName(from: user, in: managedObjectContext)
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

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }

    @ViewBuilder
    private func personLabel(for person: Person) -> some View {
        HStack(spacing: 8) {
            Text(personDisplayName(for: person))
                .foregroundStyle(.primary)

            if person.is_account {
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

    private func doctorDisplayName(for doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Dottore" : full
    }

    private func deletePerson(_ person: Person) {
        let context = person.managedObjectContext ?? managedObjectContext
        do {
            try PersonDeletionService.shared.delete(person, in: context)
        } catch {
            context.rollback()
            personDeleteErrorMessage = error.localizedDescription
            print("Errore nell'eliminazione della persona: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        DataManagementView()
    }
    .environmentObject(AuthViewModel())
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
