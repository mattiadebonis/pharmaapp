# CLAUDE.md — PharmaApp

This document provides a comprehensive guide to the PharmaApp codebase for AI assistants and developers.

---

## Project Overview

**PharmaApp** is an Italian-language iOS application for personal medication management. Users can track their medicine cabinet (armadio dei farmaci), manage therapies with recurrence schedules, log dose intakes and purchases, receive prescription reminders, and locate nearby pharmacies.

- **Language**: Swift (100%)
- **UI Framework**: SwiftUI (iOS 18+ with `TabView`/`Tab` APIs; no older fallback currently implemented)
- **Persistence**: Core Data (single SQLite store shared with the app group for widgets)
- **Architecture**: Clean Hexagonal (Ports & Adapters) — described in more detail below
- **Deployment target**: iOS 16+
- **App extensions**: Live Activity extension (`PharmaAppLiveActivityExtension`)
- **Tests**: XCTest unit tests (`PharmaAppTests`)

---

## Repository Structure

```
pharmaapp/
├── PharmaApp/                        # Main application target
│   ├── PharmaAppApp.swift            # App entry point (@main), AppDelegate, DI root
│   ├── ContentView.swift             # Root TabView, global navigation handler
│   ├── AppViewModel.swift            # Global UI state (search sheet, pharmacy suggestion)
│   │
│   ├── PharmaCore/                   # Domain layer — pure Swift, no frameworks
│   │   ├── Domain/
│   │   │   ├── DomainEvent.swift     # Immutable event record (Codable, Hashable)
│   │   │   ├── EventType.swift       # Event type enum with undo mapping
│   │   │   └── Identifiers.swift     # Typed IDs (MedicineId, TherapyId, PackageId)
│   │   ├── Ports/
│   │   │   ├── EventStore.swift      # Protocol: append/fetch domain events
│   │   │   └── Clock.swift           # Protocol: current time abstraction
│   │   ├── UseCases/
│   │   │   ├── RecordIntakeUseCase.swift
│   │   │   ├── RecordPurchaseUseCase.swift
│   │   │   ├── RecordPrescriptionReceivedUseCase.swift
│   │   │   ├── RequestPrescriptionUseCase.swift
│   │   │   └── UndoActionUseCase.swift
│   │   ├── ReadModel/Today/
│   │   │   ├── TodayStateBuilder.swift   # Pure function: builds TodayState from snapshots
│   │   │   ├── TodayModels.swift         # TodayState, TodayTodoItem, TodayTodoCategory, etc.
│   │   │   ├── TodayInputModels.swift    # MedicineSnapshot, TherapySnapshot, OptionSnapshot
│   │   │   ├── TodayRecurrenceService.swift
│   │   │   └── TodayClinicalContextBuilder.swift
│   │   └── Errors/
│   │       └── PharmaError.swift
│   │
│   ├── PharmaData/                   # Infra layer — Core Data adapters
│   │   ├── CoreDataEventStore.swift  # Implements EventStore
│   │   └── Today/
│   │       ├── CoreDataTodaySnapshotBuilder.swift  # Maps CD objects → snapshots
│   │       └── CoreDataTodayStateProvider.swift    # Drives TodayStateBuilder
│   │
│   ├── Data/                         # Core Data model classes & helpers
│   │   ├── Medicine.swift, Therapy.swift, Dose.swift, Package.swift
│   │   ├── Todo.swift, Log.swift, Stock.swift
│   │   ├── Pharmacie.swift, OpeningTime.swift
│   │   ├── Person.swift, Doctor.swift, Cabinet.swift
│   │   ├── Option.swift              # User preferences (NSManagedObject)
│   │   ├── UserProfile.swift
│   │   └── DataManager.swift         # JSON bootstrap loader (medicines + pharmacies)
│   │
│   ├── Feature/                      # Feature modules (SwiftUI views + ViewModels)
│   │   ├── Today/                    # "Oggi" tab — daily todo list
│   │   │   ├── TodayView.swift
│   │   │   ├── TodayViewModel.swift
│   │   │   ├── TodayTodoEngine.swift
│   │   │   ├── TodayTodoRowView.swift
│   │   │   ├── TodayFormatters.swift
│   │   │   └── TodayState.swift
│   │   ├── Upcoming/                 # "Prossime" future doses view
│   │   ├── Medicines/                # Medicine cabinet browser
│   │   │   ├── Cabinet/              # CabinetView, CabinetViewModel, CabinetDetailView
│   │   │   └── Medicine/             # MedicineDetailView, TherapyFormView, TherapyFormViewModel
│   │   ├── Adherence/                # Statistics / adherence dashboard
│   │   ├── Pharmacy/                 # Pharmacy cards, codice fiscale fullscreen
│   │   ├── Search/                   # Global search
│   │   └── Registry/                 # Log registry view
│   │
│   ├── Services/                     # Application-layer services
│   │   ├── RecurrenceRule/
│   │   │   ├── RecurrenceRule.swift  # Custom iCal-like RRULE struct
│   │   │   ├── RecurrenceService.swift
│   │   │   └── RecurrenceManager.swift
│   │   ├── MedicineActionService.swift
│   │   ├── MedicineStockService.swift
│   │   ├── TodoBuilderService.swift
│   │   ├── NotificationScheduler.swift (via Notifications/)
│   │   ├── SectionBuilder.swift
│   │   ├── DoseEventGenerator.swift
│   │   ├── PdfReportBuilder.swift
│   │   └── AccountPersonService.swift
│   │
│   ├── Notifications/                # Local notification scheduling
│   │   ├── NotificationCoordinator.swift
│   │   ├── NotificationPlanner.swift
│   │   ├── NotificationScheduler.swift
│   │   ├── NotificationActionHandler.swift
│   │   ├── AutoIntakeProcessor.swift
│   │   └── TherapyNotificationPreferences.swift
│   │
│   ├── LiveActivity/                 # Critical-dose Live Activity (iOS 16+)
│   │   ├── CriticalDoseLiveActivityCoordinator.swift
│   │   ├── CriticalDoseLiveActivityPlanner.swift
│   │   ├── CriticalDoseLiveActivityClient.swift
│   │   ├── CriticalDoseReminderScheduler.swift
│   │   ├── CriticalDoseActionService.swift
│   │   └── CriticalDoseSnoozeStore.swift
│   │
│   ├── LiveActivities/               # Refill Live Activity (pharmacy proximity)
│   │   ├── RefillLiveActivityCoordinator.swift
│   │   ├── RefillGeofenceManager.swift
│   │   ├── RefillLiveActivityClient.swift
│   │   └── RefillActivityStateStore.swift
│   │
│   ├── Intents/                      # Siri App Intents (iOS 16 AppIntents framework)
│   │   ├── PharmaAppShortcutsProvider.swift
│   │   ├── MarkMedicineTakenIntent.swift
│   │   ├── MarkMedicinePurchasedIntent.swift
│   │   ├── WhatShouldITakeNowIntent.swift
│   │   ├── WhatShouldIBuyIntent.swift
│   │   ├── DidITakeEverythingTodayIntent.swift
│   │   ├── ShowCodiceFiscaleIntent.swift
│   │   ├── NavigateToPharmacyIntent.swift
│   │   ├── OpenPurchaseListIntent.swift
│   │   ├── MarkPrescriptionReceivedIntent.swift
│   │   ├── LiveActivityMarkTakenIntent.swift
│   │   └── LiveActivityRemindLaterIntent.swift
│   │
│   ├── Auth/                         # Authentication (Apple Sign-In + Google Sign-In)
│   │   ├── AuthViewModel.swift
│   │   ├── AuthenticationGateView.swift
│   │   ├── LoginView.swift
│   │   └── AuthModels.swift
│   │
│   ├── Navigation/                   # Deep-link routing
│   │   ├── AppRoute.swift            # AppTabRoute enum, AppRoute enum
│   │   ├── AppRouter.swift           # ObservableObject: selectedTab, pendingRoute
│   │   └── PendingAppRouteStore.swift
│   │
│   ├── Settings/                     # Settings screens (persons, doctors, options)
│   │
│   ├── Speech/                       # SpeechRecognizer for voice input
│   │
│   ├── Utils/                        # Shared utilities
│   │   ├── CodiceFiscaleValidator.swift
│   │   ├── MedicineInputParser.swift
│   │   ├── TherapyDescriptionParser.swift
│   │   ├── KeychainClient.swift
│   │   ├── FavoritesStore.swift
│   │   ├── Haptics.swift
│   │   └── View+Availability.swift   # iOS version guard helpers
│   │
│   ├── Persistence.swift             # PersistenceController (Core Data stack)
│   ├── ClinicalRules.swift           # Prescription / clinical business rules
│   └── PharmaciesIndex.swift / SearchIndex.swift
│
├── PharmaAppLiveActivityExtension/   # Live Activity widget extension
│   ├── CriticalDoseLiveActivityWidget.swift
│   ├── RefillLiveActivityWidget.swift
│   ├── PharmaAppLiveActivityBundle.swift
│   └── LiveActivityActionURLBuilder.swift
│
├── PharmaAppTests/                   # XCTest unit tests (30 files)
│
├── PharmaApp.xcodeproj/              # Xcode project
│   └── project.xcworkspace/xcshareddata/swiftpm/Package.resolved
│
└── GoogleService-Info.plist          # Firebase configuration (do not commit secrets)
```

