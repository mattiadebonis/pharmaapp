//
//  PersonDetailView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 19/01/26.
//

import SwiftUI

struct PersonDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject var person: Person

    @State private var nome: String

    init(person: Person) {
        self.person = person
        _nome = State(initialValue: person.nome ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("Dettagli Persona")) {
                TextField("Nome", text: $nome)
            }
        }
        .navigationTitle("Dettaglio Persona")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Salva") {
                    saveChanges()
                }
            }
        }
    }

    private func saveChanges() {
        person.nome = normalizedValue(from: nome)
        person.cognome = nil

        do {
            try managedObjectContext.save()
        } catch {
            print("Errore nel salvataggio della persona: \(error.localizedDescription)")
        }
    }

    private func normalizedValue(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
