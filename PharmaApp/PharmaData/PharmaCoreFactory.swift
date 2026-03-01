import Foundation
import CoreData

struct PharmaCoreFactory {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - Repositories

    func makeMedicineRepository() -> MedicineRepository {
        CoreDataMedicineRepository(context: context)
    }

    func makeTherapyRepository() -> TherapyRepository {
        CoreDataTherapyRepository(context: context)
    }

    func makeLogRepository() -> LogRepository {
        CoreDataLogRepository(context: context)
    }

    func makeStockRepository() -> StockRepository {
        CoreDataStockRepository(context: context)
    }

    func makeOptionRepository() -> OptionRepository {
        CoreDataOptionRepository(context: context)
    }

    func makeCabinetRepository() -> CabinetRepository {
        CoreDataCabinetRepository(context: context)
    }

    func makeMedicinePackageRepository() -> MedicinePackageRepository {
        CoreDataMedicinePackageRepository(context: context)
    }

    // MARK: - Services

    func makeRecurrenceService() -> RecurrencePort {
        PureRecurrenceService()
    }

    func makeSectionCalculator() -> SectionCalculator {
        SectionCalculator(recurrenceService: makeRecurrenceService())
    }

    func makeDoseScheduleReadModel() -> DoseScheduleReadModel {
        DoseScheduleReadModel(recurrenceService: makeRecurrenceService())
    }

    func makeCabinetSummaryReadModel() -> CabinetSummaryReadModel {
        CabinetSummaryReadModel(recurrenceService: makeRecurrenceService())
    }

    func makeMedicineActionUseCase() -> MedicineActionUseCase {
        MedicineActionUseCase(
            logRepository: makeLogRepository(),
            therapyRepository: makeTherapyRepository(),
            medicineRepository: makeMedicineRepository(),
            eventStore: CoreDataEventStore(context: context),
            recurrenceService: makeRecurrenceService()
        )
    }
}
