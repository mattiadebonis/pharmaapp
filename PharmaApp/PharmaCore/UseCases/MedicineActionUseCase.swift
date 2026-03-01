import Foundation

public struct MedicineActionUseCase {
    private let logRepository: LogRepository
    private let therapyRepository: TherapyRepository
    private let medicineRepository: MedicineRepository
    private let eventStore: EventStore
    private let recurrenceService: RecurrencePort
    private let clock: Clock

    private lazy var recordPurchaseUseCase = RecordPurchaseUseCase(eventStore: eventStore, clock: clock)
    private lazy var requestPrescriptionUseCase = RequestPrescriptionUseCase(eventStore: eventStore, clock: clock)
    private lazy var recordPrescriptionReceivedUseCase = RecordPrescriptionReceivedUseCase(eventStore: eventStore, clock: clock)
    private lazy var undoActionUseCase = UndoActionUseCase(eventStore: eventStore, clock: clock)

    public init(
        logRepository: LogRepository,
        therapyRepository: TherapyRepository,
        medicineRepository: MedicineRepository,
        eventStore: EventStore,
        recurrenceService: RecurrencePort,
        clock: Clock = SystemClock()
    ) {
        self.logRepository = logRepository
        self.therapyRepository = therapyRepository
        self.medicineRepository = medicineRepository
        self.eventStore = eventStore
        self.recurrenceService = recurrenceService
        self.clock = clock
    }

    // MARK: - Prescription

    public mutating func requestPrescription(
        medicineId: MedicineId,
        packageId: PackageId,
        operationId: UUID
    ) throws {
        let request = RequestPrescriptionRequest(
            operationId: operationId,
            medicineId: medicineId,
            packageId: packageId
        )
        _ = try requestPrescriptionUseCase.execute(request)
    }

    public mutating func markPrescriptionReceived(
        medicineId: MedicineId,
        packageId: PackageId,
        operationId: UUID
    ) throws {
        let request = RecordPrescriptionReceivedRequest(
            operationId: operationId,
            medicineId: medicineId,
            packageId: packageId
        )
        _ = try recordPrescriptionReceivedUseCase.execute(request)
    }

    // MARK: - Purchase

    public mutating func recordPurchase(
        medicineId: MedicineId,
        packageId: PackageId,
        operationId: UUID
    ) throws {
        let request = RecordPurchaseRequest(
            operationId: operationId,
            medicineId: medicineId,
            packageId: packageId
        )
        _ = try recordPurchaseUseCase.execute(request)
    }

    // MARK: - Intake

    public func recordIntake(
        medicineId: MedicineId,
        packageId: PackageId,
        therapyId: TherapyId?,
        operationId: UUID,
        timestamp: Date? = nil,
        scheduledDueAt: Date? = nil
    ) throws -> UUID {
        let request = CreateLogRequest(
            type: .intake,
            medicineId: medicineId,
            packageId: packageId,
            therapyId: therapyId,
            timestamp: timestamp ?? clock.now(),
            scheduledDueAt: scheduledDueAt,
            operationId: operationId
        )
        return try logRepository.createLog(request)
    }

    public func resolveTherapyCandidate(
        for medicineId: MedicineId,
        packageId: PackageId? = nil,
        now: Date? = nil
    ) throws -> TherapySnapshot? {
        let currentTime = now ?? clock.now()
        var therapies = try therapyRepository.fetchTherapies(for: medicineId)

        if let packageId {
            therapies = therapies.filter { $0.packageId == packageId }
        }

        guard !therapies.isEmpty else { return nil }

        let candidates: [(therapy: TherapySnapshot, date: Date)] = therapies.compactMap { therapy in
            let rule = recurrenceService.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.startDate ?? currentTime
            guard let next = recurrenceService.nextOccurrence(
                rule: rule,
                startDate: startDate,
                after: currentTime,
                doses: therapy.doses,
                calendar: .current
            ) else { return nil }
            return (therapy, next)
        }

        if let chosen = candidates.min(by: { $0.date < $1.date }) {
            return chosen.therapy
        }

        return therapies.first
    }

    // MARK: - Undo

    public mutating func undoAction(operationId: UUID) throws -> Bool {
        do {
            _ = try undoActionUseCase.execute(
                UndoActionRequest(
                    originalOperationId: operationId,
                    undoOperationId: UUID()
                )
            )
            return true
        } catch let error as PharmaError {
            if error.code == .invalidInput || error.code == .notFound {
                return try logRepository.undoLog(operationId: operationId)
            }
            throw error
        }
    }

    // MARK: - Missed Dose

    public func missedDoseCandidate(
        for medicineId: MedicineId,
        packageId: PackageId? = nil,
        now: Date? = nil
    ) throws -> (therapyId: TherapyId, scheduledAt: Date, nextScheduledAt: Date?)? {
        let currentTime = now ?? clock.now()
        var therapies = try therapyRepository.fetchTherapies(for: medicineId)

        if let packageId {
            therapies = therapies.filter { $0.packageId == packageId }
        }

        let manualTherapies = therapies.filter { $0.manualIntakeRegistration }
        guard !manualTherapies.isEmpty else { return nil }

        guard let medicine = try medicineRepository.fetchMedicine(id: medicineId) else { return nil }
        let intakeLogs = medicine.effectiveIntakeLogs()

        let doseSchedule = DoseScheduleReadModel(recurrenceService: recurrenceService)
        return doseSchedule.missedDoseCandidate(
            for: manualTherapies,
            intakeLogs: intakeLogs,
            now: currentTime
        )
    }
}
