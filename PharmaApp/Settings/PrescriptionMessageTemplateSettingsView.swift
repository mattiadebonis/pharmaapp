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
                header: Text("Template messaggio"),
                footer: Text("Il template deve includere entrambi i placeholder: \(PrescriptionMessageTemplateRenderer.doctorPlaceholder) e \(PrescriptionMessageTemplateRenderer.medicinesPlaceholder).")
            ) {
                TextEditor(text: $templateText)
                    .frame(minHeight: 180)
                    .font(.body)

                if !isTemplateValid {
                    Text("Template non valido: inserisci entrambi i placeholder richiesti.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Placeholder disponibili") {
                HStack(spacing: 10) {
                    placeholderButton(PrescriptionMessageTemplateRenderer.doctorPlaceholder)
                    placeholderButton(PrescriptionMessageTemplateRenderer.medicinesPlaceholder)
                }
            }

            Section("Anteprima") {
                Text(previewMessage)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Section {
                Button("Ripristina default") {
                    templateText = PrescriptionMessageTemplateRenderer.defaultTemplate
                }
            }
        }
        .navigationTitle("Messaggio medico")
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
        .alert("Template non valido", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Inserisci entrambi i placeholder \(PrescriptionMessageTemplateRenderer.doctorPlaceholder) e \(PrescriptionMessageTemplateRenderer.medicinesPlaceholder) prima di salvare.")
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
            return "Anteprima non disponibile finché il template non contiene entrambi i placeholder."
        }
        return PrescriptionMessageTemplateRenderer.render(
            template: trimmedTemplate,
            doctorName: previewDoctorName,
            medicineNames: previewMedicineNames
        )
    }

    private func placeholderButton(_ placeholder: String) -> some View {
        Button {
            appendPlaceholder(placeholder)
        } label: {
            Text(placeholder)
                .font(.callout.weight(.semibold))
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
