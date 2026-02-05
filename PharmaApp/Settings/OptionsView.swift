//
//  OptionsView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import SwiftUI
import CoreData

struct OptionsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @State private var thresholdInput: String = ""

    var body: some View {
        Form {
            Section(
                header: Text("Soglia scorte e assunzione"),
                footer: Text("Queste impostazioni valgono per tutte le medicine.")
            ) {
                if let option = options.first {
                    let manualBinding = Binding<Bool>(
                        get: { option.manual_intake_registration },
                        set: { newValue in
                            option.manual_intake_registration = newValue
                            applyManualIntakeSetting(newValue)
                            saveContext()
                        }
                    )
                    Toggle(isOn: manualBinding) {
                        HStack(spacing: 12) {
                            Image(systemName: "repeat")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chiedi conferma assunzione")
                                Text("Quando ricevi il promemoria, conferma manualmente l'assunzione.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avvisami quando restano")
                        HStack(spacing: 8) {
                            TextField("Giorni", text: Binding(
                                get: { thresholdInput },
                                set: { newValue in
                                    let sanitized = sanitizeThresholdInput(newValue)
                                    if sanitized != thresholdInput {
                                        thresholdInput = sanitized
                                    }
                                    persistThresholdInput(sanitized, option: option)
                                }
                            ))
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 80)
                            Text("giorni")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onAppear {
                        if thresholdInput.isEmpty {
                            let value = Int(option.day_threeshold_stocks_alarm)
                            thresholdInput = String(value > 0 ? value : 7)
                        }
                    }
                } else {
                    Text("Opzioni non disponibili.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Opzioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fine") {
                    dismiss()
                }
            }
        }
    }

    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio: \(error.localizedDescription)")
        }
    }

    private func sanitizeThresholdInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(2))
    }

    private func persistThresholdInput(_ value: String, option: Option) {
        guard let parsed = Int(value) else { return }
        let clamped = min(max(1, parsed), 60)
        if Int(option.day_threeshold_stocks_alarm) != clamped {
            option.day_threeshold_stocks_alarm = Int32(clamped)
            saveContext()
        }
        if value != String(clamped) {
            thresholdInput = String(clamped)
        }
    }

    private func applyManualIntakeSetting(_ enabled: Bool) {
        let medicineRequest: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        let therapyRequest: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        if let medicines = try? managedObjectContext.fetch(medicineRequest) {
            for medicine in medicines {
                medicine.manual_intake_registration = enabled
            }
        }
        if let therapies = try? managedObjectContext.fetch(therapyRequest) {
            for therapy in therapies {
                therapy.manual_intake_registration = enabled
            }
        }
    }
}

#Preview {
    NavigationStack {
        OptionsView()
    }
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
