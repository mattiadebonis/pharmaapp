import SwiftUI

struct PrescriptionMessageTemplateSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore

    let doctorId: UUID
    let doctorDisplayName: String
    let onSavedTemplate: (String?) -> Void

    @State private var templateText: String
    @State private var didLoadTemplate = false
    @State private var showValidationAlert = false
    @State private var saveErrorMessage: String?

    private let previewMedicineNames = ["Tachipirina", "Augmentin"]

    init(
        doctorId: UUID,
        doctorDisplayName: String,
        initialTemplate: String?,
        onSavedTemplate: @escaping (String?) -> Void = { _ in }
    ) {
        self.doctorId = doctorId
        self.doctorDisplayName = doctorDisplayName
        self.onSavedTemplate = onSavedTemplate
        _templateText = State(
            initialValue: PrescriptionMessageTemplateRenderer.resolvedTemplate(customTemplate: initialTemplate)
        )
    }

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
        let trimmed = doctorDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
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
        do {
            if let doctor = try appDataStore.provider.settings.doctor(id: doctorId) {
                templateText = PrescriptionMessageTemplateRenderer.resolvedTemplate(
                    customTemplate: doctor.prescriptionMessageTemplate
                )
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
        didLoadTemplate = true
    }

    private func saveTemplate() {
        guard isTemplateValid else {
            showValidationAlert = true
            return
        }

        do {
            try appDataStore.provider.settings.savePrescriptionMessageTemplate(
                doctorId: doctorId,
                template: trimmedTemplate
            )
            let resolvedTemplate = PrescriptionMessageTemplateRenderer.resolvedTemplate(customTemplate: trimmedTemplate)
            let customTemplate = resolvedTemplate == PrescriptionMessageTemplateRenderer.defaultTemplate
                ? nil
                : resolvedTemplate
            onSavedTemplate(customTemplate)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    return NavigationStack {
        PrescriptionMessageTemplateSettingsView(
            doctorId: UUID(),
            doctorDisplayName: "Dott.ssa Rossi",
            initialTemplate: nil
        )
    }
    .environmentObject(
        AppDataStore(
            provider: CoreDataAppDataProvider(
                authGateway: FirebaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
            )
        )
    )
}
