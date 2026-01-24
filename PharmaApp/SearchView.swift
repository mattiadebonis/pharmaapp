import SwiftUI
import CoreData

struct SearchView: View {
    @Environment(\.managedObjectContext) private var moc
    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    @State private var query: String = ""
    @State private var selectedMedicine: Medicine?

    private var filtered: [Medicine] {
        let base = medicines.filter { ($0.medicinePackages?.isEmpty ?? true) }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(base) }
        return base.filter { $0.nome.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        List {
            ForEach(filtered) { medicine in
                row(for: medicine)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Cerca")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca medicine")
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { if !$0 { selectedMedicine = nil } }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(
                        medicine: medicine,
                        package: package
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    VStack(spacing: 12) {
                        Text("Completa i dati del medicinale")
                            .font(.headline)
                        Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
    }

    private func row(for medicine: Medicine) -> some View {
        MedicineRowView(medicine: medicine)
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded {
                selectedMedicine = medicine
            }, including: .gesture
        )
        .gesture(
            LongPressGesture().onEnded { _ in
                selectedMedicine = medicine
                Haptics.impact(.medium)
            }, including: .gesture
        )
        .accessibilityIdentifier("Search_MedicineRow_\(medicine.objectID)")
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if let package = medicine.packages.first {
            return package
        }
        return nil
    }
}

#Preview {
    NavigationStack {
        SearchView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(AppViewModel())
    }
}
