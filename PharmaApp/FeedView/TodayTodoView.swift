import SwiftUI
import CoreData

struct TodayTodoItem: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case therapy
        case purchase
        case prescription
        case upcoming
        case pharmacy

        var label: String {
            switch self {
            case .therapy: return "Terapie di oggi"
            case .purchase: return "Acquisti"
            case .prescription: return "Ricette"
            case .upcoming: return "Prossimi giorni"
            case .pharmacy: return "Farmacia"
            }
        }

        var icon: String {
            switch self {
            case .therapy: return "pills.circle"
            case .purchase: return "cart.badge.plus"
            case .prescription: return "doc.text.magnifyingglass"
            case .upcoming: return "calendar"
            case .pharmacy: return "mappin.and.ellipse"
            }
        }

        var tint: Color {
            switch self {
            case .therapy: return .blue
            case .purchase: return .green
            case .prescription: return .orange
            case .upcoming: return .purple
            case .pharmacy: return .teal
            }
        }

        static var displayOrder: [Category] {
            [.therapy, .purchase, .prescription, .upcoming, .pharmacy]
        }
    }

    let id: String
    let title: String
    let detail: String?
    let category: Category
    let medicineID: NSManagedObjectID?
}

struct TodayTodoBuilder {
    static func makeTodos(from context: AIInsightsContext, medicines: [Medicine], urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem] {
        var items: [TodayTodoItem] = []
        let medIndex: [String: Medicine] = {
            var dict: [String: Medicine] = [:]
            for med in medicines {
                dict[med.nome.lowercased()] = med
            }
            return dict
        }()

        for highlight in context.therapyHighlights {
            guard let parsed = parseHighlight(highlight) else { continue }
            let detailRaw = parsed.detail.flatMap { normalizedTimeDetail(from: $0) } ?? parsed.detail
            items.append(
                TodayTodoItem(
                    id: "therapy|\(parsed.id)",
                    title: parsed.name,
                    detail: detailRaw,
                    category: .therapy,
                    medicineID: medIndex[parsed.name.lowercased()]?.objectID
                )
            )
        }

        for highlight in context.purchaseHighlights {
            guard let parsed = parsePurchaseHighlight(highlight) else { continue }
            let medID = medIndex[parsed.name.lowercased()]?.objectID
            let detailWithUrgency = detailForAction(base: parsed.detail, medicine: medIndex[parsed.name.lowercased()], urgentIDs: urgentIDs)
            items.append(
                TodayTodoItem(
                    id: "purchase|\(parsed.name.lowercased())|\(parsed.status.rawValue)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .purchase,
                    medicineID: medID
                )
            )
        }

        for highlight in context.prescriptionHighlights {
            guard let parsed = parseHighlight(highlight) else { continue }
            let medID = medIndex[parsed.name.lowercased()]?.objectID
            let med = medIndex[parsed.name.lowercased()]
            let baseDetail: String?
            if let med, med.hasNewPrescritpionRequest() {
                baseDetail = parsed.detail
            } else {
                baseDetail = nil
            }
            let detailWithUrgency = detailForAction(base: baseDetail, medicine: med, urgentIDs: urgentIDs)
            items.append(
                TodayTodoItem(
                    id: "prescription|\(parsed.id)",
                    title: parsed.name,
                    detail: detailWithUrgency,
                    category: .prescription,
                    medicineID: medID
                )
            )
        }

        return items
    }

    private static func parseHighlight(_ highlight: String) -> (id: String, name: String, detail: String?)? {
        let components = highlight.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let name = components.first, !name.isEmpty else { return nil }
        let detail = components.count > 1 ? components[1] : nil
        let identifier = "\(name.lowercased())|\(detail?.lowercased() ?? "")"
        return (identifier, name, detail)
    }

    private enum PurchaseStatus: String {
        case waitingRx
        case normal
    }

    private static func parsePurchaseHighlight(_ highlight: String) -> (id: String, name: String, detail: String?, status: PurchaseStatus)? {
        let trimmed = highlight.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let raw = components.first, !raw.isEmpty else { return nil }
        var detail = components.count > 1 ? components[1] : nil
        // highlight formati come:
        // "compra Nome (in attesa della ricetta)"
        // "compra Nome — chiedi ricetta"
        // "compra Nome: copertura per X"
        // oppure "Nome: copertura per X"
        let lower = raw.lowercased()
        let name: String
        if lower.hasPrefix("compra ") {
            name = raw.dropFirst("compra ".count).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let status: PurchaseStatus = (raw.contains("attesa della ricetta") || trimmed.lowercased().contains("ricetta")) ? .waitingRx : .normal
        if status == .waitingRx && (detail == nil || detail?.isEmpty == true) {
            detail = "In attesa della ricetta"
        }
        let identifier = "\(name.lowercased())|\(status.rawValue)"
        return (identifier, name, detail, status)
    }

    private static func detailForAction(base: String?, medicine: Medicine?, urgentIDs: Set<NSManagedObjectID>) -> String? {
        var parts: [String] = []
        if let base, !base.isEmpty {
            parts.append(base)
        }
        if let med = medicine, !urgentIDs.contains(med.objectID), let dose = nextDoseTodayText(for: med) {
            parts.append("Oggi: \(dose)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private static func nextDoseTodayText(for medicine: Medicine) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let calendar = Calendar.current
        let upcoming = therapies.compactMap { therapy -> Date? in
            let rule = rec.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
            return rec.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?)
        }.sorted().first
        guard let next = upcoming, calendar.isDateInToday(next) else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: next)
    }

    private static func normalizedTimeDetail(from detail: String) -> String? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^[0-9]{1,2}:[0-9]{2}$"
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            return "alle \(trimmed)"
        }
        return nil
    }
}

