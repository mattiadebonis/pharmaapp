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
            let info = medicineData["informazioni"] as? [String: Any]
            let flags = medicineData["flags"] as? [String: Any]
            let principles = medicineData["principi"] as? [String: Any]
            let medicinalInfo = medicineData["medicinale"] as? [String: Any]

            func medValue(_ key: String) -> Any? {
                value(for: key, in: medicineData, fallbacks: [info, flags, principles])
            }

            let medicineId = UUID(uuidString: medicineData["id"] as? String ?? "") ?? UUID()
            let nome = (medicinalInfo?["denominazioneMedicinale"] as? String)
                ?? (medValue("denominazioneMedicinale") as? String)
                ?? (medValue("descrizioneFormaDosaggio") as? String)
                ?? (medValue("principiAttiviIt") as? [String])?.first
                ?? "Medicinale"

            let principiAttivi = medValue("principiAttiviIt") as? [String] ?? []
            let descrizioniAtc = medValue("descrizioneAtc") as? [String] ?? []
            let principioAttivo = {
                let joined = principiAttivi.joined(separator: ", ")
                if !joined.isEmpty { return joined }
                let fallback = descrizioniAtc.joined(separator: ", ")
                return fallback.isEmpty ? nome : fallback
            }()

            let confezioni = medicineData["confezioni"] as? [[String: Any]] ?? []
            let obbligoRicetta = requiresPrescription(from: confezioni)
            let dosage = parseDosage(from: medValue("descrizioneFormaDosaggio") as? String)

            let medicine = Medicine(context: context)
            medicine.id = medicineId
            medicine.nome = nome
            medicine.principio_attivo = principioAttivo
            medicine.obbligo_ricetta = obbligoRicetta
            medicine.codice_forma_dosaggio = stringValue(medicineData["id"])
            medicine.principi_attivi_it_json = jsonString(from: medValue("principiAttiviIt"))
            medicine.vie_somministrazione_json = jsonString(from: medValue("vieSomministrazione"))
            medicine.codice_atc_json = jsonString(from: medValue("codiceAtc"))
            medicine.descrizione_atc_json = jsonString(from: medValue("descrizioneAtc"))
            medicine.forma_farmaceutica = medValue("formaFarmaceutica") as? String
            medicine.piano_terapeutico = int32Value(medValue("pianoTerapeutico"))
            medicine.descrizione_forma_dosaggio = medValue("descrizioneFormaDosaggio") as? String
            medicine.flag_alcol = boolValue(medValue("flagAlcol"))
            medicine.flag_potassio = boolValue(medValue("flagPotassio"))
            medicine.flag_guida = boolValue(medValue("flagGuida"))
            medicine.flag_dopante = boolValue(medValue("flagDopante"))
            medicine.livello_guida = stringValue(medValue("livelloGuida"))
            medicine.descrizione_livello = medValue("descrizioneLivello") as? String
            medicine.carente = boolValue(medValue("carente"))
            medicine.innovativo = boolValue(medValue("innovativo"))
            medicine.orfano = boolValue(medValue("orfano"))
            medicine.revocato = boolValue(medValue("revocato"))
            medicine.sospeso = boolValue(medValue("sospeso"))
            medicine.principio_attivo_forma_json = jsonString(from: medValue("principioAttivoForma") ?? principles?["forme"] ?? medValue("forme"))
            medicine.flag_fi = boolValue(medValue("flagFI"))
            medicine.flag_rcp = boolValue(medValue("flagRCP"))
            medicine.tipo_autorizzazione = stringValue(medValue("tipoAutorizzazione"))
            medicine.aic6_importazione_parallela = stringValue(medValue("aic6ImportazioneParallela"))
            medicine.sis_importazione_parallela = stringValue(medValue("sisImportazioneParallela"))
            medicine.den_importazione_parallela = stringValue(medValue("denImportazioneParallela"))
            medicine.rag_importazione_parallela = stringValue(medValue("ragImportazioneParallela"))
            medicine.position_json = jsonString(from: medValue("position"))

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
                package.descrizione_fornitura = packageValue("descrizioneFornitura", in: conf) as? String
                package.classe_fornitura = packageValue("classeFornitura", in: conf) as? String
                package.codice_forma_dosaggio = stringValue(packageValue("codiceFormaDosaggio", in: conf))
                package.aic = packageValue("aic", in: conf) as? String
                package.descrizione_rf_json = jsonString(from: packageValue("descrizioneRf", in: conf))
                package.carenza_motivazione = packageValue("carenzaMotivazione", in: conf) as? String
                package.carenza_inizio = parseISODate(packageValue("carenzaInizio", in: conf))
                package.carenza_fine_presunta = parseISODate(packageValue("carenzaFinePresunta", in: conf))
                package.data_autorizzazione = parseISODate(packageValue("dataAutorizzazione", in: conf))
                package.flag_commercio = boolValue(packageValue("flagCommercio", in: conf))
                package.flag_prescrizione = boolValue(packagePrescriptionValue(in: conf))
                package.carente = boolValue(packageValue("carente", in: conf))
                let routesValue = packageAdministrationRoutes(in: conf) ?? medValue("vieSomministrazione")
                package.vie_somministrazione_json = jsonString(from: routesValue)
                package.classe_rimborsabilita = packageValue("classeRimborsabilita", in: conf) as? String
                package.descrizione_rimborsabilita = packageValue("descrizioneRimborsabilita", in: conf) as? String
                package.stato_amministrativo = packageValue("statoAmministrativo", in: conf) as? String
                package.descrizione_stato_amministrativo = packageValue("descrizioneStatoAmministrativo", in: conf) as? String
                package.data_registrazione_gu = parseISODate(packageValue("dataRegistrazioneGU", in: conf))
                package.data_ricezione_pratica = parseISODate(packageValue("dataRicezionePratica", in: conf))
                package.piano_terapeutico = int32Value(packageValue("pianoTerapeutico", in: conf))
                package.fk_forma_dosaggio = stringValue(packageValue("fkFormaDosaggio", in: conf))
                package.tipo_autorizzazione = stringValue(packageValue("tipoAutorizzazione", in: conf))
                package.aic6_importazione_parallela = stringValue(packageValue("aic6ImportazioneParallela", in: conf))
                package.sis_importazione_parallela = stringValue(packageValue("sisImportazioneParallela", in: conf))
                package.den_importazione_parallela = stringValue(packageValue("denImportazioneParallela", in: conf))
                package.rag_importazione_parallela = stringValue(packageValue("ragImportazioneParallela", in: conf))
                package.categoria_medicinale = stringValue(packageValue("categoriaMedicinale", in: conf))
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
            if boolValue(packagePrescriptionValue(in: package)) {
                return true
            }
            if let classe = (packageValue("classeFornitura", in: package) as? String)?.uppercased(),
               ["RR", "RRL", "OSP"].contains(classe) {
                return true
            }
            let descrizioni = stringArray(from: packageValue("descrizioneRf", in: package))
            if descrizioni.contains(where: requiresPrescriptionDescription) {
                return true
            }
        }
        return false
    }

    private func requiresPrescriptionDescription(_ description: String) -> Bool {
        let lower = description.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("non soggetto") || lower.contains("senza ricetta") || lower.contains("senza prescrizione") || lower.contains("non richiede") {
            return false
        }
        return lower.contains("prescrizione") || lower.contains("ricetta")
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

    private func value(for key: String, in dict: [String: Any], fallbacks: [[String: Any]?] = []) -> Any? {
        var candidates: [[String: Any]?] = [dict]
        candidates.append(contentsOf: fallbacks)
        for candidate in candidates {
            if let val = candidate?[key], !(val is NSNull) {
                return val
            }
        }
        return nil
    }

    private func packageValue(_ key: String, in package: [String: Any]) -> Any? {
        let prescrizioni = package["prescrizioni"]
        var fallbacks: [[String: Any]?] = []
        if let dict = prescrizioni as? [String: Any] {
            fallbacks.append(dict)
        }
        fallbacks.append(package["informazioni"] as? [String: Any])

        if let val = value(for: key, in: package, fallbacks: fallbacks) {
            return val
        }

        if key == "flagPrescrizione" {
            if let bool = prescrizioni as? Bool { return bool }
            if let int = prescrizioni as? Int { return int }
            if let number = prescrizioni as? NSNumber { return number }
        }
        return nil
    }

    private func packagePrescriptionValue(in package: [String: Any]) -> Any? {
        if let val = packageValue("flagPrescrizione", in: package) { return val }
        return packageValue("prescrizione", in: package)
    }

    private func packageAdministrationRoutes(in package: [String: Any]) -> Any? {
        if let routes = packageValue("vieSomministrazione", in: package) {
            return routes
        }
        return nil
    }

    private func stringArray(from value: Any?) -> [String] {
        guard let value = value else { return [] }
        if let array = value as? [String] { return array }
        if let string = value as? String { return [string] }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }
        return []
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
