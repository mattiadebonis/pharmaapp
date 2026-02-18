import SwiftUI
import CoreData

struct GlobalSearchView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>

    @FetchRequest(fetchRequest: Person.extractPersons())
    private var persons: FetchedResults<Person>

    @State private var query: String = ""
    @State private var selectedMedicine: Medicine?
    @State private var selectedDoctor: Doctor?
    @State private var isDoctorDetailPresented = false
    @State private var selectedPerson: Person?
    @State private var isPersonDetailPresented = false
    @State private var isSearchPresented = false
    @State private var pendingCatalogSelection: CatalogSelection?
    @State private var catalogSelection: CatalogSelection?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMedicines: [Medicine] {
        guard !trimmedQuery.isEmpty else { return [] }
        return medicines.filter { med in
            med.nome.localizedCaseInsensitiveContains(trimmedQuery)
            || med.principio_attivo.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var filteredDoctors: [Doctor] {
        guard !trimmedQuery.isEmpty else { return [] }
        return doctors.filter { doc in
            (doc.nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doc.cognome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var filteredPersons: [Person] {
        guard !trimmedQuery.isEmpty else { return [] }
        return persons.filter { person in
            (person.nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (person.cognome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    private var hasResults: Bool {
        !filteredMedicines.isEmpty || !filteredDoctors.isEmpty || !filteredPersons.isEmpty
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                emptyState
            } else if !hasResults {
                noResults
            } else {
                if !filteredMedicines.isEmpty {
                    Section("Farmaci") {
                        ForEach(filteredMedicines) { medicine in
                            medicineRow(medicine)
                        }
                    }
                }
                if !filteredDoctors.isEmpty {
                    Section("Dottori") {
                        ForEach(filteredDoctors) { doctor in
                            doctorRow(doctor)
                        }
                    }
                }
                if !filteredPersons.isEmpty {
                    Section("Persone") {
                        ForEach(filteredPersons) { person in
                            personRow(person)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cerca")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Farmaci, dottori, persone")
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { if !$0 { selectedMedicine = nil } }
        )) {
            if let medicine = selectedMedicine, let package = getPackage(for: medicine) {
                MedicineDetailView(medicine: medicine, package: package)
                    .presentationDetents([.fraction(0.75), .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .navigationDestination(isPresented: $isDoctorDetailPresented) {
            if let doctor = selectedDoctor {
                DoctorDetailView(doctor: doctor)
            }
        }
        .navigationDestination(isPresented: $isPersonDetailPresented) {
            if let person = selectedPerson {
                PersonDetailView(person: person)
            }
        }
        .sheet(isPresented: $isSearchPresented, onDismiss: {
            if let pending = pendingCatalogSelection {
                pendingCatalogSelection = nil
                DispatchQueue.main.async {
                    catalogSelection = pending
                }
            }
        }) {
            NavigationStack {
                CatalogSearchScreen { selection in
                    pendingCatalogSelection = selection
                    isSearchPresented = false
                }
            }
        }
        .sheet(item: $catalogSelection) { selection in
            MedicineWizardView(prefill: selection) {
                catalogSelection = nil
            }
            .environment(\.managedObjectContext, managedObjectContext)
            .presentationDetents([.fraction(0.5), .large])
        }
    }

    // MARK: - Rows

    private func medicineRow(_ medicine: Medicine) -> some View {
        Button {
            selectedMedicine = medicine
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(medicine.nome)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if !medicine.principio_attivo.isEmpty {
                    Text(medicine.principio_attivo)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func doctorRow(_ doctor: Doctor) -> some View {
        Button {
            selectedDoctor = doctor
            isDoctorDetailPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dott. \(doctor.nome ?? "") \(doctor.cognome ?? "")")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let phone = doctor.telefono, !phone.isEmpty {
                    Text(phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func personRow(_ person: Person) -> some View {
        Button {
            selectedPerson = person
            isPersonDetailPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(personDisplayName(for: person))
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let cf = person.codice_fiscale, !cf.isEmpty {
                    Text(cf)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty States

    private var emptyState: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Cerca farmaci, dottori o persone")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isSearchPresented = true
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "vial.viewfinder")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.tint)
                            .frame(width: 52, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scannerizza la scatola del farmaco")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Tocca qui per usare lo scanner e riconoscere automaticamente il farmaco.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scannerizza la scatola del farmaco")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .listRowBackground(Color.clear)
    }

    private var noResults: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Nessun risultato per \"\(trimmedQuery)\"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        return medicine.packages.first
    }
}
