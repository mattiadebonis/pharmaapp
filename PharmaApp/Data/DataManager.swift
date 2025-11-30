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
            let medicineId = UUID(uuidString: medicineData["id"] as? String ?? "") ?? UUID()
            let medicinalInfo = medicineData["medicinale"] as? [String: Any]
            let nome = (medicinalInfo?["denominazioneMedicinale"] as? String)
                ?? (medicineData["descrizioneFormaDosaggio"] as? String)
                ?? (medicineData["principiAttiviIt"] as? [String])?.first
                ?? "Medicinale"

            let principiAttivi = medicineData["principiAttiviIt"] as? [String] ?? []
            let descrizioniAtc = medicineData["descrizioneAtc"] as? [String] ?? []
            let principioAttivo = {
                let joined = principiAttivi.joined(separator: ", ")
                if !joined.isEmpty { return joined }
                let fallback = descrizioniAtc.joined(separator: ", ")
                return fallback.isEmpty ? nome : fallback
            }()

            let confezioni = medicineData["confezioni"] as? [[String: Any]] ?? []
            let obbligoRicetta = requiresPrescription(from: confezioni)
            let dosage = parseDosage(from: medicineData["descrizioneFormaDosaggio"] as? String)

            let medicine = Medicine(context: context)
            medicine.id = medicineId
            medicine.nome = nome
            medicine.principio_attivo = principioAttivo
            medicine.obbligo_ricetta = obbligoRicetta

            for conf in confezioni {
                let package = Package(context: context)
                let confIdString = conf["idPackage"] as? String ?? ""
                package.id = UUID(uuidString: confIdString) ?? UUID()
                let tipologia = conf["denominazionePackage"] as? String ?? "Confezione"
                package.tipologia = tipologia
                package.numero = Int32(extractUnitCount(from: tipologia))
                package.valore = dosage.value
                package.unita = dosage.unit
                package.volume = extractVolume(from: tipologia)
                package.medicine = medicine
                medicine.addToPackages(package)
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

    private func requiresPrescription(from packages: [[String: Any]]) -> Bool {
        for package in packages {
            if let intFlag = package["flagPrescrizione"] as? Int, intFlag != 0 {
                return true
            }
            if let boolFlag = package["flagPrescrizione"] as? Bool, boolFlag {
                return true
            }
            if let classe = (package["classeFornitura"] as? String)?.uppercased(),
               ["RR", "RRL", "OSP"].contains(classe) {
                return true
            }
            if let descrizioni = package["descrizioneRf"] as? [String],
               descrizioni.contains(where: { $0.lowercased().contains("prescrizione") }) {
                return true
            }
        }
        return false
    }

    private func parseDosage(from description: String?) -> (value: Int32, unit: String) {
        guard let text = description else { return (0, "") }
        let tokens = text.split(separator: " ")
        var value: Int32 = 0
        var unit = ""
        for (index, token) in tokens.enumerated() {
            let digitString = token.filter(\.isNumber)
            if let parsed = Int32(digitString), !digitString.isEmpty {
                value = parsed
                if index + 1 < tokens.count {
                    let possibleUnit = tokens[index + 1]
                    if possibleUnit.rangeOfCharacter(from: .letters) != nil || possibleUnit.contains("/") {
                        unit = String(possibleUnit)
                    }
                }
                break
            }
        }
        return (value, unit)
    }

    private func extractUnitCount(from text: String) -> Int {
        let pattern = "\\d+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last,
              let range = Range(last.range, in: text),
              let value = Int(text[range]) else {
            return 0
        }
        return value
    }

    private func extractVolume(from text: String) -> String {
        let uppercased = text.uppercased()
        let pattern = "\\d+\\s*(ML|L)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(location: 0, length: (uppercased as NSString).length)
        if let match = regex.firstMatch(in: uppercased, range: range),
           let matchRange = Range(match.range, in: uppercased) {
            return uppercased[matchRange].lowercased()
        }
        return ""
    }
}
