//
//  DoctorDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct DoctorDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var doctor: Doctor

    @State private var nome: String
    @State private var mail: String
    @State private var telefono: String
    @State private var specializzazione: String
    @State private var schedule: DoctorScheduleDTO
    @State private var segreteriaNome: String
    @State private var segreteriaMail: String
    @State private var segreteriaTelefono: String
    @State private var segreteriaSchedule: DoctorScheduleDTO
    @State private var saveErrorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var isDeleting = false

    init(doctor: Doctor) {
        self.doctor = doctor
        _nome = State(initialValue: Self.doctorDisplayName(for: doctor))
        _mail = State(initialValue: doctor.mail ?? "")
        _telefono = State(initialValue: doctor.telefono ?? "")
        _specializzazione = State(initialValue: doctor.specializzazione ?? "")
        _schedule = State(initialValue: doctor.scheduleDTO)
        _segreteriaNome = State(initialValue: doctor.segreteria_nome ?? "")
        _segreteriaMail = State(initialValue: doctor.segreteria_mail ?? "")
        _segreteriaTelefono = State(initialValue: doctor.segreteria_telefono ?? "")
        _segreteriaSchedule = State(initialValue: doctor.secretaryScheduleDTO)
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome e cognome", text: $nome)
            }

            Section(header: Text("Contatti e disponibilità")) {
                NavigationLink {
                    DoctorProfessionalInfoPageView(
                        title: "Contatti e disponibilità",
                        email: $mail,
                        telefono: $telefono,
                        specializzazione: $specializzazione,
                        schedule: $schedule
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apri pagina contatti e disponibilità")
                            .foregroundStyle(.primary)
                        Text(professionalInfoSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Segreteria")) {
                NavigationLink {
                    DoctorSecretaryEditorView(
                        nome: $segreteriaNome,
                        mail: $segreteriaMail,
                        telefono: $segreteriaTelefono,
                        schedule: $segreteriaSchedule
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apri pagina segreteria")
                            .foregroundStyle(.primary)
                        Text(secretarySummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Richieste ricetta")) {
                NavigationLink {
                    PrescriptionMessageTemplateSettingsView(doctor: doctor)
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
        .onChange(of: mail) { _ in
            scheduleAutosave()
        }
        .onChange(of: telefono) { _ in
            scheduleAutosave()
        }
        .onChange(of: specializzazione) { _ in
            scheduleAutosave()
        }
        .onChange(of: schedule) { _ in
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
        .onChange(of: segreteriaSchedule) { _ in
            scheduleAutosave()
        }
        .onDisappear {
            autosaveTask?.cancel()
            saveChanges()
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
        guard !isDeleting, !doctor.isDeleted else { return }

        doctor.nome = normalizedValue(from: nome)
        doctor.cognome = nil
        doctor.mail = normalizedValue(from: mail)
        doctor.telefono = normalizedValue(from: telefono)
        doctor.specializzazione = normalizedValue(from: specializzazione)
        doctor.scheduleDTO = schedule
        doctor.segreteria_nome = normalizedValue(from: segreteriaNome)
        doctor.segreteria_mail = normalizedValue(from: segreteriaMail)
        doctor.segreteria_telefono = normalizedValue(from: segreteriaTelefono)
        doctor.secretaryScheduleDTO = segreteriaSchedule

        let context = doctor.managedObjectContext ?? managedObjectContext
        do {
            if context.hasChanges {
                try context.save()
            }
            saveErrorMessage = nil
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
    }

    private func deleteDoctor() {
        isDeleting = true
        autosaveTask?.cancel()
        let context = doctor.managedObjectContext ?? managedObjectContext
        context.delete(doctor)
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
            print("Errore nell'eliminazione del dottore: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var secretarySummary: String {
        let values = [
            normalizedValue(from: segreteriaNome),
            normalizedValue(from: segreteriaTelefono),
            normalizedValue(from: segreteriaMail)
        ].compactMap { $0 }
        return values.isEmpty ? "Nessuna segreteria configurata" : values.joined(separator: " · ")
    }

    private var scheduleSummary: String {
        let configuredDays = schedule.days.filter { $0.mode != .closed }.count
        return configuredDays == 0 ? "Nessun orario configurato" : "\(configuredDays) giorni configurati"
    }

    private var professionalInfoSummary: String {
        let values = [
            normalizedValue(from: mail),
            normalizedValue(from: telefono),
            normalizedValue(from: specializzazione)
        ].compactMap { $0 }

        let contacts = values.isEmpty ? "Contatti non configurati" : values.joined(separator: " · ")
        return "\(contacts) · \(scheduleSummary)"
    }

    private var prescriptionTemplateStatus: String {
        let template = PrescriptionMessageTemplateRenderer.resolvedTemplate(
            customTemplate: doctor.prescription_message_template
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

    private static func doctorDisplayName(for doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full
    }
}
