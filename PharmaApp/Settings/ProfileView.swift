//
//  ProfileView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 05/02/26.
//

import SwiftUI
import CoreData

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var codiceFiscaleStore: CodiceFiscaleStore
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @State private var codiceFiscaleInput: String = ""
    @State private var isScannerPresented = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(header: Text("Account")) {
                if let user = auth.user {
                    HStack {
                        Text("Utente")
                        Spacer()
                        Text(user.displayName)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Provider")
                        Spacer()
                        Text(user.provider == .apple ? "Apple" : "Google")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Nessun account collegato.")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    auth.signOut()
                    dismiss()
                } label: {
                    Text("Esci")
                }
            }

            Section(header: Text("Codice Fiscale")) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Inserisci il Codice Fiscale", text: $codiceFiscaleInput)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        Button("Salva") {
                            saveCodiceFiscale()
                        }
                        .buttonStyle(.borderedProminent)

                        if scannerAvailable {
                            Button("Scansiona tessera") {
                                isScannerPresented = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if let current = codiceFiscaleStore.codiceFiscale {
                        Text("Salvato: \(current)")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.primary)
                    } else {
                        Text("Nessun Codice Fiscale salvato.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if !scannerAvailable {
                        Text("Scanner non disponibile su questo dispositivo. Inserisci manualmente il Codice Fiscale.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .onAppear {
                    if codiceFiscaleInput.isEmpty, let current = codiceFiscaleStore.codiceFiscale {
                        codiceFiscaleInput = current
                    }
                }
            }

            if let option = options.first {
                Section(
                    header: Text("Orari eventi"),
                    footer: Text("Usa questi orari come scorciatoie quando inserisci le dosi.")
                ) {
                    ForEach(EventTimeKind.allCases) { kind in
                        DatePicker(
                            kind.label,
                            selection: timeBinding(for: kind, option: option),
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }

            Section(header: HStack {
                Text("Gestione Dottori")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    NavigationLink {
                        DoctorDetailView(doctor: doctor)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(doctor.nome ?? "")
                                .font(.headline)
                            if let mail = doctor.mail {
                                Text("Email: \(mail)")
                            }
                            if let telefono = doctor.telefono {
                                Text("Telefono: \(telefono)")
                            }
                        }
                    }
                }
            }

            Section(header: HStack {
                Text("Gestione Persone")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(persons) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(person.nome ?? "")
                                .font(.headline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fine") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isScannerPresented) {
            if #available(iOS 16.0, *) {
                CodiceFiscaleScannerSheet { value in
                    codiceFiscaleInput = value
                    saveCodiceFiscale()
                }
            } else {
                Text("Scanner non disponibile.")
            }
        }
    }

    private var scannerAvailable: Bool {
        if #available(iOS 16.0, *) {
            return CodiceFiscaleScannerView.isAvailable
        }
        return false
    }

    private func saveCodiceFiscale() {
        errorMessage = nil
        do {
            try codiceFiscaleStore.save(from: codiceFiscaleInput)
            codiceFiscaleInput = codiceFiscaleStore.codiceFiscale ?? codiceFiscaleInput
        } catch {
            if let localized = error as? LocalizedError, let message = localized.errorDescription {
                errorMessage = message
            } else {
                errorMessage = "Codice Fiscale non valido."
            }
        }
    }

    private func timeBinding(for kind: EventTimeKind, option: Option) -> Binding<Date> {
        let base = Calendar.current.startOfDay(for: Date())
        return Binding(
            get: {
                EventTimeSettings.time(for: option, kind: kind, base: base)
            },
            set: { newValue in
                let normalized = EventTimeSettings.normalizedTime(from: newValue, base: base)
                EventTimeSettings.setOptionTime(normalized, kind: kind, option: option)
                saveContext()
            }
        )
    }

    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AppViewModel())
    .environmentObject(AuthViewModel())
    .environmentObject(CodiceFiscaleStore())
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
