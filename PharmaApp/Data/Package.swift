//
//  Therapy.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 10/12/24.
//

import CoreData

@objc(Package)
public class Package: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var id_package: String?
    @NSManaged public var denominazione_package: String?
    @NSManaged public var descrizione_fornitura: String?
    @NSManaged public var classe_fornitura: String?
    @NSManaged public var codice_forma_dosaggio: String?
    @NSManaged public var aic: String?
    @NSManaged public var descrizione_rf_json: String?
    @NSManaged public var carenza_motivazione: String?
    @NSManaged public var carenza_inizio: Date?
    @NSManaged public var carenza_fine_presunta: Date?
    @NSManaged public var data_autorizzazione: Date?
    @NSManaged public var flag_commercio: Bool
    @NSManaged public var flag_prescrizione: Bool
    @NSManaged public var carente: Bool
    @NSManaged public var vie_somministrazione_json: String?
    @NSManaged public var classe_rimborsabilita: String?
    @NSManaged public var descrizione_rimborsabilita: String?
    @NSManaged public var stato_amministrativo: String?
    @NSManaged public var descrizione_stato_amministrativo: String?
    @NSManaged public var data_registrazione_gu: Date?
    @NSManaged public var data_ricezione_pratica: Date?
    @NSManaged public var piano_terapeutico: Int32
    @NSManaged public var fk_forma_dosaggio: String?
    @NSManaged public var tipo_autorizzazione: String?
    @NSManaged public var aic6_importazione_parallela: String?
    @NSManaged public var sis_importazione_parallela: String?
    @NSManaged public var den_importazione_parallela: String?
    @NSManaged public var rag_importazione_parallela: String?
    @NSManaged public var categoria_medicinale: String?
    @NSManaged public var principio_attivo: String?
    @NSManaged public var numero: Int32
    @NSManaged public var tipologia: String
    @NSManaged public var valore: Int32
    @NSManaged public var unita: String
    @NSManaged public var volume: String
    @NSManaged public var medicine: Medicine
    @NSManaged public var therapies: Set<Therapy>?
    @NSManaged public var stocks: Set<Stock>?
    @NSManaged public var medicinePackages: Set<MedicinePackage>?
    @NSManaged public var logs: Set<Log>?
}

extension Package{
    static func extractPackages() -> NSFetchRequest<Package> {
    
        let request:NSFetchRequest<Package> = Package.fetchRequest() as! NSFetchRequest <Package>
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        
        request.sortDescriptors = [sortDescriptor]
        
        return request

    }

    func addToStocks(_ stock: Stock) {
        self.mutableSetValue(forKey: "stocks").add(stock)
    }
}
