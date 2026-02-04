import SwiftUI
import CoreData

extension TodayTodoCategory {
    var label: String {
        switch self {
        case .therapy: return "Terapie di oggi"
        case .monitoring: return "Monitoraggi"
        case .missedDose: return "Dose mancate"
        case .purchase: return "Acquisti"
        case .deadline: return "Scadenze"
        case .prescription: return "Ricette"
        case .upcoming: return "Prossimi giorni"
        case .pharmacy: return "Farmacia"
        }
    }

    var icon: String {
        switch self {
        case .therapy: return "pills.circle"
        case .monitoring: return "waveform.path.ecg"
        case .missedDose: return "exclamationmark.triangle"
        case .purchase: return "cart.badge.plus"
        case .deadline: return "calendar.badge.exclamationmark"
        case .prescription: return "doc.text.magnifyingglass"
        case .upcoming: return "calendar"
        case .pharmacy: return "mappin.and.ellipse"
        }
    }

    var tint: Color {
        switch self {
        case .therapy: return .blue
        case .monitoring: return .indigo
        case .missedDose: return .red
        case .purchase: return .green
        case .deadline: return .orange
        case .prescription: return .orange
        case .upcoming: return .purple
        case .pharmacy: return .teal
        }
    }
}

extension TodayTodoItem {
    init?(todo: Todo) {
        guard let category = TodayTodoCategory(rawValue: todo.category) else { return nil }
        self.init(
            id: todo.source_id,
            title: todo.title,
            detail: todo.detail,
            category: category,
            medicineId: todo.medicine.map { MedicineId($0.id) }
        )
    }
}
