//
//  PharmaAppApp.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI

@main
struct PharmaAppApp: App {
    let persistenceController = PersistenceController.shared

    @StateObject var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appViewModel)

        }
    }
}


