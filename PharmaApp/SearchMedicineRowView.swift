import SwiftUI
import CoreData

struct SearchMedicineRowView: View {
    @ObservedObject var medicine: Medicine
    
    // MARK: - Body
    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            leadingIcon
            VStack(alignment: .leading, spacing: 6) {
                titleLine
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 4)
        .contentShape(Rectangle())
    }
    
    // MARK: - Components
    
    private var titleLine: some View {
        let trimmed = medicine.nome.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Medicinale" : trimmed
        let name = camelCase(base)
        let dosage = primaryPackageDosage
        let quantity = primaryPackageQuantity

        let parts = [name, dosage, quantity].compactMap { $0 }
        let fullTitle = parts.joined(separator: " ")
        
        return Text(fullTitle)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.primary)
            .lineLimit(2)
    }

    private var leadingIcon: some View {
        Image(systemName: "pill")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.blue)
            .frame(width: 22, height: 22, alignment: .center)
    }

    // MARK: - Helpers
    
    private var primaryPackage: Package? {
        // Simple logic: pick the first package (sorted by numero desc if possible or any logical order)
        // Adjust if needed to match MedicineRowView's exact logic
        return medicine.packages.sorted { $0.numero > $1.numero }.first
    }

    private var primaryPackageDosage: String? {
        guard let pkg = primaryPackage else { return nil }
        return packageDosageLabel(pkg)
    }
    
    private var primaryPackageQuantity: String? {
        guard let pkg = primaryPackage else { return nil }
        return packageQuantityLabel(pkg)
    }

    private func packageQuantityLabel(_ pkg: Package) -> String? {
        let typeRaw = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        if pkg.numero > 0 {
            let unitLabel = typeRaw.isEmpty ? "unità" : typeRaw.lowercased()
            return "\(pkg.numero) \(unitLabel)"
        }
        return typeRaw.isEmpty ? nil : typeRaw.capitalized
    }

    private func packageDosageLabel(_ pkg: Package) -> String? {
        guard pkg.valore > 0 else { return nil }
        let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(pkg.valore)" : "\(pkg.valore) \(unit)"
    }
    
    private func camelCase(_ text: String) -> String {
        let lowered = text.lowercased()
        return lowered
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }
}
