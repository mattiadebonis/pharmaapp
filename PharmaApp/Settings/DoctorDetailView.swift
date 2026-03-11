//
//  DoctorDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct DoctorDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    private let doctorId: UUID

    @State private var nome: String
    @State private var specializzazione: String
    @State private var mail: String
    @State private var telefono: String
    @State private var segreteriaNome: String
    @State private var segreteriaMail: String
    @State private var segreteriaTelefono: String
    @State private var saveErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isDeleting = false
    @State private var prescriptionMessageTemplate: String?
    @State private var didLoadFromStore = false

    init(doctor: SettingsDoctorRecord) {
        self.doctorId = doctor.id
        _nome = State(initialValue: doctor.name ?? "")
        _specializzazione = State(initialValue: doctor.specialization ?? "")
        _mail = State(initialValue: doctor.email ?? "")
        _telefono = State(initialValue: doctor.phone ?? "")
        _segreteriaNome = State(initialValue: doctor.secretaryName ?? "")
        _segreteriaMail = State(initialValue: doctor.secretaryEmail ?? "")
        _segreteriaTelefono = State(initialValue: doctor.secretaryPhone ?? "")
        _prescriptionMessageTemplate = State(initialValue: doctor.prescriptionMessageTemplate)
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome e cognome", text: $nome)
                TextField("Specializzazione", text: $specializzazione)
            }

            Section(header: Text("Contatti dottore")) {
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
            }

            Section(header: Text("Segreteria")) {
                TextField("Nome segreteria", text: $segreteriaNome)
                TextField("Telefono segreteria", text: $segreteriaTelefono)
                    .keyboardType(.phonePad)
                TextField("Email segreteria", text: $segreteriaMail)
                    .keyboardType(.emailAddress)
            }

            Section(header: Text("Richieste ricetta")) {
                NavigationLink {
                    PrescriptionMessageTemplateSettingsView(
                        doctorId: doctorId,
                        doctorDisplayName: normalizedValue(from: nome) ?? "Dottore",
                        initialTemplate: prescriptionMessageTemplate
                    ) { updatedTemplate in
                        prescriptionMessageTemplate = updatedTemplate
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personalizza il messaggio di richiesta di medicinali")
                            .foregroundStyle(.primary)
                        Text(prescriptionTemplateStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Elimina dottore")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Dettaglio Dottore")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: nome) { _ in
            scheduleAutosave()
        }
        .onChange(of: specializzazione) { _ in
            scheduleAutosave()
        }
        .onChange(of: mail) { _ in
            scheduleAutosave()
        }
        .onChange(of: telefono) { _ in
            scheduleAutosave()
        }
        .onChange(of: segreteriaNome) { _ in
            scheduleAutosave()
        }
        .onChange(of: segreteriaMail) { _ in
            scheduleAutosave()
        }
        .onChange(of: segreteriaTelefono) { _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveChanges()
        }
        .onAppear {
            guard !didLoadFromStore else { return }
            didLoadFromStore = true
            reloadDoctorFromStore()
        }
        .alert("Errore salvataggio", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    saveErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage ?? "Errore sconosciuto.")
        }
        .alert("Eliminare questo dottore?", isPresented: $showDeleteConfirmation) {
            Button("Elimina", role: .destructive) {
                deleteDoctor()
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Questa azione non può essere annullata.")
        }
    }

    private func saveChanges() {
        guard !isDeleting else { return }
        do {
            _ = try appDataStore.provider.settings.saveDoctor(
                DoctorWriteInput(
                    id: doctorId,
                    name: normalizedValue(from: nome),
                    email: normalizedValue(from: mail),
                    phone: normalizedValue(from: telefono),
                    specialization: normalizedValue(from: specializzazione),
                    schedule: DoctorScheduleDTO(),
                    secretaryName: normalizedValue(from: segreteriaNome),
                    secretaryEmail: normalizedValue(from: segreteriaMail),
                    secretaryPhone: normalizedValue(from: segreteriaTelefono),
                    secretarySchedule: DoctorScheduleDTO()
                )
            )
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
    }

    private func deleteDoctor() {
        isDeleting = true
        autosaveTask?.cancel()
        do {
            try appDataStore.provider.settings.deleteDoctor(id: doctorId)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            print("Errore nell'eliminazione del dottore: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var prescriptionTemplateStatus: String {
        let template = PrescriptionMessageTemplateRenderer.resolvedTemplate(
            customTemplate: prescriptionMessageTemplate
        )
        return template == PrescriptionMessageTemplateRenderer.defaultTemplate
            ? "Template predefinito"
            : "Template personalizzato"
    }

    private func scheduleAutosave() {
        guard !isDeleting else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                saveChanges()
            }
        }
    }

    private func reloadDoctorFromStore() {
        guard !isDeleting else { return }
        do {
            guard let doctor = try appDataStore.provider.settings.doctor(id: doctorId) else { return }
            nome = doctor.name ?? ""
            specializzazione = doctor.specialization ?? ""
            mail = doctor.email ?? ""
            telefono = doctor.phone ?? ""
            segreteriaNome = doctor.secretaryName ?? ""
            segreteriaMail = doctor.secretaryEmail ?? ""
            segreteriaTelefono = doctor.secretaryPhone ?? ""
            prescriptionMessageTemplate = doctor.prescriptionMessageTemplate
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
