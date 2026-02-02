import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Oggi".
/// Sposta la logica di costruzione dei todo e degli insight fuori dalla view.
class TodayViewModel: ObservableObject {
    let actionService: MedicineActionService
    private let recordIntakeUseCase: RecordIntakeUseCase
    private let operationIdProvider: OperationIdProviding
    @Published private(set) var state: TodayState = .empty

    init(
        actionService: MedicineActionService = MedicineActionService(),
        recordIntakeUseCase: RecordIntakeUseCase = RecordIntakeUseCase(
            eventStore: CoreDataEventStore(context: PersistenceController.shared.container.viewContext),
            clock: SystemClock()
        ),
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared
    ) {
        self.actionService = actionService
        self.recordIntakeUseCase = recordIntakeUseCase
        self.operationIdProvider = operationIdProvider
    }

    private var viewContext: NSManagedObjectContext {
        PersistenceController.shared.container.viewContext
    }

    @MainActor
    func refreshState(
        medicines: [Medicine],
        logs: [Log],
        todos: [Todo],
        option: Option?,
        completedTodoIDs: Set<String>
    ) {
        let recurrenceManager = RecurrenceManager(context: viewContext)
        let clinicalContext = ClinicalContextBuilder(context: viewContext).build(for: medicines)
        let newState = TodayTodoEngine.buildState(
            medicines: medicines,
            logs: logs,
            todos: todos,
            option: option,
            completedTodoIDs: completedTodoIDs,
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext
        )
        if newState != state {
            state = newState
        }
    }

    // MARK: - Intake (PharmaCore)
    func recordIntake(medicine: Medicine, therapy: Therapy?, operationId: UUID) -> RecordIntakeResult? {
        guard let package = resolvePackage(for: medicine, therapy: therapy) else {
            print("⚠️ recordIntake: package missing for \(medicine.nome)")
            return nil
        }

        let request = RecordIntakeRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            therapyId: therapy.map { TherapyId($0.id) },
            packageId: PackageId(package.id)
        )

        do {
            return try recordIntakeUseCase.execute(request)
        } catch {
            print("⚠️ recordIntake: \(error)")
            return nil
        }
    }

    func undoCompletion(operationId: UUID?, logObjectID: NSManagedObjectID?) {
        if let operationId {
            _ = actionService.undoLog(operationId: operationId)
            return
        }
        if let logObjectID {
            _ = actionService.undoLog(logObjectID: logObjectID)
        }
    }

    func intakeOperationId(for completionKey: String, source: OperationSource = .today) -> UUID {
        let key = OperationKey.intake(completionKey: completionKey, source: source)
        return operationIdProvider.operationId(for: key, ttl: 180)
    }

    func clearIntakeOperationId(for completionKey: String, source: OperationSource = .today) {
        let key = OperationKey.intake(completionKey: completionKey, source: source)
        operationIdProvider.clear(key)
    }

    func operationToken(
        action: OperationAction,
        medicine: Medicine,
        source: OperationSource = .today,
        ttl: TimeInterval = 3
    ) -> (id: UUID, key: OperationKey) {
        let key = operationKey(action: action, medicine: medicine, source: source)
        let id = operationIdProvider.operationId(for: key, ttl: ttl)
        return (id, key)
    }

    func clearOperationId(for key: OperationKey?) {
        guard let key else { return }
        operationIdProvider.clear(key)
    }

    func completionKey(for item: TodayTodoItem) -> String {
        TodayTodoEngine.completionKey(for: item)
    }

    @MainActor
    func syncTodos(
        from items: [TodayTodoItem],
        medicines: [Medicine],
        option: Option?
    ) {
        let context = viewContext
        let now = Date()
        let recurrenceManager = RecurrenceManager(context: context)
        let request: NSFetchRequest<Todo> = Todo.fetchRequest()
        let existing: [Todo]
        do {
            existing = try context.fetch(request)
        } catch {
            print("⚠️ syncTodos: fetch failed \(error)")
            return
        }

        var bySourceID: [String: Todo] = [:]
        for todo in existing {
            bySourceID[todo.source_id] = todo
        }

        var seen: Set<String> = []
        for item in items {
            let sourceID = item.id
            seen.insert(sourceID)
            let todo = bySourceID[sourceID] ?? Todo(context: context)
            if bySourceID[sourceID] == nil {
                todo.id = UUID()
                todo.created_at = now
            }
            todo.source_id = sourceID
            todo.title = item.title
            todo.detail = item.detail
            todo.category = item.category.rawValue
            todo.updated_at = now
            todo.due_at = TodayTodoEngine.todoTimeDate(
                for: item,
                medicines: medicines,
                options: option,
                recurrenceManager: recurrenceManager,
                now: now,
                calendar: .current
            )
            todo.medicine = medicine(for: item, medicines: medicines)
        }

        for todo in existing where !seen.contains(todo.source_id) {
            context.delete(todo)
        }

        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("⚠️ syncTodos: save failed \(error)")
        }
    }

    func earliestDoseToday(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Date? {
        TodayTodoEngine.earliestDoseToday(
            for: medicine,
            recurrenceManager: recurrenceManager,
            now: Date(),
            calendar: .current
        )
    }

    func isOutOfStock(_ medicine: Medicine, option: Option?, recurrenceManager: RecurrenceManager) -> Bool {
        TodayTodoEngine.isOutOfStock(medicine, option: option, recurrenceManager: recurrenceManager)
    }

    func needsPrescriptionBeforePurchase(_ medicine: Medicine, option: Option?, recurrenceManager: RecurrenceManager) -> Bool {
        TodayTodoEngine.needsPrescriptionBeforePurchase(medicine, option: option, recurrenceManager: recurrenceManager)
    }

    @MainActor
    func nextDoseTodayInfo(for medicine: Medicine) -> TodayTodoEngine.TodayDoseInfo? {
        let recurrenceManager = RecurrenceManager(context: viewContext)
        return TodayTodoEngine.nextDoseTodayInfo(
            for: medicine,
            recurrenceManager: recurrenceManager,
            now: Date(),
            calendar: .current
        )
    }

    // MARK: - Helpers per medicine lookup
    private func medicine(for item: TodayTodoItem, medicines: [Medicine]) -> Medicine? {
        if let id = item.medicineID, let medicine = medicines.first(where: { $0.objectID == id }) {
            return medicine
        }
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return medicines.first(where: { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle })
    }

    private func resolvePackage(for medicine: Medicine, therapy: Therapy?) -> Package? {
        if let therapy { return therapy.package }
        if let therapies = medicine.therapies, let first = therapies.first {
            return first.package
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        if !medicine.packages.isEmpty {
            return medicine.packages.sorted(by: { $0.numero > $1.numero }).first
        }
        return nil
    }

    func operationKey(action: OperationAction, medicine: Medicine, source: OperationSource) -> OperationKey {
        let packageId = resolvePackage(for: medicine, therapy: nil)?.id
        return OperationKey.medicineAction(
            action: action,
            medicineId: medicine.id,
            packageId: packageId,
            source: source
        )
    }
}