---

## Architecture

### Hexagonal (Clean) Architecture

The project is explicitly documented in the git history as following "Clean Hex" (Clean Hexagonal Architecture). The layering is:

```
┌─────────────────────────────────────────────────────┐
│  UI Layer (SwiftUI Views + ViewModels)               │
│  Feature/, Settings/, Auth/, Navigation/             │
├─────────────────────────────────────────────────────┤
│  Application Services                               │
│  Services/, Notifications/, Intents/, LiveActivity/ │
├─────────────────────────────────────────────────────┤
│  Domain / PharmaCore (pure Swift, no frameworks)    │
│  UseCases/, Domain/, Ports/, ReadModel/             │
├─────────────────────────────────────────────────────┤
│  Infrastructure / PharmaData                        │
│  CoreDataEventStore, CoreDataTodaySnapshotBuilder   │
└─────────────────────────────────────────────────────┘
```

**Key rules:**
- `PharmaCore/` has zero framework imports — only `Foundation`. Never add UIKit/SwiftUI/CoreData here.
- Domain events are immutable value types (`DomainEvent` struct, `EventType` enum).
- Use cases depend only on protocols (`EventStore`, `Clock`) — never on concrete Core Data types.
- `PharmaData/` is the only layer that knows about `NSManagedObject`.

