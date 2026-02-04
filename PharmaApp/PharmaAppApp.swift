//
//  PharmaAppApp.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI
import FirebaseCore
import UserNotifications


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self

    return true
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
}

@main
struct PharmaAppApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var appViewModel = AppViewModel()
    @StateObject var authViewModel = AuthViewModel()
    @StateObject private var favoritesStore = FavoritesStore()
    @StateObject private var codiceFiscaleStore = CodiceFiscaleStore()
    @StateObject private var notificationCoordinator = NotificationCoordinator(
        context: PersistenceController.shared.container.viewContext
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appViewModel)
                .environmentObject(authViewModel)
                .environmentObject(favoritesStore)
                .environmentObject(codiceFiscaleStore)
                .onOpenURL { url in
                    authViewModel.handleOpenURL(url)
                }
                .task {
                    notificationCoordinator.start()
                }
        }
    }
}
