import SwiftUI
import CoreData

struct UpcomingView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let sectionContentInset: CGFloat = 30
    private let sectionHeaderInset: CGFloat = 18

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Todo.due_at, ascending: true),
            NSSortDescriptor(keyPath: \Todo.category, ascending: true),
            NSSortDescriptor(keyPath: \Todo.title, ascending: true)
        ],
        animation: .default
    )
    private var allTodos: FetchedResults<Todo>

    private let cal = Calendar.current

    var body: some View {
        let groups = buildFlatGroups()
        List {
            ForEach(groups) { group in
                Section {
                    ForEach(group.todos, id: \.objectID) { todo in
                        TodayTodoRowView(
                            iconName: todo.category,
                            leadingTime: leadingTime(for: todo, dayDate: group.dayDate),
                            title: todo.title,
                            subtitle: todo.detail,
                            isCompleted: false,
                            hideToggle: true,
                            onToggle: {}
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: sectionContentInset, bottom: 0, trailing: sectionContentInset))
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Color.primary.opacity(0.12))
                    }
                } header: {
                    sectionHeader(for: group)
                        .padding(.horizontal, sectionHeaderInset)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacingIfAvailable(4)
        .listRowSpacing(0)
        .navigationTitle("Prossime")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: – Section header

    @ViewBuilder
    private func sectionHeader(for group: FlatGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if group.isFirstInDay {
                Text(group.dayLabel)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.top, group.dayDate == cal.startOfDay(for: Date()) ? 18 : 32)
                    .padding(.bottom, 2)
            }
            HStack(spacing: 6) {
                Text(group.categoryLabel)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(sectionHeaderColor)
                Text("\(group.todos.count)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                Spacer()
            }
            .padding(.top, group.isFirstInDay ? 10 : 18)
            .padding(.bottom, 6)
        }
        .textCase(nil)
    }

    // MARK: – Leading time

    private func leadingTime(for todo: Todo, dayDate: Date) -> String? {
        guard let dueAt = todo.due_at else { return nil }
        let cat = TodayTodoCategory(rawValue: todo.category)
        switch cat {
        case .purchase:
            let today = cal.startOfDay(for: Date())
            let days = cal.dateComponents([.day], from: today, to: dayDate).day ?? 0
            if days <= 0 { return "Oggi" }
            if days == 1 { return "entro\n1 giorno" }
            return "entro\n\(days) giorni"
        default:
            let c = cal.dateComponents([.hour, .minute], from: dueAt)
            guard let h = c.hour, let m = c.minute, !(h == 0 && m == 0) else { return nil }
            return String(format: "%02d:%02d", h, m)
        }
    }

    // MARK: – Grouping

    private struct FlatGroup: Identifiable {
        let id: String
        let dayDate: Date
        let dayLabel: String
        let isFirstInDay: Bool
        let categoryLabel: String
        let todos: [Todo]
    }

    private func buildFlatGroups() -> [FlatGroup] {
        let today = cal.startOfDay(for: Date())

        // Bucket todos by (day, category)
        typealias Key = (Date, String)
        var map: [Date: [String: [Todo]]] = [:]
        var undatedByCategory: [String: [Todo]] = [:]

        for todo in allTodos {
            if let dueAt = todo.due_at {
                let day = cal.startOfDay(for: dueAt)
                guard day >= today else { continue }
                map[day, default: [:]][todo.category, default: []].append(todo)
            } else {
                undatedByCategory[todo.category, default: []].append(todo)
            }
        }

        let categoryOrder: [TodayTodoCategory] = [
            .therapy, .purchase, .monitoring,
            .missedDose, .deadline, .prescription, .pharmacy, .upcoming
        ]

        func flatGroups(from byCategory: [String: [Todo]], dayDate: Date, dayLabel: String) -> [FlatGroup] {
            var result: [FlatGroup] = []
            var isFirst = true
            for cat in categoryOrder {
                guard let todos = byCategory[cat.rawValue], !todos.isEmpty else { continue }
                result.append(FlatGroup(
                    id: "\(dayDate.timeIntervalSince1970)-\(cat.rawValue)",
                    dayDate: dayDate,
                    dayLabel: dayLabel,
                    isFirstInDay: isFirst,
                    categoryLabel: sectionLabel(for: cat),
                    todos: todos
                ))
                isFirst = false
            }
            // unknown categories
            let knownRaw = Set(categoryOrder.map(\.rawValue))
            let unknownItems = byCategory.filter { !knownRaw.contains($0.key) }.values.flatMap { $0 }
            if !unknownItems.isEmpty {
                result.append(FlatGroup(
                    id: "\(dayDate.timeIntervalSince1970)-unknown",
                    dayDate: dayDate,
                    dayLabel: dayLabel,
                    isFirstInDay: isFirst,
                    categoryLabel: "Altro",
                    todos: unknownItems
                ))
            }
            return result
        }

        var result: [FlatGroup] = []
        for day in map.keys.sorted() {
            result += flatGroups(from: map[day]!, dayDate: day, dayLabel: dayLabel(for: day, today: today))
        }
        if !undatedByCategory.isEmpty {
            result += flatGroups(from: undatedByCategory, dayDate: .distantFuture, dayLabel: "Senza scadenza")
        }
        return result
    }

    private func dayLabel(for date: Date, today: Date) -> String {
        if cal.isDate(date, inSameDayAs: today) { return "Oggi" }
        if let tmr = cal.date(byAdding: .day, value: 1, to: today),
           cal.isDate(date, inSameDayAs: tmr) { return "Domani" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "it_IT")
        fmt.dateFormat = "EEEE d MMM"
        return fmt.string(from: date).capitalized
    }

    private func sectionLabel(for category: TodayTodoCategory) -> String {
        switch category {
        case .therapy:    return "Da assumere"
        case .purchase:   return "Da comprare"
        case .monitoring: return "Monitoraggi"
        case .missedDose: return "Dosi mancate"
        case .deadline:   return "Scadenze"
        case .prescription: return "Ricette"
        case .upcoming:   return "Prossimi"
        case .pharmacy:   return "Farmacia"
        }
    }

    // MARK: – Colors

    private var sectionHeaderColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : Color.primary.opacity(0.45)
    }
}
