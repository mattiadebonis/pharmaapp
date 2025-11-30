import SwiftUI
import CoreData

/// Dettaglio di un cabinet con elenco dei medicinali contenuti.
struct CabinetDetailView: View {
    let cabinet: Cabinet
    let medicines: [Medicine]
    
    @State private var selectedMedicine: Medicine?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    
    var body: some View {
        List {
            ForEach(medicines, id: \.objectID) { med in
                MedicineRowView(medicine: med)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMedicine = med
                    }
            }
        }
        .listStyle(.insetGrouped)
        .listRowSeparator(.hidden)
        .scrollContentBackground(.hidden)
        .navigationTitle(cabinet.name)
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in if !newValue { selectedMedicine = nil } }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(medicine: medicine, package: package)
                        .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
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
    
    private func getPackage(for medicine: Medicine) -> Package? {
        if let packages = medicine.packages as? Set<Package> {
            return packages.first
        }
        return nil
    }
}
