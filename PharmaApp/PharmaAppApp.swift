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
    @StateObject private var backupCoordinator = BackupCoordinator(
        persistenceController: PersistenceController.shared
    )
    @StateObject private var notificationCoordinator = NotificationCoordinator(
        context: PersistenceController.shared.container.viewContext,
        policy: PerformancePolicy.current()
    )

    var body: some Scene {
        WindowGroup {
            AuthenticationGateView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appViewModel)
                .environmentObject(appRouter)
                .environmentObject(authViewModel)
                .environmentObject(favoritesStore)
                .environmentObject(backupCoordinator)
                .onOpenURL { url in
                    Task { @MainActor in
                        if url.scheme == "pharmaapp" {
                            switch url.host {
                            case "scan":
                                appRouter.open(.scan)
                                return
                            case "add":
                                appRouter.open(.addMedicine)
                                return
                            default:
                                break
                            }
                        }
                        let handledLiveActivityAction = await LiveActivityURLActionHandler.shared.handle(url: url)
                        if handledLiveActivityAction {
                            appRouter.consumePendingRouteIfAny()
                            return
                        }
                        authViewModel.handleOpenURL(url)
                    }
                }
                .onChange(of: authViewModel.user) { user in
                    syncIdentity(from: user)
                }
                .onChange(of: backupCoordinator.restoreRevision) { _ in
                    handleRestoreCompletion()
                }
                .task {
                    let context = persistenceController.container.viewContext
                    DataManager.shared.performOneTimeBootstrapIfNeeded()
                    DataManager.shared.migrateManualIntakeDefaultIfNeeded()
                    DataManager.shared.migrateTherapyManualIntakeScopeIfNeeded()
                    UserIdentityProvider.shared.ensureProfile(in: context)
                    AccountPersonService.shared.ensureAccountPerson(in: context)
                    AccountPersonService.shared.migrateLegacyCodiceFiscaleIfNeeded(in: context)
                    syncIdentity(from: authViewModel.user)
                    appRouter.consumePendingRouteIfAny()
                    backupCoordinator.start()
                    notificationCoordinator.start()
                }
        }
    }

    private func syncIdentity(from user: AuthUser?) {
        let context = persistenceController.container.viewContext
        backupCoordinator.setAuthenticatedUserID(user?.id)
        UserIdentityProvider.shared.syncAuthenticatedIdentity(from: user, in: context)
        AccountPersonService.shared.syncAccountDisplayName(from: user, in: context)
    }

    private func handleRestoreCompletion() {
        let context = persistenceController.container.viewContext
        DataManager.shared.initializePharmaciesDataIfNeeded()
        DataManager.shared.initializeOptionsIfEmpty()
        UserIdentityProvider.shared.ensureProfile(in: context, authUser: authViewModel.user)
        AccountPersonService.shared.ensureAccountPerson(in: context)
        UserIdentityProvider.shared.syncAuthenticatedIdentity(from: authViewModel.user, in: context)
        AccountPersonService.shared.syncAccountDisplayName(from: authViewModel.user, in: context)
        notificationCoordinator.refreshAfterStoreChange()
        Task { @MainActor in
            _ = await CriticalDoseLiveActivityCoordinator.shared.refresh(reason: "backup-restore", now: nil)
        }
    }
}
