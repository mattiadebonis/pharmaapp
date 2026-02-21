import Foundation

enum PrescriptionMessageTemplateRenderer {
    static let doctorPlaceholder = "{medico}"
    static let medicinesPlaceholder = "{medicinali}"

    static let defaultTemplate = """
    Gentile {medico},

    avrei bisogno della ricetta per {medicinali}.

    Potresti inviarla appena possibile? Grazie!
    """

    static func isValidTemplate(_ template: String) -> Bool {
        let normalized = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return normalized.contains(doctorPlaceholder) && normalized.contains(medicinesPlaceholder)
    }

    static func resolvedTemplate(customTemplate: String?) -> String {
        guard let customTemplate else { return defaultTemplate }
        let trimmed = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidTemplate(trimmed) else { return defaultTemplate }
        return trimmed
    }

    static func render(
        template customTemplate: String?,
        doctorName: String,
        medicineNames: [String]
    ) -> String {
        let doctor = normalizedDoctorName(doctorName)
        let medicines = formattedMedicineList(medicineNames)
        let baseTemplate = resolvedTemplate(customTemplate: customTemplate)

        return baseTemplate
            .replacingOccurrences(of: doctorPlaceholder, with: doctor)
            .replacingOccurrences(of: medicinesPlaceholder, with: medicines)
    }

    static func normalizedDoctorName(_ doctorName: String) -> String {
        let trimmed = doctorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Dottore" : trimmed
    }

    static func formattedMedicineList(_ medicineNames: [String]) -> String {
        let normalized = medicineNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else { return "il medicinale indicato" }
        if normalized.count == 1 {
            return normalized[0]
        }
        return normalized.joined(separator: ", ")
    }
}
