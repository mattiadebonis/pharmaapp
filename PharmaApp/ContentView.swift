//
//  ContentView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

//
//  ContentView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI

struct ContentView: View {

    @Environment(\.managedObjectContext) private var managedObjectContext
    @EnvironmentObject var appViewModel: AppViewModel

    @FetchRequest(fetchRequest: Pharmacie.extractPharmacies(), animation: .default) var pharmacies: FetchedResults<Pharmacie>


    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 1.0)
    let textColor = Color(red: 47/255, green: 47/255, blue: 47/255, opacity: 1.0)
    let pastelPink = Color(red: 248/255, green: 200/255, blue: 220/255, opacity: 1.0)
    
    @State private var isSearchIndexPresented = false
    @State private var isSettingsPresented = false

    init() {
        DataManager.shared.initializeMedicinesDataIfNeeded()
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
    }

    var body: some View {
        ScrollView (){
            VStack(alignment: .leading ) {
                HStack {
                    Spacer()
                    Button(action: { isSettingsPresented = true}) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(pastelBlue)
                            .padding()
                    }
                }
                .padding()
                if appViewModel.suggestNearestPharmacies {
                    Button(action: {
                        appViewModel.isStocksIndexPresented = true
                    }) {
                        Image(systemName: "cross")
                        Text("Rifornisci i farmaci in esaurimento")
                        Spacer()
                    }
                    .bold()
                    .foregroundColor(Color.white)
                    .padding(20)
                    .background(Color.blue)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                TextField("Cerca", text: $appViewModel.query)
                    .padding()
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                if appViewModel.query == "" {
                    FeedView()
                }else{
                    SearchIndex()
                }
            }.padding()
        }   
        .sheet(isPresented: $isSettingsPresented) {
            OptionsView()
                .environment(\.managedObjectContext, managedObjectContext)
        }
        .sheet(isPresented: $appViewModel.isStocksIndexPresented) {
            PharmaciesIndex()
        }
        
    }
}

#Preview {
    ContentView()
}
