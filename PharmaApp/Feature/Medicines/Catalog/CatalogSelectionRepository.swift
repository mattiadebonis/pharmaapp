import Foundation

struct CatalogSelectionRepository {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadSelections() -> [CatalogSelection] {
        loadRecords()
            .flatMap { record in
                record.packages.map { package in
                    CatalogSelection(
                        id: package.id,
                        name: record.name,
                        principle: record.principle,
                        requiresPrescription: package.requiresPrescription,
                        packageLabel: package.label,
                        units: max(1, package.units),
                        tipologia: package.tipologia,
                        valore: package.dosageValue,
                        unita: package.dosageUnit,
                        volume: package.volume
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.packageLabel.localizedCaseInsensitiveCompare(rhs.packageLabel) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func searchSelections(
        query: String,
        in selections: [CatalogSelection],
        excludingIdentityKeys: Set<String> = [],
        limit: Int = 40
    ) -> [CatalogSelection] {
        let normalizedQuery = normalizeText(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return selections
            .filter { selection in
                !excludingIdentityKeys.contains(identityKey(for: selection))
                && matches(selection: selection, normalizedQuery: normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name {
                    return lhs.packageLabel.localizedCaseInsensitiveCompare(rhs.packageLabel) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    func matchSelection(fromRecognizedText text: String) -> CatalogSelection? {
        let normalizedText = normalizeScannerText(text)
        let textTokens = tokenSet(fromScannerText: normalizedText)
        let textNumbers = numberTokens(fromScannerText: normalizedText)

        var best: (selection: CatalogSelection, score: Double, singlePackage: Bool)?

        for record in loadRecords() {
            let medicineScore = scoreMedicine(
                record: record,
                normalizedText: normalizedText,
                tokens: textTokens,
                numbers: textNumbers
            )
            if medicineScore < 4 { continue }

            for package in record.packages {
                let packageScore = scorePackage(
                    package: package,
                    normalizedText: normalizedText,
                    tokens: textTokens,
                    numbers: textNumbers
                )
                let total = medicineScore + packageScore
                if best == nil || total > best!.score {
                    let selection = CatalogSelection(
                        id: package.id,
                        name: record.name,
                        principle: record.principle,
                        requiresPrescription: package.requiresPrescription,
                        packageLabel: package.label,
                        units: max(1, package.units),
                        tipologia: package.tipologia,
                        valore: package.dosageValue,
                        unita: package.dosageUnit,
                        volume: package.volume
                    )
                    best = (selection, total, record.packages.count == 1)
                }
            }
        }

        guard let best else { return nil }
        let threshold = best.singlePackage ? 6.0 : 8.0
        return best.score >= threshold ? best.selection : nil
    }

    func identityKey(for selection: CatalogSelection) -> String {
        identityKey(name: selection.name, principle: selection.principle)
    }

    func identityKey(name: String, principle: String) -> String {
        let normalizedName = normalizeText(name)
        let normalizedPrinciple = normalizeText(principle)
        if normalizedPrinciple.isEmpty {
            return normalizedName
        }
        return "\(normalizedName)|\(normalizedPrinciple)"
    }

    func inCabinetIdentityKeys(from medicines: [Medicine]) -> Set<String> {
        Set(
            medicines
                .filter(\.in_cabinet)
                .map { medicine in
                    identityKey(name: medicine.nome, principle: medicine.principio_attivo)
                }
        )
    }

    func naturalPackageLabel(for selection: CatalogSelection) -> String {
        var parts: [String] = []
        if selection.units > 0 {
            parts.append("\(selection.units) unità")
        }
        if selection.valore > 0 {
            let unit = selection.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(unit.isEmpty ? "\(selection.valore)" : "\(selection.valore) \(unit)")
        }
        if !selection.volume.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(selection.volume)
        }
        if parts.isEmpty {
            let raw = selection.packageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? "Confezione" : titleCase(raw)
        }
        return parts.joined(separator: " • ")
    }

    func normalizeText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let cleaned = folded.replacingOccurrences(
            of: "[^A-Za-z0-9]",
            with: " ",
            options: .regularExpression
        )
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func titleCase(_ text: String) -> String {
        text
            .lowercased()
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private func matches(selection: CatalogSelection, normalizedQuery: String) -> Bool {
        let name = normalizeText(selection.name)
        let principle = normalizeText(selection.principle)
        let package = normalizeText(selection.packageLabel)
        return name.contains(normalizedQuery)
            || principle.contains(normalizedQuery)
            || package.contains(normalizedQuery)
    }

    private func loadRecords() -> [CatalogRecord] {
        guard let object = loadCatalogObject(),
              let entries = catalogEntries(from: object) else {
            return []
        }

        var records: [CatalogRecord] = []
        records.reserveCapacity(min(entries.count, 1200))

        for entry in entries.prefix(1200) {
            let medicineInfo = entry["medicinale"] as? [String: Any]
            let info = entry["informazioni"] as? [String: Any]
            let principles = entry["principi"] as? [String: Any]

            let rawName = (medicineInfo?["denominazioneMedicinale"] as? String)
                ?? (entry["denominazioneMedicinale"] as? String)
                ?? (entry["titolo"] as? String)
                ?? catalogStringArray(from: entry["principiAttiviIt"]).first
                ?? catalogStringArray(from: principles?["principiAttiviIt"]).first
                ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let principleValues = deduplicatedCatalogValues(
                catalogStringArray(from: entry["principiAttiviIt"])
                + catalogStringArray(from: principles?["principiAttiviIt"])
                + catalogStringArray(from: entry["descrizioneAtc"])
            )
            let principle = principleValues.isEmpty ? name : principleValues.joined(separator: ", ")

            let medicineCodes: [String] = [
                medicineInfo?["codiceMedicinale"] as? String,
                (medicineInfo?["aic6"] as? Int).map(String.init),
                entry["aic6"] as? String
            ].compactMap { $0 }

            let packages = entry["confezioni"] as? [[String: Any]] ?? []
            guard !packages.isEmpty else { continue }

            let dosageSource = (info?["descrizioneFormaDosaggio"] as? String)
                ?? (entry["descrizioneFormaDosaggio"] as? String)
            let dosage = parseDosage(from: dosageSource)

            let catalogPackages = packages.map { package in
                let rawPackageLabel = (package["denominazionePackage"] as? String) ?? "Confezione"
                let packageLabel = rawPackageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let packageId = (package["idPackage"] as? String)
                    ?? (entry["id"] as? String)
                    ?? UUID().uuidString
                let packageCodes: [String] = [
                    package["aic"] as? String,
                    package["idPackage"] as? String
                ].compactMap { $0 }

                return CatalogPackageRecord(
                    id: packageId,
                    label: packageLabel.isEmpty ? "Confezione" : packageLabel,
                    units: max(1, extractUnitCount(from: packageLabel)),
                    tipologia: packageLabel.isEmpty ? "Confezione" : packageLabel,
                    dosageValue: dosage.value,
                    dosageUnit: dosage.unit,
                    volume: extractVolume(from: packageLabel),
                    requiresPrescription: catalogRequiresPrescription(package),
                    codes: packageCodes
                )
            }

            records.append(
                CatalogRecord(
                    name: name,
                    principle: principle,
                    codes: medicineCodes,
                    packages: catalogPackages
                )
            )
        }

        return records
    }

    private func loadCatalogObject() -> Any? {
        let data: Data? = {
            if let fullURL = bundle.url(forResource: "medicinali", withExtension: "json"),
               let fullData = try? Data(contentsOf: fullURL) {
                return fullData
            }
            if let fallbackURL = bundle.url(forResource: "medicinale_example", withExtension: "json"),
               let fallbackData = try? Data(contentsOf: fallbackURL) {
                return fallbackData
            }
            return nil
        }()

        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func catalogEntries(from object: Any) -> [[String: Any]]? {
        if let array = object as? [[String: Any]] {
            return array
        }
        if let dictionary = object as? [String: Any] {
            return [dictionary]
        }
        return nil
    }

    private func catalogStringArray(from value: Any?) -> [String] {
        guard let value else { return [] }
        if let array = value as? [String] {
            return array
        }
        if let string = value as? String {
            return [string]
        }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? String }
        }
        return []
    }

    private func deduplicatedCatalogValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = normalizeText(trimmed)
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private func catalogRequiresPrescription(_ package: [String: Any]) -> Bool {
        if catalogBoolValue(package["flagPrescrizione"] ?? package["prescrizione"]) {
            return true
        }
        if let classe = (package["classeFornitura"] as? String)?.uppercased(),
           ["RR", "RRL", "OSP"].contains(classe) {
            return true
        }
        let descriptions = catalogStringArray(from: package["descrizioneRf"])
        if descriptions.contains(where: catalogRequiresPrescriptionDescription) {
            return true
        }
        return false
    }

    private func catalogRequiresPrescriptionDescription(_ description: String) -> Bool {
        let normalized = description
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains("non soggetto")
            || normalized.contains("senza ricetta")
            || normalized.contains("senza prescrizione")
            || normalized.contains("non richiede") {
            return false
        }
        return normalized.contains("prescrizione") || normalized.contains("ricetta")
    }

    private func catalogBoolValue(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let bool = value as? Bool { return bool }
        if let int = value as? Int { return int != 0 }
        if let int = value as? Int32 { return int != 0 }
        if let number = value as? NSNumber { return number.intValue != 0 }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "si", "y", "t"].contains(normalized)
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
            guard !digitString.isEmpty, let parsed = Int32(digitString) else { continue }
            value = parsed
            if index + 1 < tokens.count {
                let possibleUnit = tokens[index + 1]
                if possibleUnit.rangeOfCharacter(from: .letters) != nil || possibleUnit.contains("/") {
                    unit = String(possibleUnit)
                }
            }
            break
        }

        return (value, unit)
    }

    private func extractUnitCount(from text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "\\d+") else { return 0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last,
              let range = Range(last.range, in: text),
              let value = Int(text[range]) else {
            return 0
        }
        return value
    }

    private func extractVolume(from text: String) -> String {
        let uppercase = text.uppercased()
        guard let regex = try? NSRegularExpression(pattern: "\\d+\\s*(ML|L)") else { return "" }
        let range = NSRange(location: 0, length: (uppercase as NSString).length)
        guard let match = regex.firstMatch(in: uppercase, range: range),
              let matchRange = Range(match.range, in: uppercase) else {
            return ""
        }
        return uppercase[matchRange].lowercased()
    }

    private func normalizeScannerText(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: .current)
        let upper = folded.uppercased()
        let cleaned = upper.replacingOccurrences(of: "[^A-Z0-9]", with: " ", options: .regularExpression)
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(fromScannerText normalized: String) -> Set<String> {
        let tokens = normalized.split(separator: " ")
        let filtered = tokens.map(String.init).filter { token in
            if token.allSatisfy(\.isNumber) { return true }
            return token.count > 1
        }
        return Set(filtered)
    }

    private func numberTokens(fromScannerText normalized: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: "\\d+") else { return [] }
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        var results = Set<String>()
        for match in matches {
            if let range = Range(match.range, in: normalized) {
                results.insert(String(normalized[range]))
            }
        }
        return results
    }

    private func scoreMedicine(
        record: CatalogRecord,
        normalizedText: String,
        tokens: Set<String>,
        numbers: Set<String>
    ) -> Double {
        let nameNorm = normalizeScannerText(record.name)
        guard !nameNorm.isEmpty else { return 0 }
        let nameTokens = tokenSet(fromScannerText: nameNorm)
        let overlap = nameTokens.intersection(tokens).count
        let ratio = Double(overlap) / Double(max(1, nameTokens.count))
        var score = Double(overlap) * 1.5 + ratio * 2.0
        if normalizedText.contains(nameNorm) {
            score += 6.0
        }
        for code in record.codes where numbers.contains(code) {
            score += 4.0
        }
        return score
    }

    private func scorePackage(
        package: CatalogPackageRecord,
        normalizedText: String,
        tokens: Set<String>,
        numbers: Set<String>
    ) -> Double {
        let labelNorm = normalizeScannerText(package.label)
        let labelTokens = tokenSet(fromScannerText: labelNorm)
        let overlap = labelTokens.intersection(tokens).count
        let labelNumbers = numberTokens(fromScannerText: labelNorm)
        let numberOverlap = labelNumbers.intersection(numbers).count
        var score = Double(overlap) * 1.0 + Double(numberOverlap) * 2.0
        if !labelNorm.isEmpty && normalizedText.contains(labelNorm) {
            score += 4.0
        }
        for code in package.codes where numbers.contains(code) {
            score += 5.0
        }
        return score
    }
}

private struct CatalogRecord {
    let name: String
    let principle: String
    let codes: [String]
    let packages: [CatalogPackageRecord]
}

private struct CatalogPackageRecord {
    let id: String
    let label: String
    let units: Int
    let tipologia: String
    let dosageValue: Int32
    let dosageUnit: String
    let volume: String
    let requiresPrescription: Bool
    let codes: [String]
}
