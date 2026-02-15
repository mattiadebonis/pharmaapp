import SwiftUI
import CoreData
import os.signpost

/// ViewModel dedicato al tab "Oggi".
/// Sposta la logica di costruzione dei todo e degli insight fuori dalla view.
class TodayViewModel: ObservableObject {
    let actionService: MedicineActionService
    private let recordIntakeUseCase: RecordIntakeUseCase
    private let operationIdProvider: OperationIdProviding
    private let todayStateProvider: CoreDataTodayStateProvider
    private let refreshEngine = TodayStateRefreshEngine()
    private var refreshTask: Task<Void, Never>?
    private let refreshLogLookbackDays = 90
    private let perfLog = OSLog(subsystem: "PharmaApp", category: "Performance")
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
        refreshTask?.cancel()

        let cutoff = Calendar.current.date(byAdding: .day, value: -refreshLogLookbackDays, to: Date()) ?? .distantPast
        let medicineIDs = medicines.map(\.objectID)
        let recentLogIDs = logs.filter { $0.timestamp >= cutoff }.map(\.objectID)
        let todoIDs = todos.map(\.objectID)
        let optionID = option?.objectID
        let completedIDs = completedTodoIDs

        refreshTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let token = await self.refreshEngine.issueToken()
            let signpostID = OSSignpostID(log: self.perfLog)
            os_signpost(.begin, log: self.perfLog, name: "TodayRefresh", signpostID: signpostID)
            defer { os_signpost(.end, log: self.perfLog, name: "TodayRefresh", signpostID: signpostID) }

            guard let newState = await Self.buildStateInBackground(
                medicineIDs: medicineIDs,
                logIDs: recentLogIDs,
                todoIDs: todoIDs,
                optionID: optionID,
                completedTodoIDs: completedIDs
            ) else { return }
            guard !Task.isCancelled else { return }
            guard await self.refreshEngine.isLatest(token) else { return }

            await MainActor.run {
                if newState != self.state {
                    self.state = newState
                }
            }
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
        option: Option?,
        timeLabels: [String: TodayTimeLabel]
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
            let isNew = bySourceID[sourceID] == nil
            if isNew {
                todo.id = UUID()
                todo.created_at = now
            }

            var didChange = isNew

            if todo.source_id != sourceID {
                todo.source_id = sourceID
                didChange = true
            }
            if todo.title != item.title {
                todo.title = item.title
                didChange = true
            }
            if todo.detail != item.detail {
                todo.detail = item.detail
                didChange = true
            }
            if todo.category != item.category.rawValue {
                todo.category = item.category.rawValue
                didChange = true
            }

            let resolvedDueAt = resolvedDueDate(
                for: item,
                medicines: medicines,
                option: option,
                timeLabels: timeLabels,
                now: now
            )
            if todo.due_at != resolvedDueAt {
                todo.due_at = resolvedDueAt
                didChange = true
            }

            let resolvedMedicine = medicine(for: item, medicines: medicines)
            if todo.medicine?.objectID != resolvedMedicine?.objectID {
                todo.medicine = resolvedMedicine
                didChange = true
            }

            if didChange {
                todo.updated_at = now
            }
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

    private func resolvedDueDate(
        for item: TodayTodoItem,
        medicines: [Medicine],
        option: Option?,
        timeLabels: [String: TodayTimeLabel],
        now: Date
    ) -> Date? {
        if let label = timeLabels[item.id] {
            switch label {
            case .time(let date):
                return date
            case .category:
                if !item.id.hasPrefix("purchase|deadline|") && item.category != .deadline {
                    return nil
                }
            }
        }
        return todayStateProvider.todoTimeDate(
            for: item,
            medicines: medicines,
            option: option,
            now: now
        )
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

    private static func buildStateInBackground(
        medicineIDs: [NSManagedObjectID],
        logIDs: [NSManagedObjectID],
        todoIDs: [NSManagedObjectID],
        optionID: NSManagedObjectID?,
        completedTodoIDs: Set<String>
    ) async -> TodayState? {
        let container = await MainActor.run { PersistenceController.shared.container }
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return await withCheckedContinuation { continuation in
            context.perform {
                let medicines = medicineIDs.compactMap { id in
                    try? context.existingObject(with: id) as? Medicine
                }
                let logs = logIDs.compactMap { id in
                    try? context.existingObject(with: id) as? Log
                }
                let todos = todoIDs.compactMap { id in
                    try? context.existingObject(with: id) as? Todo
                }
                let option = optionID.flatMap { id in
                    try? context.existingObject(with: id) as? Option
                }

                let provider = CoreDataTodayStateProvider(context: context)
                let state = provider.buildState(
                    medicines: medicines,
                    logs: logs,
                    todos: todos,
                    option: option,
                    completedTodoIDs: completedTodoIDs
                )
                continuation.resume(returning: state)
            }
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}

actor TodayStateRefreshEngine {
    private var token: UInt64 = 0

    func issueToken() -> UInt64 {
        token &+= 1
        return token
    }

    func isLatest(_ candidate: UInt64) -> Bool {
        candidate == token
    }
}
