//
//  PrescriptionManagementView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on [data corrente].
//

import SwiftUI
import CoreData

struct PrescriptionManagementView: View {
    let medicine: Medicine
    let package: Package
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    
    @StateObject private var viewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Gestione Ricetta per \(medicine.nome ?? "")")
                    .font(.title3)
                    .bold()
                    .padding(.top)
                
                // Se vuoi visualizzare un eventuale stato della ricetta, potresti aggiungere una label qui
                
                // Bottone per richiedere la ricetta
                Button(action: {
                    viewModel.addNewPrescriptionRequest(for: medicine, for: package)
                }) {
                    Label("Richiedi Ricetta", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                // Bottone per registrare una nuova ricetta
                Button(action: {
                    viewModel.addNewPrescription(for: medicine, for: package)
                }) {
                    Label("Registra Ricetta", systemImage: "doc.text.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Gestione Ricetta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}