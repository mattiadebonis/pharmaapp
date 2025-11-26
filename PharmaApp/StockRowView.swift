//
//  StockRowView.swift
//  PharmaApp
//
//  Created by Mattia De Bonis on 01/01/25.
//

import SwiftUI

struct StockRowView: View {
    
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Log.extractIntakeLogs()) var intakeLogs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Log.extractPurchaseLogs()) var purchaseLogs: FetchedResults<Log>
    @ObservedObject var stockRowViewModel: StockRowViewModel

    var medicine: Medicine

    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    
    var body: some View {

        VStack {
            HStack {
                Button(action:{
                    stockRowViewModel.saveIntakeLog() 
                    stockRowViewModel.calculateRemainingUnits()
                }){
                    Image(systemName: "circle")
                }
                Image(systemName: "cross.vial").foregroundColor(stockRowViewModel.isAvailable ? .green : .red)
                VStack(alignment: .leading) {
                    Text(stockRowViewModel.medicine.nome)

                    if stockRowViewModel.isAvailable {
                        Text("Disponibili: \(stockRowViewModel.remainingUnits)")
                            .foregroundColor(.green)
                    } else {
                        Text("Non disponibile")
                            .foregroundColor(.red)
                    }
                }
                Spacer()
            }
        }
        .padding(20)
        .foregroundColor(textColor)
    }
}