### Event Sourcing (partial)

Dose intakes, purchases, prescription requests, and their undo events are stored as `DomainEvent` records in the `CoreDataEventStore`. The read model (`TodayStateBuilder`) reconstructs current state from these events plus Core Data entity snapshots. This enables reliable undo via reversal events.

**EventType values:**
- `intakeRecorded` / `intakeUndone`
- `purchaseRecorded` / `purchaseUndone`
- `prescriptionRequested` / `prescriptionRequestUndone`
- `prescriptionReceived` / `prescriptionReceivedUndone`
- `stockAdjusted`

### Read Model

`TodayStateBuilder` is a pure static function factory. It receives `TodayStateInput` (snapshots of medicines, therapies, todos, options) and returns a `TodayState` value with computed todo lists. It is fully testable without Core Data.

---

## Third-Party Dependencies (Swift Package Manager)

Pinned in `Package.resolved`:

| Package | Version | Purpose |
|---|---|---|
| `firebase-ios-sdk` | 12.8.0 | Firebase core (Analytics, App Check) |
| `googlesignin-ios` | 9.1.0 | Google OAuth sign-in |
| `googleappmeasurement` | 12.8.0 | Firebase Analytics |
| `appauth-ios` | 2.0.0 | OAuth 2.0 for Google |
| `gtmappauth` | 5.0.0 | GTM auth utilities |
| `swiftui-code39` | 1.1.0 | Code39 barcode rendering (for codice fiscale card) |
| `abseil-cpp-binary`, `grpc-binary` | — | Firebase Firestore transitive deps |
| `nanopb`, `leveldb`, `promises` | — | Firebase transitive deps |

