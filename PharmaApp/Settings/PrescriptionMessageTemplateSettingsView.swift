import SwiftUI

struct PrescriptionMessageTemplateSettingsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var doctor: Doctor

    @State private var templateText = ""
    @State private var didLoadTemplate = false
    @State private var showValidationAlert = false
    @State private var saveErrorMessage: String?

    private let previewMedicineNames = ["Tachipirina", "Augmentin"]

    var body: some View {
        Form {
            Section(
                header: Text("Testo del messaggio"),
                footer: Text("Si applica solo ai farmaci che hanno questo medico come prescrittore. Negli altri casi viene usato il template predefinito.")
            ) {
                TextEditor(text: $templateText)
                    .frame(minHeight: 180)
                    .font(.body)

                if !isTemplateValid {
                    Text("Testo non valido: aggiungi entrambi i campi automatici richiesti.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Campi automatici") {
                VStack(spacing: 10) {
                    placeholderButton(
                        title: "Nome del medico",
                        placeholder: PrescriptionMessageTemplateRenderer.doctorPlaceholder
                    )
                    placeholderButton(
                        title: "Farmaci richiesti",
                        placeholder: PrescriptionMessageTemplateRenderer.medicinesPlaceholder
                    )
                }
            }

            Section("Esempio del messaggio") {
                Text(previewMessage)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Section {
                Button("Ripristina testo predefinito") {
                    templateText = PrescriptionMessageTemplateRenderer.defaultTemplate
                }
            }
        }
        .navigationTitle("Messaggio richiesta medicinali")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    saveTemplate()
                }
            }
        }
        .onAppear {
            loadTemplateIfNeeded()
        }
        .alert("Testo non valido", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Inserisci entrambi i campi automatici disponibili prima di salvare.")
        }
        .alert(
            "Errore",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "Errore sconosciuto")
        }
    }

    private var trimmedTemplate: String {
        templateText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTemplateValid: Bool {
        PrescriptionMessageTemplateRenderer.isValidTemplate(trimmedTemplate)
    }

    private var previewDoctorName: String {
        let trimmed = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Dott.ssa Rossi" : trimmed
    }

    private var previewMessage: String {
        guard isTemplateValid else {
            return "L'esempio sarà disponibile quando il testo conterrà entrambi i campi automatici."
        }
        return PrescriptionMessageTemplateRenderer.render(
            template: trimmedTemplate,
            doctorName: previewDoctorName,
            medicineNames: previewMedicineNames
        )
    }

    private func placeholderButton(title: String, placeholder: String) -> some View {
        Button {
            appendPlaceholder(placeholder)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func appendPlaceholder(_ placeholder: String) {
        if templateText.isEmpty {
            templateText = placeholder
            return
        }

        if templateText.hasSuffix(" ") || templateText.hasSuffix("\n") {
            templateText += placeholder
        } else {
            templateText += " \(placeholder)"
        }
    }

    private func loadTemplateIfNeeded() {
        guard !didLoadTemplate else { return }
        templateText = PrescriptionMessageTemplateRenderer.resolvedTemplate(
            customTemplate: doctor.prescription_message_template
        )
        didLoadTemplate = true
    }

    private func saveTemplate() {
        guard isTemplateValid else {
            showValidationAlert = true
            return
        }

        let normalizedTemplate = PrescriptionMessageTemplateRenderer.resolvedTemplate(
            customTemplate: trimmedTemplate
        )
        doctor.prescription_message_template = normalizedTemplate == PrescriptionMessageTemplateRenderer.defaultTemplate
            ? nil
            : normalizedTemplate

        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            managedObjectContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let context = PersistenceController.shared.container.viewContext
    let doctor = Doctor(context: context)
    doctor.id = UUID()
    doctor.nome = "Dott.ssa Rossi"

    return NavigationStack {
        PrescriptionMessageTemplateSettingsView(doctor: doctor)
    }
    .environment(\.managedObjectContext, context)
}
