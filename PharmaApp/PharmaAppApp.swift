//
//  PharmaAppApp.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI
import FirebaseCore


class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

    return true
  }
}

@main
struct PharmaAppApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var appViewModel = AppViewModel()
    @StateObject var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appViewModel)
                .environmentObject(authViewModel)
                .onOpenURL { url in
                    authViewModel.handleOpenURL(url)
                }
        }
    }
}