---

## Data Model (Core Data)

Key entities and their roles:

| Entity | Purpose |
|---|---|
| `Medicine` | Represents a medicinal product from the Italian AIFA catalogue |
| `Package` | A specific package/confezione of a Medicine (units, dosage, AIC code) |
| `MedicinePackage` | User-owned package instance (tracks stock units) |
| `Therapy` | A recurring dose schedule (links Medicine → Person, has RRULE string) |
| `Dose` | A single dose slot within a Therapy (time + amount) |
| `Log` | An event log entry (intake, purchase, prescription) |
| `Todo` | A persisted todo item for the Today view |
| `Stock` | Stock quantity record for a MedicinePackage |
| `Cabinet` | A named medicine cabinet (e.g., per person or room) |
| `CabinetMembership` | Many-to-many Medicine ↔ Cabinet |
| `Person` | A person who takes medicines (family member support) |
| `Doctor` | A doctor contact (for prescription management) |
| `Option` | Single-row user preferences entity |
| `UserProfile` | Local user profile (codice fiscale, name) |
| `Pharmacie` | A pharmacy from the bootstrap JSON |
| `OpeningTime` | Opening hours for a Pharmacie |
| `DoseEventRecord` | Persisted domain event (CoreDataEventStore backing) |
| `NotificationLock` | Prevents duplicate notification scheduling |

The Core Data stack is in `Persistence.swift`:
- Store URL: `PharmaApp.shared.sqlite` (in app container)
- Persistent history tracking enabled (for cross-process change observation)
- `automaticallyMergesChangesFromParent = true`
- Merge policy: `NSMergeByPropertyObjectTrumpMergePolicy`

---

## Recurrence System

Therapies use a custom RRULE-like string format, parsed by `RecurrenceService` / `TodayRecurrenceService`. The `RecurrenceRule` struct supports:

- `freq`: `DAILY`, `WEEKLY`
- `interval`: every N days/weeks
- `byDay`: weekday list (`MO`, `TU`, etc.)
- `count`, `until`: finite schedules
- `exdates`, `rdates`: exclusion/addition overrides
- **Cycle dosing**: `cycleOnDays` / `cycleOffDays` (e.g., 21 on / 7 off for chemotherapy protocols)

`TodayRecurrenceService.allowedEvents(on:rule:startDate:dosesPerDay:calendar:)` is the core scheduler function — returns how many doses are allowed on a given day.

---

## Navigation

Navigation uses a custom routing system (`AppRouter`), not SwiftUI's `NavigationPath`:

- `AppTabRoute` enum: `oggi`, `prossime`, `statistiche`, `medicine`, `profilo`, `search`
- `AppRoute` enum: `today`, `todayPurchaseList`, `pharmacy`, `codiceFiscaleFullscreen`, `profile`
- `AppRouter` (ObservableObject) holds `selectedTab` and `pendingRoute`
- Deep links (from Live Activities, Siri shortcuts, notifications) arrive via `onOpenURL` or `LiveActivityURLActionHandler` and translate to `AppRoute` values

---

## Authentication

Two providers supported via `AuthViewModel`:

1. **Apple Sign-In** (`AuthenticationServices`) — primary, uses `ASAuthorizationAppleIDProvider`
2. **Google Sign-In** (`GoogleSignIn`) — secondary, requires `GoogleService-Info.plist` with `CLIENT_ID`

