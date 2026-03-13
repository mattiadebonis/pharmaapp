import Foundation

struct CatalogSelectionRepository {
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

    func matchSelection(
        fromRecognizedText text: String,
        candidates: [CatalogSelection]
    ) -> CatalogSelection? {
        let normalizedText = normalizeScannerText(text)
        let textTokens = tokenSet(fromScannerText: normalizedText)
        let textNumbers = numberTokens(fromScannerText: normalizedText)

        let groupedByMedicine = Dictionary(grouping: candidates, by: identityKey(for:))
        var best: (selection: CatalogSelection, score: Double, singlePackage: Bool)?

        for selection in candidates {
            let medicineScore = scoreMedicine(
                selection: selection,
                normalizedText: normalizedText,
                tokens: textTokens,
                numbers: textNumbers
            )
            if medicineScore < 4 { continue }

            let packageScore = scorePackage(
                selection: selection,
                normalizedText: normalizedText,
                tokens: textTokens,
                numbers: textNumbers
            )
            let total = medicineScore + packageScore
            if best == nil || total > best!.score {
                best = (
                    selection,
                    total,
                    (groupedByMedicine[identityKey(for: selection)]?.count ?? 0) <= 1
                )
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
        selection: CatalogSelection,
        normalizedText: String,
        tokens: Set<String>,
        numbers: Set<String>
    ) -> Double {
        let nameNorm = normalizeScannerText(selection.name)
        guard !nameNorm.isEmpty else { return 0 }
        let nameTokens = tokenSet(fromScannerText: nameNorm)
        let overlap = nameTokens.intersection(tokens).count
        let ratio = Double(overlap) / Double(max(1, nameTokens.count))
        var score = Double(overlap) * 1.5 + ratio * 2.0
        if normalizedText.contains(nameNorm) {
            score += 6.0
        }
        for code in selectionMatchCodes(for: selection) where numbers.contains(code) {
            score += 4.0
        }
        return score
    }

    private func scorePackage(
        selection: CatalogSelection,
        normalizedText: String,
        tokens: Set<String>,
        numbers: Set<String>
    ) -> Double {
        let labelNorm = normalizeScannerText(selection.packageLabel)
        let labelTokens = tokenSet(fromScannerText: labelNorm)
        let overlap = labelTokens.intersection(tokens).count
        let labelNumbers = numberTokens(fromScannerText: labelNorm)
        let numberOverlap = labelNumbers.intersection(numbers).count
        var score = Double(overlap) * 1.0 + Double(numberOverlap) * 2.0
        if !labelNorm.isEmpty && normalizedText.contains(labelNorm) {
            score += 4.0
        }
        for code in selectionMatchCodes(for: selection) where numbers.contains(code) {
            score += 5.0
        }
        return score
    }

    private func selectionMatchCodes(for selection: CatalogSelection) -> [String] {
        [selection.catalogCode, selection.productKey, selection.packageKey]
            .compactMap { $0 }
            .flatMap { code in
                code.split(whereSeparator: { !$0.isNumber }).map(String.init)
            }
    }
}
