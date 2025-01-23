//
//  FeedView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 02/01/25.
//

import SwiftUI
import CoreData

struct FeedView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicinesWithTherapiesOrPurchaseLogs())

    var medicines: FetchedResults<Medicine>

    @State private var selectedMedicine: Medicine?
    @State private var dataUpdated = UUID()  // Usato per forzare l'aggiornamento della vista

    init() {
        // Impostazione dell'observer nel contesto di un inizializzatore statico o in un'estensione di ambiente
        _ = Self.setupObserver
    }

    static let setupObserver: () = {
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: .main) { _ in
            // Usare un approccio di aggiornamento che non cattura direttamente `self`
            // Postare una notifica che possa essere ascoltata da SwiftUI per aggiornare la vista
            NotificationCenter.default.post(name: NSNotification.Name("dataDidChange"), object: nil)
        }
    }()

    var body: some View {

        let medicineArray = Array(medicines)
        let sortedByWeight = medicineArray.sorted { $0.weight > $1.weight } 

        VStack {
            ForEach(sortedByWeight) { medicine in
                Button {
                    selectedMedicine = medicine
                } label: {
                    MedicineRowView(medicine: medicine)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("dataDidChange"))) { _ in
            dataUpdated = UUID()
        }
        .id(dataUpdated)
        .sheet(item: $selectedMedicine) { medicine in
            /* TherapyFormView(
                medicine: medicine,
                context: managedObjectContext
                package:
            ) */
        }
    }
}

#Preview {
    FeedView()
}