Auth state is persisted in `UserDefaults` (key: `auth.user`) as JSON-encoded `AuthUser`. Session is restored at launch. Sign-out clears both local storage and the Google SDK session.

---

## Bootstrap & Seed Data

On first launch, `DataManager.performOneTimeBootstrapIfNeeded()` runs once (guarded by `UserDefaults` key `pharmaapp.bootstrap.completed.v1`):

1. Loads `farmacie.json` from the bundle → seeds `Pharmacie` entities
2. Initializes default `Option` row with:
   - `manual_intake_registration = false`
   - `day_threeshold_stocks_alarm = 7`
   - `therapy_notification_level` = default level
   - `therapy_snooze_minutes` = default minutes

The medicines catalogue (`medicinale_example.json`) is loaded on-demand by `DataManager.saveMedicinesToCoreData()` (called from `DataManager.initializeMedicinesDataIfNeeded()` when the Medicine table is empty) and also inline in `ContentView` for the catalog search screen.

---

## Live Activities

Two distinct Live Activity types:

### CriticalDose Live Activity
- Shown when a critical (urgent) dose is due
- Managed by `CriticalDoseLiveActivityCoordinator` (singleton)
- Plans doses via `CriticalDoseLiveActivityPlanner`
- Supports "Mark Taken" and "Remind Later" actions via `AppIntents`
- Snooze state stored in `CriticalDoseSnoozeStore` (UserDefaults)

### Refill Live Activity
- Shown when a medicine refill is needed and user is near a pharmacy
- Managed by `RefillLiveActivityCoordinator` (singleton)
- Geofencing via `RefillGeofenceManager` (CLLocationManager)
- Shows pharmacy opening hours via `RefillPharmacyHoursResolver`

Both coordinators start in `PharmaAppApp.task` and URL actions are routed through `LiveActivityURLActionHandler`.

---

## Siri Intents (AppIntents)

Registered via `PharmaAppShortcutsProvider`. Available intents:

| Intent | Action |
|---|---|
| `MarkMedicineTakenIntent` | Record a dose intake |
| `MarkMedicinePurchasedIntent` | Record a purchase |
| `WhatShouldITakeNowIntent` | Query pending doses |
| `WhatShouldIBuyIntent` | Query purchase list |
| `DidITakeEverythingTodayIntent` | Check today's adherence |
| `ShowCodiceFiscaleIntent` | Display health card (tessera sanitaria) |
| `NavigateToPharmacyIntent` | Open Maps to nearest pharmacy |
| `OpenPurchaseListIntent` | Deep-link to purchase list |
| `MarkPrescriptionReceivedIntent` | Record prescription received |
| `LiveActivityMarkTakenIntent` | Action from Live Activity |
| `LiveActivityRemindLaterIntent` | Snooze from Live Activity |
| `DismissRefillActivityIntent` | Dismiss refill Live Activity |

---

## Notifications

Managed by `NotificationCoordinator`, which starts at launch and orchestrates:

- `NotificationPlanner` — computes which notifications to schedule
- `NotificationScheduler` — submits `UNNotificationRequest` to UNUserNotificationCenter
- `AutoIntakeProcessor` — handles automatic intake registration from notification actions
- `NotificationActionHandler` — processes user interactions (stop/snooze) with `UNNotificationResponse`

Notification categories are registered in `AppDelegate.registerNotificationCategories()`:
- Category: `TherapyAlarmNotificationConstants.categoryIdentifier`
  - Action "Stop" (destructive)
  - Action "Rimanda" (snooze)

---

## Barcode & Camera Features

- **Medicine box scanning**: Uses `VNRecognizeTextRequest` (Vision framework) for OCR, with Italian/English language correction. Matches scanned text against the medicine catalogue using a token-overlap scoring algorithm.
- **Codice fiscale scanning**: `CodiceFiscaleScannerView` — reads the Italian health card barcode (Code39 via `swiftui-code39`).
- **Barcode scanning**: `CodiceFiscaleValidator` validates the 16-character Italian fiscal code checksum.

