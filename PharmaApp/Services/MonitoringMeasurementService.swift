import Foundation
import CoreData

struct MonitoringMeasurementPayload {
    let todoSourceID: String
    let kind: MonitoringKind
    let doseRelation: MonitoringDoseRelation?
    let measuredAt: Date
    let scheduledAt: Date?
    let valuePrimary: Double
    let valueSecondary: Double?
    let unit: String?
    let medicine: Medicine?
    let therapy: Therapy?

    init(
        todoSourceID: String,
        kind: MonitoringKind,
        doseRelation: MonitoringDoseRelation?,
        measuredAt: Date = Date(),
        scheduledAt: Date?,
        valuePrimary: Double,
        valueSecondary: Double? = nil,
        unit: String? = nil,
        medicine: Medicine?,
        therapy: Therapy?
    ) {
        self.todoSourceID = todoSourceID
        self.kind = kind
        self.doseRelation = doseRelation
        self.measuredAt = measuredAt
        self.scheduledAt = scheduledAt
        self.valuePrimary = valuePrimary
        self.valueSecondary = valueSecondary
        self.unit = unit
        self.medicine = medicine
        self.therapy = therapy
    }
}

final class MonitoringMeasurementService {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func saveOrUpdate(_ payload: MonitoringMeasurementPayload) throws -> MonitoringMeasurement {
        let measurement = try fetchByTodoSourceID(payload.todoSourceID) ?? makeMeasurement()
        if measurement.isInserted {
            measurement.id = UUID()
            measurement.created_at = payload.measuredAt
        }

        measurement.todo_source_id = payload.todoSourceID
        measurement.kind = payload.kind.rawValue
        measurement.dose_relation = payload.doseRelation?.rawValue
        measurement.measured_at = payload.measuredAt
        measurement.scheduled_at = payload.scheduledAt
        measurement.value_primary = NSNumber(value: payload.valuePrimary)
        if let valueSecondary = payload.valueSecondary {
            measurement.value_secondary = NSNumber(value: valueSecondary)
        } else {
            measurement.value_secondary = nil
        }
        measurement.unit = payload.unit
        measurement.medicine = inContextOptional(payload.medicine)
        measurement.therapy = inContextOptional(payload.therapy)

        try context.save()
        return measurement
    }

    func fetchDaily(on date: Date, calendar: Calendar = .current) throws -> [MonitoringMeasurement] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
        let request = MonitoringMeasurement.fetchRequest(from: start, to: end)
        return try context.fetch(request)
    }

    func fetchByTodoSourceID(_ todoSourceID: String) throws -> MonitoringMeasurement? {
        let request = MonitoringMeasurement.fetchRequest(todoSourceID: todoSourceID)
        return try context.fetch(request).first
    }

    @discardableResult
    func delete(todoSourceID: String) throws -> Bool {
        guard let measurement = try fetchByTodoSourceID(todoSourceID) else { return false }
        context.delete(measurement)
        try context.save()
        return true
    }

    @discardableResult
    func delete(id: UUID) throws -> Bool {
        let request: NSFetchRequest<MonitoringMeasurement> = MonitoringMeasurement.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let measurement = try context.fetch(request).first else { return false }
        context.delete(measurement)
        try context.save()
        return true
    }

    private func inContextOptional<T: NSManagedObject>(_ object: T?) -> T? {
        guard let object else { return nil }
        if object.managedObjectContext === context {
            return object
        }
        return context.object(with: object.objectID) as? T
    }

    private func makeMeasurement() throws -> MonitoringMeasurement {
        guard let entity = NSEntityDescription.entity(forEntityName: "MonitoringMeasurement", in: context) else {
            throw NSError(
                domain: "MonitoringMeasurementService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "MonitoringMeasurement entity not found in context model"]
            )
        }
        return MonitoringMeasurement(entity: entity, insertInto: context)
    }
}
