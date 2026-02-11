//
//  DoctorDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct DoctorDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject var doctor: Doctor

    @State private var nome: String
    @State private var mail: String
    @State private var telefono: String
    @State private var indirizzo: String
    @State private var schedule: DoctorScheduleDTO
    @State private var saveErrorMessage: String?

    init(doctor: Doctor) {
        self.doctor = doctor
        _nome = State(initialValue: doctor.nome ?? "")
        _mail = State(initialValue: doctor.mail ?? "")
        _telefono = State(initialValue: doctor.telefono ?? "")
        _indirizzo = State(initialValue: doctor.indirizzo ?? "")
        _schedule = State(initialValue: doctor.scheduleDTO)
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Dottore")) {
                TextField("Nome", text: $nome)
                TextField("Email", text: $mail)
                    .keyboardType(.emailAddress)
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Indirizzo", text: $indirizzo)
            }

            Section(header: Text("Orari")) {
                DoctorScheduleEditor(schedule: $schedule)
            }
        }
        .navigationTitle("Dettaglio Dottore")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    saveChanges()
                }
            }
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
    }

    private func saveChanges() {
        doctor.nome = normalizedValue(from: nome)
        doctor.cognome = nil
        doctor.mail = normalizedValue(from: mail)
        doctor.telefono = normalizedValue(from: telefono)
        doctor.indirizzo = normalizedValue(from: indirizzo)
        doctor.scheduleDTO = schedule

        let context = doctor.managedObjectContext ?? managedObjectContext
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            context.rollback()
            saveErrorMessage = error.localizedDescription
            print("Errore nel salvataggio del dottore: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