---

## Testing

Tests live in `PharmaAppTests/` and use XCTest. Test files:

| Test File | What it covers |
|---|---|
| `TodayTodoEngineTests` | Core today todo computation (TodayStateBuilder) |
| `TodayTodoEngineReproductionTests` | Regression scenarios |
| `RecordIntakeUseCaseTests` | Intake use case (with in-memory EventStore) |
| `UndoActionUseCaseTests` | Undo reversal logic |
| `PrescriptionEventsTests` | Prescription workflow events |
| `RecurrenceManagerTests` | RRULE parsing and occurrence calculation |
| `RecurrenceCycleTests` | Cycle (on/off) therapy patterns |
| `NotificationPlannerTests` | Notification scheduling logic |
| `NotificationSchedulerDescriptorTests` | Notification content formatting |
| `NotificationActionHandlerTests` | Notification response handling |
| `CriticalDoseLiveActivityPlannerTests` | Live Activity scheduling |
| `CriticalDoseLiveActivityCoordinatorTests` | Coordinator state transitions |
| `CriticalDoseActionServiceTests` | Action handling for critical dose |
| `CriticalDoseSnoozeStoreTests` | Snooze persistence |
| `RefillPurchaseSummaryProviderTests` | Refill summary generation |
| `RefillPharmacyHoursResolverTests` | Pharmacy hours resolution |
| `RefillActivityStateStoreTests` | Refill activity state persistence |
| `RefillIntentTests` | Refill intent actions |
| `SiriIntentQueryTests` | Siri query intents |
| `SiriIntentActionTests` | Siri action intents |
| `LiveActivityIntentTests` | Live Activity intent actions |
| `SectionBuilderTests` | Medicine section categorization |
| `MedicineCommentServiceTests` | Comment service logic |
| `CodiceFiscaleValidatorTests` | Codice fiscale checksum |
| `AppRouterRouteStoreTests` | Navigation route store |
| `OperationIdProviderTests` | Operation ID deduplication |
| `TestCoreDataFactory` | In-memory Core Data setup for tests |

**To run tests**: Open `PharmaApp.xcodeproj` in Xcode → select the `PharmaAppTests` scheme → ⌘U. There is no command-line build script.

---

## Key Conventions

### Swift Style

- **MVVM** for feature screens: `*View.swift` (SwiftUI View) + `*ViewModel.swift` (`ObservableObject`)
- `@StateObject` for view-owned VMs; `@EnvironmentObject` for shared app-level objects
- Use `Task { @MainActor in }` for async operations that update UI
- Availability guards: use `View+Availability.swift` helpers and `if #available(iOS 18.0, *)` blocks
- CoreData objects accessed only through `@Environment(\.managedObjectContext)`

### Domain Layer Rules

- `PharmaCore/` must remain free of `import CoreData`, `import SwiftUI`, `import UIKit`
- All use cases receive dependencies through their `init()` — no singletons inside use cases
- Domain events are never mutated — create a reversal event instead (see `UndoActionUseCase`)

### Localization

- The app is **Italian-language only**. All UI strings, labels, and messages are in Italian.
- Italian medical/regulatory terminology is used throughout (e.g., `codice fiscale`, `ricetta`, `confezione`, `principio attivo`, `AIC`)
- Do not translate UI strings to English in code

### Naming Conventions

- Italian field names on Core Data entities (e.g., `nome`, `principio_attivo`, `obbligo_ricetta`)
- Swift property/method names in English (e.g., `medicine.name`, `therapy.startDate`)
- Feature module directories named in Italian (e.g., `Oggi` is Italian for "Today")

### iOS Availability

- Target minimum: iOS 16
- The new `Tab` API in `TabView` requires iOS 18 — the current `ContentView` has an `if #available(iOS 18.0, *)` guard but the fallback `else` branch is empty (TODO)
- Use `@available(iOS 17.0, *)` / `@available(iOS 18.0, *)` guards for any newer APIs
- `View+Availability.swift` provides SwiftUI view modifiers that no-op on older OS versions