struct TodayTodoListView: View {
    let items: [TodayTodoItem]
    @Binding var completedIDs: Set<String>
    let urgentIDs: Set<NSManagedObjectID>
    var onPrescriptionTap: ((TodayTodoItem) -> Void)?
    var onPurchaseTap: ((TodayTodoItem) -> Void)?

    var body: some View {
        ForEach(items) { item in
            todoRow(for: item)
        }
    }

    private struct TherapyBucket: Identifiable {
        let id = UUID()
        let label: String
        let sortValue: Int?
        let items: [TodayTodoItem]
    }

    private func buckets(for therapies: [TodayTodoItem]) -> [TherapyBucket] {
        guard !therapies.isEmpty else { return [] }
        var groups: [String: (sort: Int?, items: [TodayTodoItem])] = [:]
        for item in therapies {
            let key = timeLabel(for: item)
            let sort = timeSortValue(for: item)
            var current = groups[key] ?? (sort: sort, items: [])
            current.items.append(item)
            if current.sort == nil { current.sort = sort }
            groups[key] = current
        }
        return groups.map { TherapyBucket(label: $0.key, sortValue: $0.value.sort, items: $0.value.items) }
            .sorted { lhs, rhs in
                switch (lhs.sortValue, rhs.sortValue) {
                case let (l?, r?):
                    return l < r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return lhs.label < rhs.label
                }
            }
    }

    private func timeLabel(for item: TodayTodoItem) -> String {
        guard let detail = item.detail else { return "Senza orario" }
        if let match = timeComponents(from: detail) {
            return String(format: "%02d:%02d", match.hour, match.minute)
        }
        return "Senza orario"
    }

    private func timeSortValue(for item: TodayTodoItem) -> Int? {
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        return match.hour * 60 + match.minute
    }

    private func timeComponents(from detail: String) -> (hour: Int, minute: Int)? {
        let pattern = "([0-9]{1,2}):([0-9]{2})"
        guard let range = detail.range(of: pattern, options: .regularExpression) else { return nil }
        let substring = String(detail[range])
        let parts = substring.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let hour = parts[0]
        let minute = parts[1]
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }

    private let iconColumnWidth: CGFloat = 24

    private func timelineRow(for item: TodayTodoItem, isFirst: Bool) -> some View {
        let isCompleted = completedIDs.contains(item.id)
        return Button {
            handleTap(for: item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon(for: item.category))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.category.tint)
                    .frame(width: iconColumnWidth, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    Text(naturalText(for: item))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isCompleted ? item.category.tint : Color.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    private func icon(for category: TodayTodoItem.Category) -> String {
        switch category {
        case .therapy: return "pills"
        case .purchase: return "cart.badge.plus"
        case .prescription: return "doc.text"
        case .upcoming: return "calendar"
        case .pharmacy: return "mappin"
        }
    }

    private func todoRow(for item: TodayTodoItem) -> some View {
        let isCompleted = completedIDs.contains(item.id)
        return Button {
            handleTap(for: item)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon(for: item.category))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.category.tint)
                    .frame(width: 24, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(naturalText(for: item))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isCompleted ? item.category.tint : Color.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    private func toggleCompletion(for item: TodayTodoItem) {
        if completedIDs.contains(item.id) {
            completedIDs.remove(item.id)
        } else {
            completedIDs.insert(item.id)
        }
    }

    private func isUrgent(_ item: TodayTodoItem) -> Bool {
        guard let id = item.medicineID else { return false }
        return urgentIDs.contains(id)
    }

    private func naturalText(for item: TodayTodoItem) -> String {
        let name = item.title
        let detail = item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch item.category {
        case .therapy:
            if detail.isEmpty { return "Assumi \(name)" }
            if let time = extractTime(from: detail) {
                return "Assumi \(name) alle \(time)"
            }
            return "Assumi \(name) \(detail)"

        case .purchase:
            if detail.isEmpty { return "Compra \(name)" }
            return "Compra \(name): \(detail)"

        case .prescription:
            if detail.isEmpty { return "Chiedi al medico la ricetta di \(name)" }
            return "Chiedi al medico la ricetta di \(name): \(detail)"

        case .upcoming, .pharmacy:
            return name
        }
    }

    private func handleTap(for item: TodayTodoItem) {
        switch item.category {
        case .prescription:
            if let onPrescriptionTap { onPrescriptionTap(item) } else { toggleCompletion(for: item) }
        case .purchase:
            if let onPurchaseTap { onPurchaseTap(item) } else { toggleCompletion(for: item) }
        default:
            toggleCompletion(for: item)
        }
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }

    func matchesRegex(_ pattern: String) -> Bool {
        range(of: pattern, options: .regularExpression) != nil
    }
}

private func extractTime(from detail: String) -> String? {
    let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    let pattern = "^[0-9]{1,2}:[0-9]{2}$"
    return trimmed.matchesRegex(pattern) ? trimmed : nil
}
