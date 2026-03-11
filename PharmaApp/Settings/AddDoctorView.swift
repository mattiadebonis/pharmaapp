//
//  AddDoctorView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 14/02/25.
//

import SwiftUI

struct AddDoctorView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore
    
    @State private var nome: String = ""
    @State private var specializzazione: String = ""
    @State private var mail: String = ""
    @State private var telefono: String = ""
    @State private var segreteriaNome: String = ""
    @State private var segreteriaMail: String = ""
    @State private var segreteriaTelefono: String = ""
    @State private var errorMessage: String?
    
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

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Aggiungi Dottore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Aggiungi") {
                    addDoctor()
                }
            }
        }
    }
    
    private func addDoctor() {
        do {
            _ = try appDataStore.provider.settings.saveDoctor(
                DoctorWriteInput(
                    id: nil,
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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct DoctorSecretaryEditorView: View {
    @Binding var mail: String
    @Binding var telefono: String

    var body: some View {
        Form {
            Section(header: Text("Contatti segreteria")) {
                TextField("Telefono segreteria", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email segreteria", text: $mail)
                    .keyboardType(.emailAddress)
            }
        }
        .navigationTitle("Segreteria")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DoctorProfessionalInfoPageView: View {
    let title: String
    @Binding var email: String
    @Binding var telefono: String

    var body: some View {
        Form {
            Section(header: Text("Contatti professionali")) {
                TextField("Telefono", text: $telefono)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