### Core Data

- Always save on `viewContext` from `@MainActor`
- Use `context.hasChanges` before calling `context.save()` to avoid unnecessary writes
- The store uses automatic lightweight migration — adding new attributes requires adding them to the `.xcdatamodeld` with a default value

### Singletons

Singletons in this codebase (use sparingly — prefer DI for new code):
- `PersistenceController.shared`
- `DataManager.shared`
- `RefillLiveActivityCoordinator.shared`
- `LiveActivityURLActionHandler.shared`
- `UserIdentityProvider.shared`
- `AccountPersonService.shared`
- `OperationIdProvider.shared`

---

## Development Workflow

### Building

1. Open `PharmaApp.xcodeproj` in Xcode (14.0+, ideally Xcode 16+)
2. Select the `PharmaApp` scheme and an iOS simulator or device
3. ⌘B to build, ⌘R to run
4. `GoogleService-Info.plist` must be present (contains Firebase config); the committed file is a placeholder — replace with a real one for Firebase features

### Adding a New Feature

1. Create a new directory under `PharmaApp/Feature/<FeatureName>/`
2. Add `<Feature>View.swift` and `<Feature>ViewModel.swift`
3. If the feature requires new domain logic, add a use case to `PharmaCore/UseCases/`
4. If the feature needs new data, add entities to the `.xcdatamodeld` and create a new model version for migration
5. If the feature requires Core Data access, pass `NSManagedObjectContext` via the environment, not as a singleton
6. Write XCTest unit tests for any new use case or non-trivial service

### Adding a New Recurrence Pattern

1. Extend `RecurrenceRule.swift` with new fields
2. Update `RecurrenceService.parseRecurrenceString()` to parse the new format
3. Update `TodayRecurrenceService.allowedEvents()` to handle the pattern
4. Add tests in `RecurrenceManagerTests` or `RecurrenceCycleTests`

### Adding a New Siri Intent

1. Create `<IntentName>Intent.swift` in `PharmaApp/Intents/`
2. Implement `AppIntent` protocol
3. Register in `PharmaAppShortcutsProvider`
4. If it needs Live Activity interaction, add a URL scheme handler in `LiveActivityURLActionHandler`
5. Test in `SiriIntentActionTests` or `SiriIntentQueryTests`

---

## Environment & Configuration

| File | Purpose |
|---|---|
| `GoogleService-Info.plist` | Firebase + Google Sign-In config (CLIENT_ID, BUNDLE_ID, etc.) |
| `PharmaAppLiveActivityExtension-Info.plist` | Extension bundle info |

No `.env` files — configuration lives in `.plist` files and app Info.plist keys.

The app reads `GIDClientID` from `Info.plist` for Google Sign-In. If not present, it falls back to reading `CLIENT_ID` from `GoogleService-Info.plist`.

---

## Important Business Logic Notes

### Stock Tracking

Stock is tracked through the event log:
- `purchaseRecorded` events increment stock
- `intakeRecorded` events decrement stock
- "Leftover units" on a therapy = package units minus consumed events

### Prescription Flow

Medicines with `obbligo_ricetta = true` (prescription required):
1. When stock falls below threshold, a `prescriptionRequested` event is needed
2. After visiting the doctor, a `prescriptionReceived` event is recorded
3. Only then is the medicine eligible for purchase
4. `ClinicalRules.swift` encodes these state machine rules

### Today View Computation

`TodayStateBuilder.buildState(input:)` produces three lists:
- `therapyItems` — pending dose intakes for today (sorted by scheduled time)
- `purchaseItems` — medicines needing purchase (sorted by stock depletion severity)
- `otherItems` — prescription requests, monitoring items, missed doses

Items are categorized as `TodayTodoCategory`: `.therapy`, `.purchase`, `.prescription`, `.monitoring`, `.missedDose`, `.deadline`

A medicine appears in the purchase list when `autonomyDays < stockThreshold` (default 7 days).
