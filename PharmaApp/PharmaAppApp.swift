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
  private lazy var notificationActionHandler = NotificationActionHandler(
    context: PersistenceController.shared.container.viewContext
  )

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self
    registerNotificationCategories()

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

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      defer { completionHandler() }
      await notificationActionHandler.handle(response: response)
    }
  }

  private func registerNotificationCategories() {
    let stopAction = UNNotificationAction(
      identifier: TherapyAlarmNotificationConstants.stopActionIdentifier,
      title: "Stop",
      options: [.destructive]
    )
    let snoozeAction = UNNotificationAction(
      identifier: TherapyAlarmNotificationConstants.snoozeActionIdentifier,
      title: "Rimanda",
      options: []
    )
    let therapyAlarmCategory = UNNotificationCategory(
      identifier: TherapyAlarmNotificationConstants.categoryIdentifier,
      actions: [stopAction, snoozeAction],
      intentIdentifiers: [],
      options: []
    )

    let notificationCenter = UNUserNotificationCenter.current()
    notificationCenter.getNotificationCategories { categories in
      var updated = categories.filter { $0.identifier != therapyAlarmCategory.identifier }
      updated.insert(therapyAlarmCategory)
      notificationCenter.setNotificationCategories(updated)
    }
  }
}

@main
struct PharmaAppApp: App {
    let persistenceController = PersistenceController.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var appViewModel = AppViewModel()
    @StateObject private var appRouter = AppRouter()
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
                .environmentObject(appRouter)
                .environmentObject(authViewModel)
                .environmentObject(favoritesStore)
                .environmentObject(codiceFiscaleStore)
                .onOpenURL { url in
                    authViewModel.handleOpenURL(url)
                }
                .task {
                    UserIdentityProvider.shared.ensureProfile(in: persistenceController.container.viewContext)
                    appRouter.consumePendingRouteIfAny()
                    notificationCoordinator.start()
                }
        }
    }
}
