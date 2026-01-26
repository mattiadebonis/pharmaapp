import CoreData

class DataManager {
    let context: NSManagedObjectContext
    static let shared = DataManager(context: PersistenceController.shared.container.viewContext)

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func loadMedicinesFromJSON() -> [[String: Any]] {
        guard let url = Bundle.main.url(forResource: "medicinale_example", withExtension: "json") else {
            fatalError("Impossibile trovare il file 'medicinale_example.json' nel bundle.")
        }

        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return extractMedicinesArray(from: json)
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
            medicine.codice_forma_dosaggio = stringValue(medicineData["id"])
            medicine.principi_attivi_it_json = jsonString(from: medicineData["principiAttiviIt"])
            medicine.vie_somministrazione_json = jsonString(from: medicineData["vieSomministrazione"])
            medicine.codice_atc_json = jsonString(from: medicineData["codiceAtc"])
            medicine.descrizione_atc_json = jsonString(from: medicineData["descrizioneAtc"])
            medicine.forma_farmaceutica = medicineData["formaFarmaceutica"] as? String
            medicine.piano_terapeutico = int32Value(medicineData["pianoTerapeutico"])
            medicine.descrizione_forma_dosaggio = medicineData["descrizioneFormaDosaggio"] as? String
            medicine.flag_alcol = boolValue(medicineData["flagAlcol"])
            medicine.flag_potassio = boolValue(medicineData["flagPotassio"])
            medicine.flag_guida = boolValue(medicineData["flagGuida"])
            medicine.flag_dopante = boolValue(medicineData["flagDopante"])
            medicine.livello_guida = stringValue(medicineData["livelloGuida"])
            medicine.descrizione_livello = medicineData["descrizioneLivello"] as? String
            medicine.carente = boolValue(medicineData["carente"])
            medicine.innovativo = boolValue(medicineData["innovativo"])
            medicine.orfano = boolValue(medicineData["orfano"])
            medicine.revocato = boolValue(medicineData["revocato"])
            medicine.sospeso = boolValue(medicineData["sospeso"])
            medicine.principio_attivo_forma_json = jsonString(from: medicineData["principioAttivoForma"])
            medicine.flag_fi = boolValue(medicineData["flagFI"])
            medicine.flag_rcp = boolValue(medicineData["flagRCP"])
            medicine.tipo_autorizzazione = stringValue(medicineData["tipoAutorizzazione"])
            medicine.aic6_importazione_parallela = stringValue(medicineData["aic6ImportazioneParallela"])
            medicine.sis_importazione_parallela = stringValue(medicineData["sisImportazioneParallela"])
            medicine.den_importazione_parallela = stringValue(medicineData["denImportazioneParallela"])
            medicine.rag_importazione_parallela = stringValue(medicineData["ragImportazioneParallela"])
            medicine.position_json = jsonString(from: medicineData["position"])

            medicine.codice_medicinale = stringValue(medicinalInfo?["codiceMedicinale"])
            medicine.aic6 = int32Value(medicinalInfo?["aic6"])
            medicine.denominazione_medicinale = (medicinalInfo?["denominazioneMedicinale"] as? String) ?? nome
            medicine.codice_sis = int32Value(medicinalInfo?["codiceSis"])
            medicine.azienda_titolare = medicinalInfo?["aziendaTitolare"] as? String
            medicine.categoria_medicinale = int32Value(medicinalInfo?["categoriaMedicinale"])
            medicine.commercio = stringValue(medicinalInfo?["commercio"])
            medicine.stato_amministrativo = medicinalInfo?["statoAmministrativo"] as? String

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
                package.principio_attivo = medicine.principio_attivo
                package.id_package = stringValue(conf["idPackage"])
                package.denominazione_package = conf["denominazionePackage"] as? String
                package.descrizione_fornitura = conf["descrizioneFornitura"] as? String
                package.classe_fornitura = conf["classeFornitura"] as? String
                package.codice_forma_dosaggio = stringValue(conf["codiceFormaDosaggio"])
                package.aic = conf["aic"] as? String
                package.descrizione_rf_json = jsonString(from: conf["descrizioneRf"])
                package.carenza_motivazione = conf["carenzaMotivazione"] as? String
                package.carenza_inizio = parseISODate(conf["carenzaInizio"])
                package.carenza_fine_presunta = parseISODate(conf["carenzaFinePresunta"])
                package.data_autorizzazione = parseISODate(conf["dataAutorizzazione"])
                package.flag_commercio = boolValue(conf["flagCommercio"])
                package.flag_prescrizione = boolValue(conf["flagPrescrizione"])
                package.carente = boolValue(conf["carente"])
                package.vie_somministrazione_json = jsonString(from: conf["vieSomministrazione"])
                package.classe_rimborsabilita = conf["classeRimborsabilita"] as? String
                package.descrizione_rimborsabilita = conf["descrizioneRimborsabilita"] as? String
                package.stato_amministrativo = conf["statoAmministrativo"] as? String
                package.descrizione_stato_amministrativo = conf["descrizioneStatoAmministrativo"] as? String
                package.data_registrazione_gu = parseISODate(conf["dataRegistrazioneGU"])
                package.data_ricezione_pratica = parseISODate(conf["dataRicezionePratica"])
                package.piano_terapeutico = int32Value(conf["pianoTerapeutico"])
                package.fk_forma_dosaggio = stringValue(conf["fkFormaDosaggio"])
                package.tipo_autorizzazione = stringValue(conf["tipoAutorizzazione"])
                package.aic6_importazione_parallela = stringValue(conf["aic6ImportazioneParallela"])
                package.sis_importazione_parallela = stringValue(conf["sisImportazioneParallela"])
                package.den_importazione_parallela = stringValue(conf["denImportazioneParallela"])
                package.rag_importazione_parallela = stringValue(conf["ragImportazioneParallela"])
                package.categoria_medicinale = stringValue(conf["categoriaMedicinale"])
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

    private func extractMedicinesArray(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] {
            return array
        }
        if let dict = json as? [String: Any] {
            return [dict]
        }
        return []
    }

    private func jsonString(from value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            return string
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }

    private func int32Value(_ value: Any?) -> Int32 {
        guard let value, !(value is NSNull) else { return 0 }
        if let intValue = value as? Int {
            return Int32(intValue)
        }
        if let intValue = value as? Int32 {
            return intValue
        }
        if let intValue = value as? Int64 {
            return Int32(intValue)
        }
        if let doubleValue = value as? Double {
            return Int32(doubleValue)
        }
        if let boolValue = value as? Bool {
            return boolValue ? 1 : 0
        }
        if let string = value as? String, let parsed = Int32(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return parsed
        }
        return 0
    }

    private func boolValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let intValue = value as? Int {
            return intValue != 0
        }
        if let intValue = value as? Int32 {
            return intValue != 0
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "si", "y", "t"].contains(normalized)
        }
        return false
    }

    private func parseISODate(_ value: Any?) -> Date? {
        if let date = value as? Date {
            return date
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let parsed = Self.isoFormatterWithFractional.date(from: string) {
            return parsed
        }
        return Self.isoFormatter.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
