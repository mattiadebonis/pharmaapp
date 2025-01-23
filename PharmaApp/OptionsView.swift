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
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    let option = options.first!

                    Button(action:{
                        
                        if option.manual_intake_registration {
                            option.manual_intake_registration = false
                        } else {
                            option.manual_intake_registration = true
                        }
                        
                        saveContext()
                    }){
                        if option.manual_intake_registration {
                            Text("Registrazione manuale assunzioni")
                        } else {
                            Text("Registrazione automatica assunzioni")

                        }
                    }

                    
                }
            }
            .navigationTitle("Impostazioni")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
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
}