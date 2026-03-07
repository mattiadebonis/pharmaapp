//
//  PharmaAppApp.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 09/12/24.
//

import SwiftUI
import UserNotifications


class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  private lazy var notificationActionHandler = NotificationActionHandler()

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
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
    private let appDataProvider: any AppDataProvider
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject var appViewModel = AppViewModel()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var appDataStore: AppDataStore
    @StateObject var authViewModel: AuthViewModel
    @StateObject private var favoritesStore = FavoritesStore()
    @State private var observedRestoreRevision: Int
    @State private var didStartBackupObservation = false

    init() {
        let backupCoordinator = BackupCoordinator(
            persistenceController: PersistenceController.shared
        )
        let appDataProvider = DataProviderFactory.make(
            backupCoordinator: backupCoordinator
        )
        self.appDataProvider = appDataProvider
        AppDataProviderRegistry.shared.provider = appDataProvider
        UserIdentityProvider.shared.configureAuthUserIDProvider {
            appDataProvider.auth.currentUser?.id
        }
        _appDataStore = StateObject(wrappedValue: AppDataStore(provider: appDataProvider))
        _authViewModel = StateObject(
            wrappedValue: AuthViewModel(authGateway: appDataProvider.auth)
        )
        _observedRestoreRevision = State(initialValue: appDataProvider.backup.state.restoreRevision)
    }

    var body: some Scene {
        WindowGroup {
            AuthenticationGateView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(appViewModel)
                .environmentObject(appRouter)
                .environmentObject(appDataStore)
                .environmentObject(authViewModel)
                .environmentObject(favoritesStore)
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
                .task {
                    let context = persistenceController.container.viewContext
                    DataManager.shared.performOneTimeBootstrapIfNeeded()
                    DataManager.shared.migrateManualIntakeDefaultIfNeeded()
                    DataManager.shared.migrateTherapyManualIntakeScopeIfNeeded()
                    DataManager.shared.migrateDeadlineToEntryIfNeeded()
                    UserIdentityProvider.shared.ensureProfile(in: context)
                    AccountPersonService.shared.ensureAccountPerson(in: context)
                    AccountPersonService.shared.migrateLegacyCodiceFiscaleIfNeeded(in: context)
                    syncIdentity(from: authViewModel.user)
                    appRouter.consumePendingRouteIfAny()
                    appDataProvider.backup.start()
                    appDataProvider.notifications.start()
                }
                .task {
                    guard !didStartBackupObservation else { return }
                    didStartBackupObservation = true
                    await observeBackupStateChanges()
                }
        }
    }

    private func syncIdentity(from user: AuthUser?) {
        let context = persistenceController.container.viewContext
        appDataProvider.backup.setAuthenticatedUserID(user?.id)
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
        appDataProvider.notifications.refreshAfterStoreChange(reason: "backup-restore")
        Task { @MainActor in
            await appDataProvider.notifications.refreshCriticalLiveActivity(reason: "backup-restore", now: nil)
        }
    }

    private func observeBackupStateChanges() async {
        for await state in appDataProvider.backup.observeState() {
            guard state.restoreRevision != observedRestoreRevision else { continue }
            let didIncrease = state.restoreRevision > observedRestoreRevision
            observedRestoreRevision = state.restoreRevision
            if didIncrease {
                handleRestoreCompletion()
            }
        }
    }
}
