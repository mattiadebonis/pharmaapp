import CoreData

class DataManager {
    let context: NSManagedObjectContext
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadMedicinesFromJSON() -> [[String: Any]] {
        guard let url = Bundle.main.url(forResource: "medicinali", withExtension: "json") else {
            fatalError("Impossibile trovare il file 'medicinali.json' nel bundle.")
        }

        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
            return json ?? []
        } catch {
            fatalError("Impossibile decodificare il file JSON: \(error.localizedDescription)")
        }
    }


    func saveMedicinesToCoreData() {
        let medicines = loadMedicinesFromJSON()

        for medicineData in medicines {
            guard let idString = medicineData["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let nome = medicineData["nome"] as? String,
                  let principioAttivo = medicineData["principio_attivo"] as? String,
                  let obbligoRicetta = medicineData["obbligo_ricetta"] as? Bool
            else {
                print("Errore: dati incompleti per un medicinale, saltato.")
                continue
            }

            let medicine = Medicine(context: context)
            medicine.id = id
            medicine.nome = nome
            medicine.principio_attivo = principioAttivo
            medicine.obbligo_ricetta = obbligoRicetta
            if let confezioni = medicineData["confezioni"] as? [[String: Any]] {
                for conf in confezioni {
                    guard let confIdString = conf["id"] as? String,
                          let confId = UUID(uuidString: confIdString),
                          let numero = conf["numero"] as? Int32,
                          let tipologia = conf["tipologia"] as? String,
                          let dosaggio = conf["dosaggio"] as? [String: Any],
                          let valore = dosaggio["valore"] as? Int32,
                          let unita = dosaggio["unita"] as? String,
                          let volume = dosaggio["volume"] as? String
                    else {
                        print("Errore: dati incompleti per una confezione, saltata.")
                        continue
                    }
                    print(numero)
                    let package = Package(context: context)
                    package.id = confId
                    package.numero = numero
                    package.tipologia = tipologia
                    package.valore = valore
                    package.unita = unita
                    package.volume = volume
                    package.medicine = medicine
                    medicine.addToPackages(package)
                }
            } 
        }

        do {
            try context.save()
        } catch {
            print("Errore durante il salvataggio su Core Data: \(error.localizedDescription)")
        }
    }

    func initializeMedicinesDataIfNeeded() {
        if isCoreDataEmpty() {
            saveMedicinesToCoreData()
        }
    }

    func isCoreDataEmpty() -> Bool {
        let fetchRequest = NSFetchRequest<Medicine>(entityName: "Medicine")
        do {
            let count = try context.count(for: fetchRequest)
            return count == 0
        } catch {
            fatalError("Errore durante la verifica di Core Data: \(error.localizedDescription)")
        }
    }
    
    func loadPharmaciesFromJSON() -> [[String: Any]] {
            guard let url = Bundle.main.url(forResource: "farmacie", withExtension: "json") else {
                fatalError("Impossibile trovare il file 'farmacie.json' nel bundle.")
            }

            do {
                let data = try Data(contentsOf: url)
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]]
                return json ?? []
            } catch {
                fatalError("Impossibile decodificare il file JSON: \(error.localizedDescription)")
            }
        }
    
    func isPharmaciesCoreDataEmpty() -> Bool {
        let fetchRequest = NSFetchRequest<Pharmacie>(entityName: "Pharmacie")
        do {
            let count = try context.count(for: fetchRequest)
            return count == 0
        } catch {
            fatalError("Errore durante la verifica di Core Data: \(error.localizedDescription)")
        }
    }

    func savePharmaciesToCoreData() {
        let pharmacies = loadPharmaciesFromJSON()
        let pharmaciesNumber = pharmacies.count
        for pharmacyData in pharmacies {
            guard let id = pharmacyData["ID"] as? Int16,
                let name = pharmacyData["Nome"] as? String,
                let address = pharmacyData["Indirizzo"] as? String,
                let phone = pharmacyData["Telefono"] as? String
            else {
                print(pharmacyData["ID"])
                print(pharmacyData["Nome"])
                print(pharmacyData["Indirizzo"])
                print(pharmacyData["Telefono"])
                print("Errore: dati incompleti per una farmacia, saltata.\(pharmacyData)")
                continue
            }

            print("Farmacia \(name) salvata")
            let pharmacie = Pharmacie(context: context)
            pharmacie.id = id
            pharmacie.name = name
            pharmacie.address = address
            pharmacie.phone = phone

            if let openingTimes = pharmacyData["orari"] as? [[String: Any]] {
                for openingData in openingTimes {
                    guard let openingIdString = openingData["id"] as? String,
                          let openingId = UUID(uuidString: openingIdString),
                          let date = openingData["data"] as? Date,
                          let openingTime = openingData["orario_apertura"] as? String,
                          let turno = openingData["turno"] as? Bool
                    else {
                        print("Errore: dati incompleti per un orario di apertura, saltato.")
                        continue
                    }

                    let opening = OpeningTime(context: context)
                    opening.id = openingId
                    opening.date = date
                    opening.opening_time = openingTime
                    opening.turno = turno
                    opening.pharmacie = pharmacie
                    pharmacie.addToOpeningtimes(opening)
                }
            } 
        }

        do {
            try context.save()
            print("Dati salvati con successo")

        } catch {
            print("Errore durante il salvataggio su Core Data: \(error.localizedDescription)")
        }
    }

    func initializePharmaciesDataIfNeeded() {
        if isPharmaciesCoreDataEmpty() {
            savePharmaciesToCoreData()
        }
    }
    
    func initializeOptionsIfEmpty() {
        let fetchRequest: NSFetchRequest<Option> = Option.fetchRequest()

        do {
            let options = try context.fetch(fetchRequest)
            if options.isEmpty {
                let newOption = Option(context: context)
                newOption.id = UUID()
                newOption.manual_intake_registration = false
                newOption.day_threeshold_stocks_alarm = 7
            }else if options.count > 0 {
                if !options.first!.manual_intake_registration {
                    options.first!.manual_intake_registration = false
                }
                if (options.first!.day_threeshold_stocks_alarm == 0) {
                    options.first!.day_threeshold_stocks_alarm = 7
                }
            }

            try context.save()
            
        } catch {
            fatalError("Errore durante il controllo o l'inizializzazione delle opzioni: \(error.localizedDescription)")
        }
    }

}
