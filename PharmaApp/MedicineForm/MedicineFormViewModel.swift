import Foundation
import CoreData
import SwiftUI

class MedicineFormViewModel: ObservableObject {
    
    @Published var isDataUpdated: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var time: String = ""
    
    private let context: NSManagedObjectContext
    
    init(context: NSManagedObjectContext) {
        self.context = context
    }


    func saveForniture(medicine: Medicine, package: Package) {  
        do{
            
            let log = Log(context: context)
            log.id = UUID()
            log.timestamp = Date()
            log.medicine = medicine
            log.type = "purchase"

            if medicine.therapies?.isEmpty ?? true {
                let therapy = Therapy(context: context)
                therapy.id = UUID()
                therapy.medicine = medicine
                therapy.rrule = nil
                therapy.start_date = nil
                therapy.package = package
            }
            
            try context.save()
            successMessage = "Salvataggio scorte riuscito!"

            DispatchQueue.main.async {
                self.isDataUpdated = true
            }

        } catch {
            print("Errore nel salvataggio di Furniture: \(error.localizedDescription)")
        }
        
    }

    
}
