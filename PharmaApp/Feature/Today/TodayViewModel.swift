import SwiftUI
import CoreData

/// ViewModel dedicato al tab "Oggi".
/// Sposta la logica di costruzione dei todo e degli insight fuori dalla view.
class TodayViewModel: ObservableObject {
    let actionService: MedicineActionService
    private let recordIntakeUseCase: RecordIntakeUseCase
    private let operationIdProvider: OperationIdProviding
    private let todayStateProvider: CoreDataTodayStateProvider
    @Published private(set) var state: TodayState = .empty

    init(
        actionService: MedicineActionService = MedicineActionService(),
        recordIntakeUseCase: RecordIntakeUseCase = RecordIntakeUseCase(
            eventStore: CoreDataEventStore(context: PersistenceController.shared.container.viewContext),
            clock: SystemClock()
        ),
        operationIdProvider: OperationIdProviding = OperationIdProvider.shared,
        todayStateProvider: CoreDataTodayStateProvider = CoreDataTodayStateProvider(
            context: PersistenceController.shared.container.viewContext
        )
    ) {
        self.actionService = actionService
        self.recordIntakeUseCase = recordIntakeUseCase
        self.operationIdProvider = operationIdProvider
        self.todayStateProvider = todayStateProvider
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
        let newState = todayStateProvider.buildState(
            medicines: medicines,
            logs: logs,
            todos: todos,
            option: option,
            completedTodoIDs: completedTodoIDs
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
        TodayStateBuilder.completionKey(for: item)
    }

    @MainActor
    func syncTodos(
        from items: [TodayTodoItem],
        medicines: [Medicine],
        option: Option?
    ) {
        let context = viewContext
        let now = Date()
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
            todo.due_at = todayStateProvider.todoTimeDate(
                for: item,
                medicines: medicines,
                option: option,
                now: now
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

    struct TodayIntakeInfo: Equatable {
        let date: Date
        let personName: String?
        let therapy: Therapy
    }

    @MainActor
    func nextDoseTodayInfo(for medicine: Medicine) -> TodayIntakeInfo? {
        let option = Option.current(in: viewContext)
        guard let info = todayStateProvider.nextDoseTodayInfo(for: medicine, option: option) else { return nil }
        guard let therapy = resolveTherapy(for: medicine, id: info.therapyId) else { return nil }
        return TodayIntakeInfo(date: info.date, personName: info.personName, therapy: therapy)
    }

    @MainActor
    func nextUpcomingDoseDate(for medicine: Medicine) -> Date? {
        todayStateProvider.nextUpcomingDoseDate(for: medicine)
    }

    // MARK: - Helpers per medicine lookup
    private func medicine(for item: TodayTodoItem, medicines: [Medicine]) -> Medicine? {
        if let id = item.medicineId, let medicine = medicines.first(where: { $0.id == id.rawValue }) {
            return medicine
        }
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return medicines.first(where: { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle })
    }

    private func resolveTherapy(for medicine: Medicine, id: TherapyId) -> Therapy? {
        medicine.therapies?.first(where: { $0.id == id.rawValue })
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
