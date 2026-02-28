import SwiftUI
import CoreData

struct PrescriptionMessageTemplateSettingsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>

    @State private var templateText = ""
    @State private var didLoadTemplate = false
    @State private var showValidationAlert = false
    @State private var saveErrorMessage: String?

    private let previewDoctorName = "Dott.ssa Rossi"
    private let previewMedicineNames = ["Tachipirina", "Augmentin"]

    var body: some View {
        Form {
            Section(
                header: Text("Testo del messaggio"),
                footer: Text("Inserisci entrambi i campi automatici per completare il messaggio in modo corretto.")
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
        .navigationTitle("Messaggio per la ricetta")
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
            customTemplate: options.first?.prescription_message_template
        )
        didLoadTemplate = true
    }

    private func saveTemplate() {
        guard isTemplateValid else {
            showValidationAlert = true
            return
        }

        let option = ensureOption()
        option.prescription_message_template = trimmedTemplate

        do {
            try managedObjectContext.save()
            dismiss()
        } catch {
            managedObjectContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }

    private func ensureOption() -> Option {
        if let existing = options.first {
            return existing
        }

        guard let optionEntity = NSEntityDescription.entity(forEntityName: "Option", in: managedObjectContext) else {
            fatalError("Entity Option non trovata nel modello Core Data.")
        }
        let newOption = Option(entity: optionEntity, insertInto: managedObjectContext)
        newOption.id = UUID()
        newOption.manual_intake_registration = false
        newOption.day_threeshold_stocks_alarm = 7
        newOption.therapy_notification_level = TherapyNotificationPreferences.defaultLevel.rawValue
        newOption.therapy_snooze_minutes = Int32(TherapyNotificationPreferences.defaultSnoozeMinutes)
        newOption.prescription_message_template = PrescriptionMessageTemplateRenderer.defaultTemplate
        return newOption
    }
}

#Preview {
    NavigationStack {
        PrescriptionMessageTemplateSettingsView()
    }
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
