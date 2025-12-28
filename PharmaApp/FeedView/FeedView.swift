//
//  FeedView.swift
//  PharmaApp
//
//  Created by Mattia De Bonis on 02/01/25.
//

import SwiftUI
import CoreData
import MapKit
import CoreLocation
import UIKit

struct FeedView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.openURL) private var openURL
    enum Mode {
        case insights
        case medicines
    }

    private var todayNavigationTitle: String {
        "Oggi"
    }

    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Cabinet.extractCabinets())
    private var cabinets: FetchedResults<Cabinet>
    @ObservedObject var viewModel: FeedViewModel
    let mode: Mode
    @State private var selectedMedicine: Medicine?
    @State private var activeCabinetID: NSManagedObjectID?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @StateObject private var locationVM = LocationSearchViewModel()
    @State private var medicineToMove: Medicine?
    @State private var completedTodoIDs: Set<String> = []
    @State private var prescriptionEmailMedicine: Medicine?
    @State private var prescriptionToConfirm: Medicine?
    @State private var selectedMapItem: MKMapItem?
    @State private var completionToastItemID: String?
    @State private var completionToastWorkItem: DispatchWorkItem?
    @State private var completionUndoLogID: NSManagedObjectID?
    @State private var completedBlockedSubtasks: Set<String> = []
    @State private var pendingPrescriptionMedIDs: Set<NSManagedObjectID> = []
    @State private var collapsedSections: Set<String> = []

    init(viewModel: FeedViewModel, mode: Mode = .medicines) {
        self.viewModel = viewModel
        self.mode = mode
    }
    
    var body: some View {
        let sections = computeSections()
        let insightsContext = buildInsightsContext(for: sections)
        let content = Group {
            switch mode {
            case .insights:
                insightsScreen(sections: sections, insightsContext: insightsContext)
            case .medicines:
                medicinesScreen(sections: sections)
            }
        }
        .onAppear { locationVM.ensureStarted() }

        mapItemWrappedView(content)
    }

    private func orderedRows(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> [(medicine: Medicine, section: MedicineRowView.RowSection)] {
        sections.purchase.map { ($0, .purchase) } +
        sections.oggi.map { ($0, .tuttoOk) } +
        sections.ok.map { ($0, .tuttoOk) }
    }

    private func toggleSection(_ label: String) {
        if collapsedSections.contains(label) {
            collapsedSections.remove(label)
        } else {
            collapsedSections.insert(label)
        }
    }

    @ViewBuilder
    private func insightsScreen(sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]), insightsContext: AIInsightsContext?) -> some View {
        let urgentIDs = urgentMedicineIDs(for: sections)
        let todos = buildTodoItems(from: insightsContext, urgentIDs: urgentIDs)
        let sorted = sortTodos(todos)
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let filtered = sorted.filter { item in
            if item.category == .prescription, let med = medicine(for: item) {
                return !needsPrescriptionBeforePurchase(med, recurrenceManager: rec)
            }
            return true
        }
        let pendingItems = filtered.filter { !completedTodoIDs.contains($0.id) }
        let timeGroups = timeGroups(from: pendingItems)

        List {
            ForEach(Array(timeGroups.enumerated()), id: \.element.id) { entry in
                let group = entry.element
                let isLast = entry.offset == timeGroups.count - 1
                let isCollapsed = collapsedSections.contains(group.label)
                Section {
                    if !isCollapsed {
                        if shouldShowPharmacyCard(for: group) {
                            pharmacySuggestionCard()
                                .listRowInsets(EdgeInsets(top: 6, leading: 48, bottom: 8, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(group.items) { item in
                            todoListRow(
                                for: item,
                                isCompleted: completedTodoIDs.contains(item.id)
                            )
                        }
                    }
                } header: {
                    Button {
                        toggleSection(group.label)
                    } label: {
                        HStack(spacing: 8) {
                            Text(sectionTitle(for: group))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .textCase(nil)
                            Text("\(group.items.count)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, group.label == "Rifornimenti" ? 6 : 12)
                    .padding(.bottom, group.label == "Rifornimenti" ? 4 : 0)
                    Divider()
                        .padding(.leading, 48)
                        .padding(.trailing, 16)
                        .opacity(0.35)
                }
                
            }
        }
        .overlay {
            if pendingItems.isEmpty {
                insightsPlaceholder
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .safeAreaInset(edge: .bottom) {
            if completionToastItemID != nil {
                completionToastView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $prescriptionToConfirm) { medicine in
            let doctor = prescriptionDoctorContact(for: medicine)
            let formattedName = formattedMedicineName(medicine.nome)
            let subject = "Richiesta ricetta per \(formattedName)"
            PrescriptionRequestConfirmationSheet(
                medicineName: formattedName,
                doctor: doctor,
                subject: subject,
                messageBody: prescriptionEmailBody(for: [medicine], doctorName: doctor.name),
                onDidSend: { viewModel.requestPrescription(for: medicine) }
            )
        }
        .sheet(item: $prescriptionEmailMedicine) { medicine in
            let doctor = prescriptionDoctorContact(for: medicine)
            let formattedName = formattedMedicineName(medicine.nome)
            let subject = "Richiesta ricetta per \(formattedName)"
            PrescriptionEmailSheet(
                doctor: doctor,
                subject: subject,
                messageBody: prescriptionEmailBody(for: [medicine], doctorName: doctor.name),
                onCopy: {
                    UIPasteboard.general.string = prescriptionEmailBody(for: [medicine], doctorName: doctor.name)
                },
                onDidSend: { viewModel.requestPrescription(for: medicine) }
            )
        }
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in
                if !newValue { selectedMedicine = nil }
            }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(
                        medicine: medicine,
                        package: package
                    )
                    .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
                    .presentationDragIndicator(.visible)
                } else {
                    VStack(spacing: 12) {
                        Text("Completa i dati del medicinale")
                            .font(.headline)
                        Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
        .navigationTitle(todayNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
    }

    private func sectionTitle(for group: TimeGroup) -> String {
        group.label
    }

    private func shouldShowPharmacyCard(for group: TimeGroup) -> Bool {
        guard group.label == "Rifornimenti" else { return false }
        return group.items.contains { $0.category == .purchase }
    }

    @ViewBuilder
    private func pharmacySuggestionCard() -> some View {
        let primaryLine = pharmacyPrimaryText()
        let statusLine = pharmacyStatusText()
        Button {
            if #available(iOS 17.0, *), let item = locationVM.pinItem?.mapItem {
                selectedMapItem = item
            } else {
                locationVM.openInMaps()
            }
        } label: {
            pharmacyHeader(primaryLine: primaryLine, statusLine: statusLine)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.6)
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    private func shortDistanceText() -> String? {
        guard let raw = locationVM.distanceString else { return nil }
        var parts = raw
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let first = parts.first {
            let cleaned = first.replacingOccurrences(of: "∼", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            parts[0] = cleaned
        }
        return parts.first
    }

    private func pharmacyPrimaryText() -> String {
        guard let pin = locationVM.pinItem else {
            return "Attiva la posizione per la farmacia consigliata"
        }
        var parts: [String] = []
        if let meters = distanceMetersText() {
            parts.append(meters)
        } else if let distance = shortDistanceText() {
            parts.append(distance)
        }
        parts.append(pin.title)
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func pharmacyHeader(primaryLine: String, statusLine: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(primaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let statusLine {
                    Text("·")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func pharmacyStatusText() -> String? {
        if locationVM.closingTimeText != nil {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == true {
            return "Aperta"
        }
        if let slot = locationVM.todayOpeningText {
            let now = Date()
            if OpeningHoursParser.activeInterval(from: slot, now: now) != nil {
                return "Aperta"
            }
        }
        return "Chiuso"
    }

    private func distanceMetersText() -> String? {
        guard let distance = locationVM.distanceMeters else { return nil }
        let formatter = MeasurementFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.unitStyle = .short
        formatter.numberFormatter.maximumFractionDigits = 1
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        return formatter.string(from: measurement)
    }

    @ViewBuilder
    private func medicinesScreen(sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> some View {
        let entries = shelfEntries(from: sections)
        List {

            if appVM.suggestNearestPharmacies {
                Section {
                    smartBannerCard
                        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                .listSectionSeparator(.hidden)
            }

            ForEach(entries) { entry in
                switch entry.kind {
                case .medicine(let med):
                    row(for: med)
                case .cabinet(let cabinet):
                    let meds = sortedMedicines(in: cabinet)
                    ZStack {
                        Button {
                            activeCabinetID = cabinet.objectID
                        } label: {
                            CabinetCardView(
                                cabinet: cabinet,
                                medicineCount: meds.count
                            )
                        }
                        .buttonStyle(.plain)
                        
                        NavigationLink(
                            destination: CabinetDetailView(cabinet: cabinet, medicines: meds, viewModel: viewModel),
                            isActive: Binding(
                                get: { activeCabinetID == cabinet.objectID },
                                set: { newValue in
                                    if !newValue { activeCabinetID = nil }
                                }
                            )
                        ) {
                            EmptyView()
                        }
                        .hidden()
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(0)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .id(logs.count)
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in
                if !newValue { selectedMedicine = nil }
            }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(
                        medicine: medicine,
                        package: package
                    )
                    .presentationDetents([.fraction(0.66), .large], selection: $detailSheetDetent)
                    .presentationDragIndicator(.visible)
                } else {
                    VStack(spacing: 12) {
                        Text("Completa i dati del medicinale")
                            .font(.headline)
                        Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
        .sheet(item: $medicineToMove) { medicine in
            MoveToCabinetSheet(
                medicine: medicine,
                cabinets: Array(cabinets),
                onSelect: { cabinet in
                    medicine.cabinet = cabinet
                    saveContext()
                }
            )
            .presentationDetents([.medium, .large])
        }
        .onChange(of: selectedMedicine) { newValue in
            if newValue == nil {
                viewModel.clearSelection()
            }
        }
    }

    private struct UpcomingStockEntry {
        let name: String
        let days: Int
    }


    private var smartBannerCard: some View {
        Button {
            appVM.isStocksIndexPresented = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rifornisci i farmaci in esaurimento")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Ti suggeriamo la farmacia più comoda in questo momento.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
        }
        .buttonStyle(.plain)
    }

    private func upcomingStockPanel(for medicines: [Medicine]) -> some View {
        let entries = upcomingStockEntries(for: medicines)
        return VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("Nessuna scorta da monitorare a breve.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Prossimamente")
                    .font(.headline)
                Text(upcomingStockSummary(from: entries))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingStockEntries(for medicines: [Medicine]) -> [UpcomingStockEntry] {
        guard !medicines.isEmpty else { return [] }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let entries = medicines.compactMap { medicine -> UpcomingStockEntry? in
            let name = (medicine.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            guard let days = estimatedCoverageDays(for: medicine, recurrenceManager: rec) else { return nil }
            let threshold = medicine.stockThreshold(option: options.first)
            let maxWindow = max(threshold + 5, threshold * 2)
            if days <= threshold { return nil }
            if days > maxWindow { return nil }
            return UpcomingStockEntry(name: name, days: days)
        }
        return entries.sorted { $0.days < $1.days }
    }
    
    private func sortedMedicines(in cabinet: Cabinet) -> [Medicine] {
        let base = cabinet.medicines.sorted { (lhs, rhs) in
            let left = (lhs.nome ?? "").lowercased()
            let right = (rhs.nome ?? "").lowercased()
            return left < right
        }
        return base
    }

    private func upcomingStockSummary(from entries: [UpcomingStockEntry]) -> String {
        guard !entries.isEmpty else {
            return "Tutte le scorte risultano stabili: controlla più avanti."
        }
        let limited = entries.prefix(3)
        var sentences: [String] = []
        for entry in limited {
            let daysText: String
            switch entry.days {
            case 0:
                daysText = "oggi stesso"
            case 1:
                daysText = "domani"
            case 2:
                daysText = "tra due giorni"
            default:
                daysText = "entro \(entry.days) giorni"
            }
            sentences.append("\(daysText.capitalized) programma il riordino di \(entry.name).")
        }
        if entries.count > limited.count {
            sentences.append("Altri \(entries.count - limited.count) medicinali restano da monitorare.")
        }
        return sentences.joined(separator: " ")
    }

    private func estimatedCoverageDays(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Int? {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard totalDaily > 0 else { return nil }
            let days = Int(floor(totalLeft / totalDaily))
            return max(days, 0)
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy(), remaining > 0 {
            return nil
        }
        return nil
    }

    private var insightsPlaceholder: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Color.mint.opacity(0.85))
                VStack(spacing: 10) {
                    Text("non è richiesta alcuna azione da parte tua")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    Text("Se ci sarà qualcosa da gestire, comparirà qui con il giusto preavviso: per ora puoi rilassarti.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var completionToastView: some View {
        HStack {
            Spacer()
            Button {
                undoLastCompletion()
            } label: {
                Label("Annulla", systemImage: "arrow.uturn.left")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                    )
            }
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private func buildTodoItems(from context: AIInsightsContext?, urgentIDs: Set<NSManagedObjectID>) -> [TodayTodoItem] {
        guard let context else { return [] }
        var items = TodayTodoBuilder.makeTodos(from: context, medicines: Array(medicines), urgentIDs: urgentIDs)
        items = items.filter { [.therapy, .purchase, .prescription].contains($0.category) }
        let blockedMedicineIDs: Set<NSManagedObjectID> = Set(
            items.compactMap { item in
                guard let info = blockedTherapyInfo(for: item) else { return nil }
                return info.medicine.objectID
            }
        )
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        if !blockedMedicineIDs.isEmpty {
            items = items.filter { item in
                guard let medID = item.medicineID else { return true }
                guard blockedMedicineIDs.contains(medID) else { return true }
                // Non duplichiamo il todo di prescrizione, ma lasciamo gli acquisti e la terapia
                if item.category == .prescription { return false }
                return true
            }
        }
        items = items.map { item in
            if item.category == .prescription,
               let med = medicine(for: item),
               needsPrescriptionBeforePurchase(med, recurrenceManager: rec) {
                return TodayTodoItem(
                    id: "purchase|rx|\(item.id)",
                    title: item.title,
                    detail: item.detail,
                    category: .purchase,
                    medicineID: item.medicineID
                )
            }
            return item
        }
        items = items.filter { item in
            if item.category == .purchase, let med = medicine(for: item) {
                if earliestDoseToday(for: med) != nil,
                   isOutOfStock(med, recurrenceManager: rec) {
                    return false
                }
            }
            return true
        }
        return items
    }

    private func sortTodos(_ items: [TodayTodoItem]) -> [TodayTodoItem] {
        items.sorted { lhs, rhs in
            let lTime = timeSortValue(for: lhs) ?? Int.max
            let rTime = timeSortValue(for: rhs) ?? Int.max
            if lTime != rTime { return lTime < rTime }
            if categoryRank(lhs.category) != categoryRank(rhs.category) {
                return categoryRank(lhs.category) < categoryRank(rhs.category)
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func matchesSmartQuery(_ medicine: Medicine, query: String) -> Bool {
        // Smart cabinets disabilitati
        return true
    }

    // Ordinamento personalizzato disabilitato (sortMenu rimosso)

    private func todoGroups(from items: [TodayTodoItem]) -> [TodoGroup] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return TodayTodoItem.Category.displayOrder.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return TodoGroup(category: category, items: items)
        }
    }

    
    private func timeSortValue(for item: TodayTodoItem) -> Int? {
        guard let date = todoTimeDate(for: item) else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
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

    private func todoTimeDate(for item: TodayTodoItem) -> Date? {
        if let medicine = medicine(for: item), let date = earliestDoseToday(for: medicine) {
            return date
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        let now = Date()
        return Calendar.current.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
    }

    private func earliestDoseToday(for medicine: Medicine) -> Date? {
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let calendar = Calendar.current
        let upcoming = therapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: rec)
        }
        return upcoming.filter { calendar.isDateInToday($0) }.sorted().first
    }

    private func timeLabel(for item: TodayTodoItem) -> String? {
        if item.category == .purchase {
            return nil
        }
        guard let date = todoTimeDate(for: item) else { return nil }
        return FeedView.insightsTimeFormatter.string(from: date)
    }

    private struct TimeGroup: Identifiable {
        let id = UUID()
        let label: String
        let sortValue: Int?
        let items: [TodayTodoItem]
    }
    
    private struct TodoGroup: Identifiable {
        var id: TodayTodoItem.Category { category }
        let category: TodayTodoItem.Category
        let items: [TodayTodoItem]
    }

    private func timeGroups(from items: [TodayTodoItem]) -> [TimeGroup] {
        var grouped: [String: (sort: Int?, items: [TodayTodoItem])] = [:]
        for item in items {
            let label = timeLabel(for: item) ?? "Rifornimenti"
            let sortValue = timeSortValue(for: item)
            var current = grouped[label] ?? (sort: sortValue, items: [])
            current.items.append(item)
            if let sortValue {
                current.sort = min(current.sort ?? sortValue, sortValue)
            }
            grouped[label] = current
        }

        return grouped.map { TimeGroup(label: $0.key, sortValue: $0.value.sort, items: $0.value.items) }
            .sorted { lhs, rhs in
                if lhs.label == "Rifornimenti", rhs.label != "Rifornimenti" { return false }
                if rhs.label == "Rifornimenti", lhs.label != "Rifornimenti" { return true }
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

    private func categoryRank(_ category: TodayTodoItem.Category) -> Int {
        TodayTodoItem.Category.displayOrder.firstIndex(of: category) ?? Int.max
    }

    private func urgentMedicineIDs(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> Set<NSManagedObjectID> {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let allMedicines = sections.purchase + sections.oggi + sections.ok
        let urgent = allMedicines.filter {
            isOutOfStock($0, recurrenceManager: rec) && hasUpcomingTherapyInNextWeek(for: $0, recurrenceManager: rec)
        }
        return Set(urgent.map { $0.objectID })
    }

    private func hasUpcomingTherapyInNextWeek(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else { return false }
        let now = Date()
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        for therapy in therapies {
            guard let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager) else {
                continue
            }
            if next <= limit { return true }
        }
        return false
    }

    @ViewBuilder
    private func todoListRow(for item: TodayTodoItem, isCompleted: Bool) -> some View {
        if let blocked = blockedTherapyInfo(for: item) {
            blockedTherapyCard(for: item, info: blocked)
        } else if item.category == .purchase,
                  let med = medicine(for: item),
                  needsPrescriptionBeforePurchase(med, recurrenceManager: RecurrenceManager(context: PersistenceController.shared.container.viewContext)) {
            purchaseWithPrescriptionRow(for: item, medicine: med, isCompleted: isCompleted)
        } else {
            let rowOpacity: Double = isCompleted ? 0.55 : 1
            let title = mainLineText(for: item)
            let subtitle = subtitleLine(for: item)
            let auxiliaryLine = auxiliaryLineText(for: item)
            let actionText = actionText(for: item, isCompleted: isCompleted)
            let titleColor: Color = isCompleted ? .secondary : .primary
            let actionLabelColor: Color = isCompleted ? .secondary : .primary
            let checkColor: Color = isCompleted ? .secondary : .secondary.opacity(0.4)
            let prescriptionMedicine = medicine(for: item)
            let isPrescriptionActionEnabled = item.category == .prescription && prescriptionTaskState(for: prescriptionMedicine, item: item) != .waitingResponse
            let iconName = actionIcon(for: item)

            HStack(alignment: .center, spacing: 12) {
                if item.category == .prescription {
                    prescriptionRowContent(
                        item: item,
                        titleColor: titleColor,
                        prescriptionMedicine: prescriptionMedicine,
                        iconName: iconName,
                        isEnabled: isPrescriptionActionEnabled,
                        onSend: {
                            handlePrescriptionTap(for: item, medicine: prescriptionMedicine, isEnabled: isPrescriptionActionEnabled)
                        }
                    )
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: iconName)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(actionLabelColor)
                            Text(actionText)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(actionLabelColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .layoutPriority(2)

                            Text(title)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(titleColor)
                                .multilineTextAlignment(.leading)
                                .lineLimit(nil)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            if let subtitle {
                                Text(subtitle)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let auxiliaryLine {
                                auxiliaryLine
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.leading, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    toggleCompletion(for: item)
                } label: {
                    Image(systemName: isCompleted ? "circle.fill" : "circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .listRowInsets(EdgeInsets(top: 4, leading: 48, bottom: 4, trailing: 16))
            .listRowSeparator(.hidden)
            .opacity(rowOpacity)
        }
    }

    private func handlePrescriptionTap(for item: TodayTodoItem, medicine: Medicine?, isEnabled: Bool) {
        guard item.category == .prescription, isEnabled, let medicine else { return }
        prescriptionEmailMedicine = medicine
    }

    private func mainLineText(for item: TodayTodoItem) -> String {
        let medicine = medicine(for: item)
        let formattedName = formattedMedicineName(medicine?.nome ?? item.title)
        return formattedName
    }

    private func prescriptionMainText(for item: TodayTodoItem, medicine: Medicine?) -> String {
        let medName = formattedMedicineName(medicine?.nome ?? item.title)
        let doctorName = medicine.map { prescriptionDoctorName(for: $0) } ?? "medico"
        return "Chiedi ricetta per \(medName) al medico \(doctorName)"
    }

    private func subtitleLine(for item: TodayTodoItem) -> String? {
        if item.category == .therapy, let med = medicine(for: item) {
            return personNameForTherapy(med)
        }
        return nil
    }

    private func auxiliaryLineText(for item: TodayTodoItem) -> Text? {
        if item.category == .purchase, let med = medicine(for: item) {
            var parts: [String] = []
            if isAwaitingPrescription(med) {
                let doctor = prescriptionDoctor(for: med)
                let docName = doctor.map(doctorFullName) ?? "medico"
                parts.append("Richiesta ricetta inviata a \(docName)")
            }
            if let stock = stockSubtitle(for: med) {
                parts.append(stock)
            }
            guard !parts.isEmpty else { return nil }
            return Text(parts.joined(separator: "\n"))
        }
        return nil
    }

    private func personNameForTherapy(_ medicine: Medicine) -> String? {
        if let info = nextDoseTodayInfo(for: medicine), let person = info.personName, !person.isEmpty {
            return person
        }
        if let therapies = medicine.therapies as? Set<Therapy>,
           let person = therapies.compactMap({ ($0.value(forKey: "person") as? Person).flatMap(displayName(for:)) }).first(where: { !$0.isEmpty }) {
            return person
        }
        return nil
    }

    // MARK: - Terapia bloccata (ricetta/scorte)
    private struct BlockedTherapyInfo {
        let medicine: Medicine
        let needsPrescription: Bool
        let isOutOfStock: Bool
        let doctor: DoctorContact?
        let timeLabel: String?
        let personName: String?
    }

    private func blockedTherapyInfo(for item: TodayTodoItem) -> BlockedTherapyInfo? {
        guard item.category == .therapy, let medicine = medicine(for: item) else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let needsRx = needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec)
        let outOfStock = isOutOfStock(medicine, recurrenceManager: rec)
        guard needsRx || outOfStock else { return nil }
        let contact = prescriptionDoctorContact(for: medicine)
        let timeLabel = timeLabel(for: item)
        let personName = personNameForTherapy(medicine)
        return BlockedTherapyInfo(
            medicine: medicine,
            needsPrescription: needsRx,
            isOutOfStock: outOfStock,
            doctor: contact,
            timeLabel: timeLabel,
            personName: personName
        )
    }

    @ViewBuilder
    private func blockedTherapyCard(for item: TodayTodoItem, info: BlockedTherapyInfo) -> some View {
        let medName = formattedMedicineName(info.medicine.nome ?? item.title)
        let awaitingRx = isAwaitingPrescription(info.medicine) || isBlockedSubtaskDone(type: "prescription", medicine: info.medicine)
        let doctorName = info.doctor?.name ?? "medico"
        VStack(spacing: 10) {
            blockedStepRow(
                title: "Assumi \(medName)",
                status: nil,
                subtitle: info.personName,
                subtitleColor: .secondary,
                subtitleAsBadge: false,
                iconName: "pills",
                trailingBadge: info.isOutOfStock ? ("Da rifornire", .orange) : nil,
                showCircle: true,
                isDone: isBlockedSubtaskDone(type: "intake", medicine: info.medicine),
                onCheck: { completeBlockedIntake(for: info) }
            )

            if info.needsPrescription || info.isOutOfStock {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .padding(.leading, 34)
                        .padding(.vertical, 10)

                    VStack(spacing: 10) {
                        if info.needsPrescription && !awaitingRx {
                            blockedStepRow(
                                title: awaitingRx ? "In attesa della ricetta da \(doctorName)" : "Chiedi ricetta al medico \(doctorName)",
                                status: nil,
                                iconName: "heart.text.square",
                                buttons: [
                                    .init(label: "Invia richiesta", action: { sendPrescriptionRequest(for: info.medicine) })
                                ],
                                showCircle: !awaitingRx,
                                isDone: isBlockedSubtaskDone(type: "prescription", medicine: info.medicine),
                                onCheck: awaitingRx ? nil : { completeBlockedPrescription(for: info) }
                            )
                            .padding(.leading, 60)
                        }

                        blockedStepRow(
                            title: "Compra \(medName)",
                            status: nil,
                            subtitle: purchaseSubtitle(for: info.medicine, awaitingRx: awaitingRx, doctorName: doctorName),
                            subtitleColor: .secondary,
                            iconName: "cart",
                            isDone: isBlockedSubtaskDone(type: "purchase", medicine: info.medicine),
                            onCheck: { completeBlockedPurchase(for: info) }
                        )
                        .padding(.leading, 60)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 48, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func purchaseWithPrescriptionRow(for item: TodayTodoItem, medicine: Medicine, isCompleted: Bool) -> some View {
        let medName = formattedMedicineName(medicine.nome ?? item.title)
        let awaitingRx = isAwaitingPrescription(medicine)
        let doctorName = prescriptionDoctor(for: medicine).map(doctorFullName) ?? "medico"

        VStack(spacing: 10) {
            blockedStepRow(
                title: "Compra \(medName)",
                status: nil,
                subtitle: purchaseSubtitle(for: medicine, awaitingRx: awaitingRx, doctorName: doctorName),
                subtitleColor: .secondary,
                subtitleAsBadge: false,
                iconName: "cart",
                showCircle: true,
                isDone: isCompleted,
                onCheck: { toggleCompletion(for: item) }
            )

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, 36)
                    .padding(.vertical, 8)

                VStack(spacing: 10) {
                    if !awaitingRx {
                        blockedStepRow(
                            title: "Chiedi ricetta al medico \(doctorName)",
                            status: nil,
                            iconName: "heart.text.square",
                            buttons: [
                                .init(label: "Invia richiesta", action: { sendPrescriptionRequest(for: medicine) })
                            ],
                            showCircle: true,
                            isDone: isBlockedSubtaskDone(type: "prescription", medicine: medicine),
                            onCheck: { sendPrescriptionRequest(for: medicine) }
                        )
                        .padding(.leading, 64)
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 48, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func blockedStatusText(for info: BlockedTherapyInfo) -> String? {
        if info.needsPrescription && info.isOutOfStock {
            return "Bloccata: serve ricetta e scorte finite"
        } else if info.needsPrescription {
            return "Bloccata: serve ricetta"
        } else if info.isOutOfStock {
            return "Bloccata: scorte finite"
        }
        return nil
    }

    private func blockedSubtaskKey(_ type: String, for medicine: Medicine) -> String {
        "\(type)|\(medicine.objectID.uriRepresentation().absoluteString)"
    }

    private func isBlockedSubtaskDone(type: String, medicine: Medicine) -> Bool {
        completedBlockedSubtasks.contains(blockedSubtaskKey(type, for: medicine))
    }

    private func isAwaitingPrescription(_ medicine: Medicine) -> Bool {
        pendingPrescriptionMedIDs.contains(medicine.objectID) || medicine.hasNewPrescritpionRequest()
    }

    private func sendPrescriptionRequest(for medicine: Medicine) {
        _ = viewModel.requestPrescription(for: medicine)
        pendingPrescriptionMedIDs.insert(medicine.objectID)
        completedBlockedSubtasks.insert(blockedSubtaskKey("prescription", for: medicine))
    }

    private func completeBlockedIntake(for info: BlockedTherapyInfo) {
        let med = info.medicine
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        // Se serve ricetta e non è stata chiesta, invia richiesta
        if needsPrescriptionBeforePurchase(med, recurrenceManager: rec),
           !isAwaitingPrescription(med) {
            sendPrescriptionRequest(for: med)
        }
        // Segna acquisto
        completedBlockedSubtasks.insert(blockedSubtaskKey("purchase", for: med))
        _ = viewModel.markAsPurchased(for: med)
        // Segna intake virtuale
        completedBlockedSubtasks.insert(blockedSubtaskKey("intake", for: med))
    }

    private func completeBlockedPurchase(for info: BlockedTherapyInfo) {
        let key = blockedSubtaskKey("purchase", for: info.medicine)
        guard !completedBlockedSubtasks.contains(key) else { return }
        completedBlockedSubtasks.insert(key)
        _ = viewModel.markAsPurchased(for: info.medicine)
    }

    private func completeBlockedPrescription(for info: BlockedTherapyInfo) {
        let key = blockedSubtaskKey("prescription", for: info.medicine)
        guard !completedBlockedSubtasks.contains(key) else { return }
        completedBlockedSubtasks.insert(key)
        sendPrescriptionRequest(for: info.medicine)
    }

    private struct SubtaskButton {
        let label: String
        let action: () -> Void
    }

    @ViewBuilder
    private func blockedStepRow(title: String, status: String? = nil, subtitle: String? = nil, subtitleColor: Color = .secondary, subtitleAsBadge: Bool = false, iconName: String? = nil, buttons: [SubtaskButton] = [], trailingBadge: (String, Color)? = nil, showCircle: Bool = true, isDone: Bool = false, onCheck: (() -> Void)? = nil) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.primary)
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(nil)
                    if let status {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.1))
                            )
                            .overlay(
                                Capsule().stroke(Color.orange.opacity(0.7), lineWidth: 1)
                            )
                    }
                }
                if let subtitle {
                    HStack(alignment: .top, spacing: 8) {
                        if iconName != nil {
                            Spacer()
                                .frame(width: 24)
                        }
                        if subtitleAsBadge {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(subtitleColor)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(subtitleColor.opacity(0.15))
                                )
                        } else {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(subtitleColor)
                                .lineLimit(nil)
                        }
                        Spacer(minLength: 0)
                    }
                }

                if !buttons.isEmpty {
                    HStack(spacing: 8) {
                        if iconName != nil {
                            Spacer()
                                .frame(width: 24)
                        }
                        ForEach(Array(buttons.enumerated()), id: \.offset) { entry in
                            let button = entry.element
                            let isSend = button.label.lowercased().contains("invia richiesta")
                            Button(action: button.action) {
                                HStack(spacing: 6) {
                                    if isSend {
                                        Image(systemName: "paperplane.fill")
                                    }
                                    Text(button.label)
                                }
                                .font(.callout)
                                .foregroundStyle(isSend ? Color.accentColor : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(isSend ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isSend ? Color.accentColor.opacity(0.35) : Color(.systemGray4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 0)

            if let badge = trailingBadge {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(badge.1)
                    Text(badge.0)
                        .font(.callout)
                        .foregroundStyle(badge.1)
                }
            } else if showCircle {
                let circle = Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.primary)

                if let onCheck {
                    Button(action: onCheck) {
                        circle
                    }
                    .buttonStyle(.plain)
                } else {
                    circle
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func openPrescription(for medicine: Medicine) {
        prescriptionEmailMedicine = medicine
    }

    private func callDoctor(_ doctor: DoctorContact?) {
        guard let phone = doctor?.phoneInternational else { return }
        let number = phone.hasPrefix("+") ? phone : "+\(phone)"
        guard let url = URL(string: "tel://\(number)") else { return }
        openURL(url)
    }

    private func normalizedSecondaryDetail(_ detail: String?) -> String? {
        guard let detail else { return nil }
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "\n", with: " • ")
    }

    private func prescriptionRowContent(
        item: TodayTodoItem,
        titleColor: Color,
        prescriptionMedicine: Medicine?,
        iconName: String,
        isEnabled: Bool,
        onSend: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(titleColor)
                Text(prescriptionMainText(for: item, medicine: prescriptionMedicine))
                    .font(.title3)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
            }
            Button {
                onSend()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                    Text("Invia richiesta")
                }
                .font(.callout)
                .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill((isEnabled ? Color.accentColor.opacity(0.12) : Color(.systemGray6)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isEnabled ? Color.accentColor.opacity(0.35) : Color(.systemGray4), lineWidth: 1)
                )
            }
            .disabled(!isEnabled)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionIcon(for item: TodayTodoItem) -> String {
        switch item.category {
        case .therapy:
            return "pills"
        case .purchase:
            return "cart"
        case .prescription:
            return "heart.text.square"
        case .upcoming, .pharmacy:
            return "checkmark.circle"
        }
    }

    private struct TodayDoseInfo {
        let date: Date
        let personName: String?
        let therapy: Therapy
    }

    private enum PrescriptionTaskState: Equatable {
        case needsRequest
        case waitingResponse
    }

    private func combine(day: Date, withTime time: Date) -> Date? {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)

        var mergedComponents = DateComponents()
        mergedComponents.year = dayComponents.year
        mergedComponents.month = dayComponents.month
        mergedComponents.day = dayComponents.day
        mergedComponents.hour = timeComponents.hour
        mergedComponents.minute = timeComponents.minute
        mergedComponents.second = timeComponents.second

        return calendar.date(from: mergedComponents)
    }

    private func occursToday(_ therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> Bool {
        let calendar = Calendar.current
        let endOfDay: Date = {
            let start = calendar.startOfDay(for: now)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? now

        if start > endOfDay { return false }
        if let until = rule.until, calendar.startOfDay(for: until) < calendar.startOfDay(for: now) { return false }

        let freq = rule.freq.uppercased()
        let interval = rule.interval ?? 1

        func icsCode(for date: Date) -> String {
            let weekday = calendar.component(.weekday, from: date)
            switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" }
        }

        switch freq {
        case "DAILY":
            let startSOD = calendar.startOfDay(for: start)
            let todaySOD = calendar.startOfDay(for: now)
            if let days = calendar.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                return days % max(1, interval) == 0
            }
            return false
        case "WEEKLY":
            let todayCode = icsCode(for: now)
            let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
            guard byDays.contains(todayCode) else { return false }

            let startWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let todayWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            if let weeks = calendar.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                return weeks % max(1, interval) == 0
            }
            return false
        default:
            return false
        }
    }

    private func scheduledTimesToday(for therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> [Date] {
        guard occursToday(therapy, now: now, recurrenceManager: recurrenceManager) else { return [] }
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return [] }
        let today = Calendar.current.startOfDay(for: now)
        return doseSet.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }.sorted()
    }

    private func intakeCountToday(for therapy: Therapy, medicine: Medicine, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = (medicine.logs ?? []).filter { $0.type == "intake" && calendar.isDate($0.timestamp, inSameDayAs: now) }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        let therapyCount = (medicine.therapies as? Set<Therapy>)?.count ?? 0
        if therapyCount == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }

    private func nextUpcomingDoseDate(for therapy: Therapy, medicine: Medicine, now: Date, recurrenceManager: RecurrenceManager) -> Date? {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? now
        let calendar = Calendar.current

        let timesToday = scheduledTimesToday(for: therapy, now: now, recurrenceManager: recurrenceManager)
        if calendar.isDateInToday(now), !timesToday.isEmpty {
            let takenCount = intakeCountToday(for: therapy, medicine: medicine, now: now)
            if takenCount >= timesToday.count {
                let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: now)) ?? now
                return recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: endOfDay, doses: therapy.doses as NSSet?)
            }
            let pending = Array(timesToday.dropFirst(min(takenCount, timesToday.count)))
            if let nextToday = pending.first(where: { $0 > now }) {
                return nextToday
            }
        }

        return recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: therapy.doses as NSSet?)
    }

    private func nextDoseTodayInfo(for medicine: Medicine) -> TodayDoseInfo? {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current

        var best: (date: Date, personName: String?, therapy: Therapy)? = nil
        for therapy in therapies where therapy.manual_intake_registration {
            guard let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: rec) else {
                continue
            }
            guard calendar.isDateInToday(next) else { continue }
            let personName = (therapy.value(forKey: "person") as? Person).flatMap { displayName(for: $0) }
            if best == nil || next < best!.date {
                best = (next, personName, therapy)
            }
        }
        guard let best else { return nil }
        return TodayDoseInfo(date: best.date, personName: best.personName, therapy: best.therapy)
    }

    private func prescriptionTaskState(for medicine: Medicine?, item: TodayTodoItem) -> PrescriptionTaskState? {
        guard item.category == .prescription, let medicine else { return nil }
        return medicine.hasNewPrescritpionRequest() ? .waitingResponse : .needsRequest
    }

    private func displayName(for person: Person) -> String? {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        let joined = parts.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private func therapyVerb(for medicine: Medicine) -> String {
        let now = Date()
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else { return "continuare" }
        let earliestStart = therapies.compactMap(\.start_date).min() ?? now
        return earliestStart > now ? "iniziare" : "continuare"
    }

    private func nextDoseLabelInNextWeek(for medicineID: NSManagedObjectID) -> String? {
        guard let medicine = medicines.first(where: { $0.objectID == medicineID }) else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        guard let next = earliestDoseInNextWeek(for: medicine, recurrenceManager: rec) else { return nil }
        return formattedDoseDateTime(next)
    }

    private func earliestDoseInNextWeek(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Date? {
        guard let therapies = medicine.therapies as? Set<Therapy>, !therapies.isEmpty else { return nil }
        let now = Date()
        let limit = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        var best: Date? = nil
        for therapy in therapies {
            if let next = nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager) {
                guard next <= limit else { continue }
                if best == nil || next < best! { best = next }
            }
        }
        return best
    }

    private func formattedDoseDateTime(_ date: Date) -> String {
        let calendar = Calendar.current

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "it_IT")
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let time = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) { return "oggi alle \(time)" }
        if calendar.isDateInTomorrow(date) { return "domani alle \(time)" }
        if let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: Date()),
           calendar.isDate(date, inSameDayAs: dayAfterTomorrow) {
            return "dopodomani alle \(time)" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let dateText = formatter.string(from: date)
        return "\(dateText) alle \(time)"
    }

    private func formattedMedicineName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.lowercased().localizedCapitalized
    }

    private func actionText(for item: TodayTodoItem, isCompleted: Bool) -> String {
        let med = medicine(for: item)
        switch item.category {
        case .therapy:
            return isCompleted ? "Assunto" : "Assumi"
        case .purchase:
            if let med {
                let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
                let awaiting = isAwaitingPrescription(med)
                if !awaiting && needsPrescriptionBeforePurchase(med, recurrenceManager: rec) {
                    let doctor = prescriptionDoctor(for: med)
                    let docName = doctor.map(doctorFullName) ?? "medico"
                    return "Chiedi ricetta al medico \(docName)"
                }
            }
            return isCompleted ? "Comprato" : "Compra"
        case .prescription:
            if med?.hasNewPrescritpionRequest() == true {
                return "In attesa della ricetta"
            }
            if isCompleted {
                return "Richiesta inviata"
            }
            if let doctor = med?.prescribingDoctor {
                let docName = doctorFullName(doctor)
                return "Chiedi ricetta al medico \(docName)"
            }
            return "Chiedi ricetta al medico"
        case .upcoming, .pharmacy:
            return isCompleted ? "Fatto" : "Fai"
        }
    }

    private func groupTitle(for category: TodayTodoItem.Category) -> String {
        switch category {
        case .therapy: return "Assumi"
        case .purchase: return "Compra"
        case .prescription: return "Ricette"
        case .upcoming: return "Promemoria"
        case .pharmacy: return "Farmacia"
        }
    }

    private func stockBadge(for medicine: Medicine) -> String? {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
            let totalLeft = therapies.reduce(0.0) { $0 + Double($1.leftover()) }
            let totalDaily = therapies.reduce(0.0) { $0 + $1.stimaConsumoGiornaliero(recurrenceManager: rec) }
            if totalDaily > 0 {
                let days = Int(totalLeft / totalDaily)
                return "Scorte \(max(0, days)) gg"
            }
            return totalLeft <= 0 ? "Scorte 0" : "Scorte ok"
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return remaining <= 0 ? "Scorte 0" : "Scorte \(remaining) u"
        }
        return nil
    }

    private func stockSubtitle(for medicine: Medicine) -> String? {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            let totalLeft = therapies.reduce(0.0) { $0 + Double($1.leftover()) }
            return "Scorte: \(Int(max(0, totalLeft))) u"
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return "Scorte: \(max(0, remaining)) u"
        }
        return nil
    }

    private func purchaseSubtitle(for medicine: Medicine, awaitingRx: Bool, doctorName: String) -> String? {
        var parts: [String] = []
        if awaitingRx {
            parts.append("Richiesta ricetta inviata a \(doctorName)")
        }
        if let stock = stockSubtitle(for: medicine) {
            parts.append(stock)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func dueLabel(for medicine: Medicine) -> String? {
        guard let label = nextDoseLabelInNextWeek(for: medicine.objectID) else { return nil }
        return "Entro \(label)"
    }

    private func metaInfo(for item: TodayTodoItem) -> (icon: String, text: String)? {
        switch item.category {
        case .purchase:
            guard let pharmacy = locationVM.pinItem?.title, !pharmacy.isEmpty else { return nil }
            return ("location.north", pharmacy)
        case .prescription:
            if let medicine = medicine(for: item) {
                let doctorName = prescriptionDoctorName(for: medicine)
                let hasContact = prescriptionDoctorEmail(for: medicine) != nil || prescriptionDoctorPhoneInternational(for: medicine) != nil
                if doctorName == "Dottore" && !hasContact {
                    return nil
                }
                return ("envelope", doctorName)
            }
            return nil
        default:
            return nil
        }
    }

    private func toggleCompletion(for item: TodayTodoItem) {
        if item.category == .purchase,
           let med = medicine(for: item) {
            let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
            if needsPrescriptionBeforePurchase(med, recurrenceManager: rec),
               !isAwaitingPrescription(med) {
                // Richiede prima il sottotask "Chiedi ricetta": non completare il todo principale
                return
            }
        }

        if completedTodoIDs.contains(item.id) {
            withAnimation(.easeInOut(duration: 0.2)) {
                completedTodoIDs.remove(item.id)
            }
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            completedTodoIDs.insert(item.id)
        }
        recordLogCompletion(for: item)
        showCompletionToast(for: item)
    }

    private func showCompletionToast(for item: TodayTodoItem) {
        completionToastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            completionToastItemID = item.id
        }
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                completionToastItemID = nil
            }
            completionUndoLogID = nil
            completionToastWorkItem = nil
        }
        completionToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: workItem)
    }

    private func undoLastCompletion() {
        guard let id = completionToastItemID else { return }
        completionToastWorkItem?.cancel()
        completionToastWorkItem = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            completedTodoIDs.remove(id)
            completionToastItemID = nil
        }
        if let logID = completionUndoLogID,
           let log = try? managedObjectContext.existingObject(with: logID) as? Log {
            managedObjectContext.delete(log)
            try? managedObjectContext.save()
        }
        completionUndoLogID = nil
    }

    private func recordLogCompletion(for item: TodayTodoItem) {
        guard let medicine = medicine(for: item) else {
            completionUndoLogID = nil
            return
        }
        let log: Log?
        switch item.category {
        case .therapy:
            if let info = nextDoseTodayInfo(for: medicine) {
                log = viewModel.markAsTaken(for: info.therapy)
            } else {
                log = viewModel.markAsTaken(for: medicine)
            }
        case .purchase:
            log = viewModel.markAsPurchased(for: medicine)
        case .prescription:
            if prescriptionTaskState(for: medicine, item: item) == .waitingResponse {
                log = viewModel.markPrescriptionReceived(for: medicine)
            } else {
                log = viewModel.requestPrescription(for: medicine)
            }
        case .upcoming, .pharmacy:
            log = nil
        }
        completionUndoLogID = log?.objectID
    }

    private func medicine(for item: TodayTodoItem) -> Medicine? {
        if let id = item.medicineID, let medicine = medicines.first(where: { $0.objectID == id }) {
            return medicine
        }
        let normalizedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return medicines.first(where: { $0.nome.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedTitle })
    }

    private func prescriptionDoctorName(for medicine: Medicine) -> String {
        let doctor = prescriptionDoctor(for: medicine)
        let first = (doctor?.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor?.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        return parts.isEmpty ? "Dottore" : parts.joined(separator: " ")
    }

    private func prescriptionDoctorEmail(for medicine: Medicine) -> String? {
        let candidate = prescriptionDoctor(for: medicine)?.mail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (candidate?.isEmpty == false) ? candidate : nil
    }

    private func prescriptionDoctorPhoneInternational(for medicine: Medicine) -> String? {
        let candidate = prescriptionDoctor(for: medicine)?.telefono?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty else { return nil }
        return CommunicationService.normalizeInternationalPhone(candidate)
    }

    private func prescriptionDoctorContact(for medicine: Medicine) -> DoctorContact {
        DoctorContact(
            name: prescriptionDoctorName(for: medicine),
            email: prescriptionDoctorEmail(for: medicine),
            phoneInternational: prescriptionDoctorPhoneInternational(for: medicine)
        )
    }

    private func prescriptionDoctor(for medicine: Medicine) -> Doctor? {
        if let assigned = medicine.prescribingDoctor {
            return assigned
        }
        if let doctorWithEmail = doctors.first(where: { !($0.mail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return doctorWithEmail
        }
        return doctors.first(where: { !($0.telefono ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func prescriptionEmailBody(for medicines: [Medicine], doctorName: String) -> String {
        let list = medicines
            .map { formattedMedicineName($0.nome) }
            .map { "- \($0)" }
            .joined(separator: "\n")
        return """
        Gentile \(doctorName),

        avrei bisogno della ricetta per:
        \(list)

        Potresti inviarla appena possibile? Grazie!

        """
    }

    private struct PrescriptionEmailSheet: View {
        let doctor: DoctorContact
        let subject: String
        let messageBody: String
        let onCopy: () -> Void
        let onDidSend: () -> Void

        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL

        var body: some View {
            let canSendEmail = (doctor.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            let canSendWhatsApp = (doctor.phoneInternational?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Messaggio da inviare a \(doctor.name)")
                            .font(.headline)
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                onCopy()
                                dismiss()
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.title3)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Copia testo")

                            if canSendEmail {
                                Button {
                                    CommunicationService(openURL: openURL).sendEmail(to: doctor, subject: subject, body: messageBody)
                                    onDidSend()
                                    dismiss()
                                } label: {
                                    Image(systemName: "envelope.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel("Invia email")
                            }

                            if canSendWhatsApp {
                                Button {
                                    CommunicationService(openURL: openURL).sendWhatsApp(to: doctor, text: messageBody)
                                    onDidSend()
                                    dismiss()
                                } label: {
                                    Image(systemName: "message.fill")
                                        .font(.title3)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(red: 0.16, green: 0.78, blue: 0.45))
                                .accessibilityLabel("Invia WhatsApp")
                            }
                        }
                    }

                    ScrollView {
                        Text(messageBody)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Spacer(minLength: 0)
                }
                .padding()
                .navigationTitle("Richiedi ricetta")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private struct PrescriptionRequestConfirmationSheet: View {
        let medicineName: String
        let doctor: DoctorContact
        let subject: String
        let messageBody: String
        let onDidSend: () -> Void

        @Environment(\.dismiss) private var dismiss
        @Environment(\.openURL) private var openURL

        var body: some View {
            let canSendEmail = (doctor.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            let canSendWhatsApp = (doctor.phoneInternational?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

            VStack(alignment: .leading, spacing: 16) {
                Text("Vuoi inviare una richiesta a \(doctor.name) per la ricetta di \(medicineName)?")
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 12) {
                    Button("Annulla") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if canSendEmail {
                        Button {
                            CommunicationService(openURL: openURL).sendEmail(to: doctor, subject: subject, body: messageBody)
                            onDidSend()
                            dismiss()
                        } label: {
                            Image(systemName: "envelope.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Invia email")
                    }

                    if canSendWhatsApp {
                        Button {
                            CommunicationService(openURL: openURL).sendWhatsApp(to: doctor, text: messageBody)
                            onDidSend()
                            dismiss()
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.16, green: 0.78, blue: 0.45))
                        .accessibilityLabel("Invia WhatsApp")
                    }
                }
                Spacer(minLength: 0)
            }
            .padding()
            .presentationDetents([.fraction(0.3), .medium])
        }
    }

    // MARK: - Row builder (gestures + card)
    private func row(for medicine: Medicine) -> some View {
        let isSelected = viewModel.selectedMedicines.contains(medicine)
        let shouldShowRx = shouldShowPrescriptionAction(for: medicine)
        return MedicineSwipeRow(
            medicine: medicine,
            isSelected: isSelected,
            isInSelectionMode: viewModel.isSelecting,
            shouldShowPrescription: shouldShowRx,
            onTap: {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: medicine)
                } else {
                    selectedMedicine = medicine
                }
            },
            onLongPress: {
                selectedMedicine = medicine
                Haptics.impact(.medium)
            },
            onToggleSelection: { viewModel.toggleSelection(for: medicine) },
            onEnterSelection: { viewModel.enterSelectionMode(with: medicine) },
            onMarkTaken: { viewModel.markAsTaken(for: medicine) },
            onMarkPurchased: { viewModel.markAsPurchased(for: medicine) },
            onRequestPrescription: shouldShowRx ? { viewModel.requestPrescription(for: medicine) } : nil,
            onMove: { medicineToMove = medicine }
        )
        .accessibilityIdentifier("MedicineRow_\(medicine.objectID)")
    }

    private func shouldShowPrescriptionAction(for medicine: Medicine) -> Bool {
        guard medicine.obbligo_ricetta else { return false }
        if medicine.hasNewPrescritpionRequest() { return false }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        return needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec)
    }
    
    // MARK: - New sorting algorithm (sections)
    private func computeSections() -> (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]) {
        PharmaApp.computeSections(for: Array(medicines), logs: Array(logs), option: options.first)
    }
    
    private struct ShelfEntry: Identifiable {
        enum Kind {
            case cabinet(Cabinet)
            case medicine(Medicine)
        }
        let id: NSManagedObjectID
        let priority: Int
        let name: String
        let kind: Kind
    }
    
    private func shelfEntries(from sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> [ShelfEntry] {
        let orderedMeds = sections.purchase + sections.oggi + sections.ok
        var indexMap: [NSManagedObjectID: Int] = [:]
        for (idx, med) in orderedMeds.enumerated() {
            indexMap[med.objectID] = idx
        }
        
        var entries: [ShelfEntry] = []
        for med in orderedMeds where med.cabinet == nil {
            let priority = indexMap[med.objectID] ?? Int.max
            entries.append(ShelfEntry(id: med.objectID, priority: priority, name: med.nome, kind: .medicine(med)))
        }
        
        let baseIndex = orderedMeds.count
        for (cabIdx, cabinet) in cabinets.enumerated() {
            let meds = cabinet.medicines
            let idxs = meds.compactMap { indexMap[$0.objectID] }
            let priority = idxs.min() ?? (baseIndex + cabIdx)
            entries.append(ShelfEntry(id: cabinet.objectID, priority: priority, name: cabinet.name, kind: .cabinet(cabinet)))
        }
        return entries.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.priority < rhs.priority
        }
    }

    private func buildInsightsContext(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> AIInsightsContext? {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let purchaseCandidates = sections.purchase.filter { !needsPrescriptionBeforePurchase($0, recurrenceManager: rec) }
        let purchaseLines = purchaseCandidates.prefix(5).map { medicine in
            "\(medicine.nome): \(purchaseHighlight(for: medicine, recurrenceManager: rec))"
        }
        // Mostra le terapie anche se il farmaco è bloccato (scorte/ricetta) per evidenziare l'orario
        let therapySources = sections.oggi + sections.purchase
        let therapyLines = therapySources.compactMap { medicine in
            nextDoseTodayHighlight(for: medicine, recurrenceManager: rec)
        }
        let upcomingLines = sections.ok.prefix(3).compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceManager: rec)
        }
        var prescriptionLines: [String] = []
        for medicine in medicines {
            guard needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec) else { continue }
            prescriptionLines.append(medicine.nome)
            if prescriptionLines.count >= 6 { break }
        }
        let context = AIInsightsContext(
            purchaseHighlights: purchaseLines,
            therapyHighlights: therapyLines,
            upcomingHighlights: upcomingLines,
            prescriptionHighlights: prescriptionLines,
            pharmacySuggestion: purchaseLines.isEmpty ? nil : pharmacyHighlightLine
        )
        return context.hasSignals ? context : nil
    }

    private func purchaseHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 {
                if let nextToday = earliestDoseToday(for: medicine) {
                    let fmt = DateFormatter(); fmt.timeStyle = .short
                    return "scorte terminate · da prendere alle \(fmt.string(from: nextToday))"
                }
                return "scorte terminate"
            }
            guard totalDaily > 0 else {
                return "copertura non stimabile"
            }
            let days = Int(totalLeft / totalDaily)
            if days <= 0 { return "scorte terminate" }
            return days == 1 ? "copertura per 1 giorno" : "copertura per \(days) giorni"
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 { return "nessuna unità residua" }
            if remaining < 5 { return "solo \(remaining) unità" }
            return "\(remaining) unità disponibili"
        }
        return "scorte non monitorate"
    }

    private func nextDoseHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let upcomingDates = therapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager)
        }
        guard let next = upcomingDates.sorted().first else { return nil }
        if calendar.isDateInToday(next) {
            return "\(medicine.nome): \(FeedView.insightsTimeFormatter.string(from: next))"
        } else if calendar.isDateInTomorrow(next) {
            return "\(medicine.nome): domani"
        } else {
            return "\(medicine.nome): \(FeedView.insightsDateFormatter.string(from: next))"
        }
    }

    private func nextDoseTodayHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let manualTherapies = therapies.filter(\.manual_intake_registration)
        guard !manualTherapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let upcomingDates = manualTherapies.compactMap { therapy in
            nextUpcomingDoseDate(for: therapy, medicine: medicine, now: now, recurrenceManager: recurrenceManager)
        }
        guard let next = upcomingDates.sorted().first, calendar.isDateInToday(next) else { return nil }
        return "\(medicine.nome): \(FeedView.insightsTimeFormatter.string(from: next))"
    }

    private static let insightsTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    private static let insightsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    @ViewBuilder
    private func mapItemWrappedView<Content: View>(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .mapItemDetailSheet(item: $selectedMapItem, displaysMap: true)
        } else if #available(iOS 17.0, *) {
            content
                .sheet(isPresented: Binding(
                    get: { selectedMapItem != nil },
                    set: { newValue in
                        if !newValue { selectedMapItem = nil }
                    }
                )) {
                    if let item = selectedMapItem {
                        MapItemDetailInlineView(mapItem: item)
                    }
                }
        } else {
            content
        }
    }

    // Verifica se una medicina ha almeno una terapia che ricorre oggi
    private func hasTherapyToday(_ m: Medicine) -> Bool {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let cal = Calendar.current
        let endOfDay: Date = {
            let start = cal.startOfDay(for: now)
            return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()
        guard let therapies = m.therapies, !therapies.isEmpty else { return false }
        for t in therapies {
            let rule = rec.parseRecurrenceString(t.rrule ?? "")
            let start = t.start_date ?? now
            if start > endOfDay { continue }
            if let until = rule.until, cal.startOfDay(for: until) < cal.startOfDay(for: now) { continue }
            let interval = rule.interval ?? 1
            switch rule.freq.uppercased() {
            case "DAILY":
                let startSOD = cal.startOfDay(for: start)
                let todaySOD = cal.startOfDay(for: now)
                if let days = cal.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                    if days % max(1, interval) == 0 { return true }
                }
            case "WEEKLY":
                let weekday = cal.component(.weekday, from: now)
                let code: String = { switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" } }()
                let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
                if byDays.contains(code) {
                    let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
                    let todayWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
                    if let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                        if weeks % max(1, interval) == 0 { return true }
                    }
                }
            default:
                break
            }
        }
        return false
    }
    
    func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if let package = medicine.packages.first {
            return package
        }
        return nil
    }

    private func saveContext() {
        do {
            try managedObjectContext.save()
        } catch {
            print("Errore salvataggio: \(error)")
        }
    }
    
    // MARK: - Doctor & pharmacy highlights
    private var doctorHighlightLine: String? {
        guard let info = todayDoctorInfo else { return nil }
        return "\(info.name) — \(info.schedule)"
    }

    private func doctorFullName(_ doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [first, last].filter { !$0.isEmpty }
        return parts.isEmpty ? "Medico" : parts.joined(separator: " ")
    }

    private var pharmacyHighlightLine: String? {
        guard let pin = locationVM.pinItem else { return nil }
        var details: [String] = []
        if let distance = locationVM.distanceString, !distance.isEmpty {
            details.append(distance)
        }
        if let opening = locationVM.todayOpeningText, !opening.isEmpty {
            details.append("Oggi: \(opening)")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: " · ")))"
        return "\(pin.title)\(suffix)"
    }

    private enum OpeningHoursParser {
        private static let separators: [Character] = ["-", "–", "—"]
        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "it_IT")
            formatter.dateFormat = "HH:mm"
            return formatter
        }()

        static func intervals(from text: String) -> [(start: Date, end: Date)] {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            return text
                .split(separator: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { segment -> (Date, Date)? in
                    guard let sep = separators.first(where: { segment.contains($0) }) else { return nil }
                    let parts = segment
                        .split(separator: sep, maxSplits: 1)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard parts.count == 2,
                          let startTime = timeFormatter.date(from: parts[0]),
                          let endTime = timeFormatter.date(from: parts[1]) else { return nil }
                    guard
                        let start = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                                  minute: calendar.component(.minute, from: startTime),
                                                  second: 0,
                                                  of: today),
                        let end = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                                minute: calendar.component(.minute, from: endTime),
                                                second: 0,
                                                of: today)
                    else { return nil }
                    return (start, end)
                }
        }

        static func activeInterval(from text: String, now: Date = Date()) -> (start: Date, end: Date)? {
            intervals(from: text).first(where: { now >= $0.start && now <= $0.end })
        }

        static func nextInterval(from text: String, after now: Date = Date()) -> (start: Date, end: Date)? {
            intervals(from: text)
                .filter { now < $0.start }
                .sorted { $0.start < $1.start }
                .first
        }

        static func timeString(from date: Date) -> String {
            timeFormatter.string(from: date)
        }

        static func closingTimeString(from interval: (start: Date, end: Date)) -> String {
            timeFormatter.string(from: interval.end)
        }
    }

    private var todayDoctorInfo: (name: String, schedule: String)? {
        guard !doctors.isEmpty else { return nil }
        let candidates: [(Doctor, DoctorScheduleDTO.DaySchedule)] = doctors.compactMap { doctor in
            let dto = doctor.scheduleDTO
            guard let daySchedule = scheduleForToday(in: dto) else { return nil }
            return (doctor, daySchedule)
        }
        guard !candidates.isEmpty else { return nil }
        let selected = candidates.first(where: { $0.1.mode != .closed }) ?? candidates.first!
        let doctor = selected.0
        let schedule = selected.1
        let nameComponents = [doctor.nome, doctor.cognome].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let displayName = nameComponents.isEmpty ? "Medico" : nameComponents.joined(separator: " ")
        return (displayName, describe(day: schedule))
    }

    private func scheduleForToday(in dto: DoctorScheduleDTO) -> DoctorScheduleDTO.DaySchedule? {
        let calendar = Calendar.current
        let weekdayNumber = calendar.component(.weekday, from: Date())
        let target: DoctorScheduleDTO.DaySchedule.Weekday
        switch weekdayNumber {
        case 1: target = .sunday
        case 2: target = .monday
        case 3: target = .tuesday
        case 4: target = .wednesday
        case 5: target = .thursday
        case 6: target = .friday
        case 7: target = .saturday
        default: target = .monday
        }
        return dto.days.first(where: { $0.day == target })
    }

    private func describe(day: DoctorScheduleDTO.DaySchedule) -> String {
        func format(_ slot: DoctorScheduleDTO.TimeSlot) -> String {
            let start = slot.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = slot.end.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty, !end.isEmpty else { return "" }
            return "\(start) - \(end)"
        }

        switch day.mode {
        case .closed:
            return "Oggi: chiuso"
        case .continuous:
            let text = format(day.primary)
            return text.isEmpty ? "Oggi: orario non disponibile" : "Oggi: \(text)"
        case .split:
            let parts = [format(day.primary), format(day.secondary)].filter { !$0.isEmpty }
            return parts.isEmpty ? "Oggi: orario non disponibile" : "Oggi: " + parts.joined(separator: " / ")
        }
    }

    // MARK: - Low stock detection (per mostrare la card)
    private func hasLowStock() -> Bool {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        for m in medicines {
            let threshold = m.stockThreshold(option: options.first)
            if let therapies = m.therapies, !therapies.isEmpty {
                var totalLeft: Double = 0
                var totalDaily: Double = 0
                for therapy in therapies {
                    totalLeft += Double(therapy.leftover())
                    totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
                }
                if totalLeft <= 0 { return true }
                if totalDaily > 0 {
                    let coverage = totalLeft / totalDaily
                    if coverage < Double(threshold) {
                        return true
                    }
                }
            } else {
                if let remaining = m.remainingUnitsWithoutTherapy() {
                    if remaining <= 0 || remaining < threshold { return true }
                }
            }
        }
        return false
    }
    
    final class LocationSearchViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
        @Published var region: MKCoordinateRegion?
        struct Pin: Identifiable {
            let id = UUID()
            let title: String
            let coordinate: CLLocationCoordinate2D
            let phone: String?
            let mapItem: MKMapItem?
        }
        @Published var pinItem: Pin?
        @Published var distanceString: String?
        @Published var distanceMeters: CLLocationDistance?
        @Published var todayOpeningText: String?
        @Published var closingTimeText: String?
        @Published var isLikelyOpen: Bool?
        
        private let manager = CLLocationManager()
        private let maxSearchSpanDelta: CLLocationDegrees = 5.0
        private var userLocation: CLLocation?
        
        override init() {
            super.init()
            manager.delegate = self
        }
        
        func ensureStarted() {
            if CLLocationManager.authorizationStatus() == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
        
        func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            default:
                break
            }
        }
        
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let loc = locations.last else { return }
            userLocation = loc
            manager.stopUpdatingLocation()
            searchNearestPharmacy(around: loc)
        }
        
        private func searchNearestPharmacy(
            around location: CLLocation,
            spanDelta: CLLocationDegrees = 0.05,
            fallback: MKMapItem? = nil,
            query: String = "pharmacy open now"
        ) {
            let isOpenQuery = query.lowercased().contains("open now")
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
            )
            
            let search = MKLocalSearch(request: request)
            search.start { [weak self] response, error in
                guard let self else { return }
                let rawItems = response?.mapItems ?? []
                let items = self.filtered(items: rawItems)
                guard !items.isEmpty else {
                    let nextSpan = spanDelta * 1.8
                    if nextSpan <= self.maxSearchSpanDelta {
                        self.searchNearestPharmacy(around: location, spanDelta: nextSpan, fallback: fallback, query: query)
                    } else if let fallback {
                        self.applySelection(for: fallback, userLocation: location, assumedOpen: isOpenQuery)
                    }
                    return
                }

                let sorted = self.sorted(items, from: location)
                let updatedFallback = fallback ?? sorted.first
                if let (best, isOpen) = self.bestCandidate(from: sorted, isOpenQuery: isOpenQuery) {
                    self.applySelection(for: best, userLocation: location, assumedOpen: isOpen)
                    return
                }

                let nextSpan = spanDelta * 1.8
                if nextSpan <= self.maxSearchSpanDelta {
                    self.searchNearestPharmacy(around: location, spanDelta: nextSpan, fallback: updatedFallback, query: query)
                    return
                }

                if let bestFallback = updatedFallback {
                    self.applySelection(for: bestFallback, userLocation: location, assumedOpen: isOpenQuery)
                }
            }
        }

        private func filtered(items: [MKMapItem]) -> [MKMapItem] {
            let cleaned = items.filter { item in
                if let category = item.pointOfInterestCategory {
                    if category != .pharmacy { return false }
                }
                let name = (item.name ?? "")
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased()
                return !name.contains("erboristeria")
                && !name.contains("parafarmacia")
                && !name.contains("vitamine")
                && !name.contains("vitamin")
            }
            return cleaned
        }

        private func sorted(_ items: [MKMapItem], from location: CLLocation) -> [MKMapItem] {
            items.sorted { lhs, rhs in
                let lDistance = lhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                let rDistance = rhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                return lDistance < rDistance
            }
        }

        private func bestCandidate(from items: [MKMapItem], isOpenQuery: Bool) -> (MKMapItem, Bool)? {
            let now = Date()
            // Prioritize items that our local schedule marks as open; otherwise fall back to nearest result.
            for item in items {
                guard let pharmacy = matchPharmacy(named: item.name ?? "") else { continue }
                if let interval = openingInterval(for: pharmacy),
                   now >= interval.start && now <= interval.end {
                    return (item, true)
                }
            }
            guard let first = items.first else { return nil }
            return (first, isOpenQuery)
        }

        private func applySelection(for chosen: MKMapItem, userLocation location: CLLocation, assumedOpen: Bool) {
            let coord = chosen.placemark.coordinate
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            DispatchQueue.main.async {
                self.region = MKCoordinateRegion(center: coord, span: span)
                let phone = chosen.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.pinItem = Pin(
                    title: chosen.name ?? "Farmacia",
                    coordinate: coord,
                    phone: (phone?.isEmpty == true) ? nil : phone,
                    mapItem: chosen
                )
                if let dist = chosen.placemark.location?.distance(from: location) {
                    self.distanceMeters = dist
                    self.distanceString = Self.format(distance: dist)
                }
                self.isLikelyOpen = assumedOpen
                if let pharmacy = self.matchPharmacy(named: chosen.name ?? "") {
                    self.applyOpeningInfo(for: pharmacy)
                } else {
                    self.todayOpeningText = nil
                    self.closingTimeText = nil
                    self.isLikelyOpen = assumedOpen
                }
            }
        }

        private func applyOpeningInfo(for pharmacy: PharmacyJSON) {
            let slot = self.rawTodaySlot(for: pharmacy)
            self.todayOpeningText = slot

            guard let slot, let interval = openingIntervalForString(slot) else {
                self.closingTimeText = nil
                self.isLikelyOpen = self.isLikelyOpen
                return
            }

            let now = Date()
            if now >= interval.start && now <= interval.end {
                self.closingTimeText = "Aperta"
                self.isLikelyOpen = true
            } else {
                self.closingTimeText = nil
                self.isLikelyOpen = false
            }
        }
        
        func openInMaps() {
            guard let pin = pinItem else { return }
            if let item = pin.mapItem {
                item.openInMaps()
                return
            }
            let placemark = MKPlacemark(coordinate: pin.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = pin.title
            item.openInMaps()
        }

        func callPharmacy() {
            guard let raw = pinItem?.phone ?? pinItem?.mapItem?.phoneNumber else { return }
            let digits = raw.filter { "0123456789+".contains($0) }
            guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
            UIApplication.shared.open(url)
        }
        
        private static func format(distance: CLLocationDistance) -> String {
            // Stima semplice: 5 km/h a piedi (~83 m/min), 45 km/h in auto (~750 m/min)
            let walkingMinutes = max(1, Int(round(distance / 83.0)))
            let drivingMinutes = max(1, Int(round(distance / 750.0)))
            return "∼\(walkingMinutes) min a piedi · ∼\(drivingMinutes) min in auto"
        }

        // MARK: - Orari farmacia (da JSON locale)
        private struct PharmacyJSON: Decodable {
            let Nome: String
            let Orari: [DayJSON]?
        }
        private struct DayJSON: Decodable {
            let data: String
            let orario_apertura: String
        }

        private lazy var pharmacies: [PharmacyJSON] = {
            guard let url = Bundle.main.url(forResource: "farmacie", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([PharmacyJSON].self, from: data) else {
                return []
            }
            return list
        }()

        private func matchPharmacy(named name: String) -> PharmacyJSON? {
            let normalizedTarget = normalize(name)
            let targetTokens = tokenize(normalizedTarget)
            let scored = pharmacies.map { pharmacy -> (PharmacyJSON, Int) in
                let tokens = tokenize(normalize(pharmacy.Nome))
                return (pharmacy, scoreTokens(targetTokens, tokens))
            }
            let best = scored.max { $0.1 < $1.1 }
            if let best, best.1 > 0 { return best.0 }

            // Fallback: substring containment to catch slight naming differences.
            if let direct = pharmacies.first(where: { candidate in
                let norm = normalize(candidate.Nome)
                return norm.contains(normalizedTarget) || normalizedTarget.contains(norm)
            }) {
                return direct
            }
            return nil
        }

        private func openingInterval(for pharmacy: PharmacyJSON) -> (start: Date, end: Date)? {
            guard let slot = rawTodaySlot(for: pharmacy) else { return nil }
            return openingIntervalForString(slot)
        }

        private func rawTodaySlot(for pharmacy: PharmacyJSON) -> String? {
            let df = DateFormatter(); df.locale = Locale(identifier: "it_IT"); df.dateFormat = "EEEE"
            let weekday = df.string(from: Date()).lowercased()
            let dayOrari = pharmacy.Orari?.first(where: { day in
                normalize(day.data).hasPrefix(weekday)
            }) ?? pharmacy.Orari?.first
            return dayOrari?.orario_apertura
        }

        private func openingIntervalForString(_ text: String) -> (start: Date, end: Date)? {
            OpeningHoursParser.activeInterval(from: text)
        }

        private func normalize(_ s: String) -> String {
            let lowered = s.lowercased()
            let folded = lowered.folding(options: .diacriticInsensitive, locale: .current)
            let cleaned = folded
                .replacingOccurrences(of: "farmacia", with: "")
                .replacingOccurrences(of: "parafarmacia", with: "")
                .replacingOccurrences(of: "srl", with: "")
                .replacingOccurrences(of: "sas", with: "")
                .replacingOccurrences(of: "snc", with: "")
                .replacingOccurrences(of: "&", with: " ")
            let allowed = cleaned.filter { $0.isLetter || $0.isNumber || $0 == " " }
            return allowed.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func tokenize(_ s: String) -> [String] {
            s.split(separator: " ").map { String($0) }.filter { $0.count >= 2 }
        }

        private func scoreTokens(_ target: [String], _ candidate: [String]) -> Int {
            let targetSet = Set(target)
            let candSet = Set(candidate)
            return targetSet.intersection(candSet).count
        }
    }
}

@available(iOS 17.0, *)
private struct MapItemDetailInlineView: View {
    let mapItem: MKMapItem

    var body: some View {
        MapItemDetailViewControllerRepresentable(mapItem: mapItem)
    }

    private struct MapItemDetailViewControllerRepresentable: UIViewControllerRepresentable {
        let mapItem: MKMapItem

        func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
            MKMapItemDetailViewController(mapItem: mapItem)
        }

        func updateUIViewController(_ uiViewController: MKMapItemDetailViewController, context: Context) {
            uiViewController.mapItem = mapItem
        }
    }
}

// MARK: - Move to cabinet sheet
struct MoveToCabinetSheet: View {
    let medicine: Medicine
    let cabinets: [Cabinet]
    let onSelect: (Cabinet) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                if cabinets.isEmpty {
                    Text("Nessun cassetto disponibile.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cabinetsWithIDs) { cabinet in
                        moveRow(for: cabinet)
                    }
                }
            }
            .navigationTitle("Sposta in cassetto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
    
    private var cabinetsWithIDs: [IdentifiedCabinet] {
        cabinets.map { IdentifiedCabinet(id: $0.id, cabinet: $0) }
    }
    
    private func moveRow(for identified: IdentifiedCabinet) -> some View {
        Button {
            onSelect(identified.cabinet)
            dismiss()
        } label: {
            HStack {
                Text(identified.cabinet.name)
                Spacer()
                if medicine.cabinet?.id == identified.id {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
        }
    }
    
    private struct IdentifiedCabinet: Identifiable {
        let id: UUID
        let cabinet: Cabinet
    }
}

private struct DividerWithLabel: View {
    let title: String
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Shared helpers
struct MedicineSwipeRow: View {
    let medicine: Medicine
    let isSelected: Bool
    let isInSelectionMode: Bool
    let shouldShowPrescription: Bool
    
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onToggleSelection: () -> Void
    let onEnterSelection: () -> Void
    let onMarkTaken: () -> Void
    let onMarkPurchased: () -> Void
    let onRequestPrescription: (() -> Void)?
    let onMove: () -> Void
    
    var body: some View {
        MedicineRowView(
            medicine: medicine,
            isSelected: isSelected,
            isInSelectionMode: isInSelectionMode
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture(minimumDuration: 0.5) { onLongPress() }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if isInSelectionMode {
                Button {
                    Haptics.impact(.light)
                    onToggleSelection()
                } label: {
                    Label(isSelected ? "Deseleziona" : "Seleziona", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .tint(.accentColor)
            } else {
                Button {
                    Haptics.impact(.light)
                    onEnterSelection()
                } label: {
                    Label("Seleziona", systemImage: "checkmark.circle")
                }
                .tint(.accentColor)
            }
        }
	        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
	            Button {
	                Haptics.impact(.medium)
	                onMarkTaken()
	            } label: {
	                Label("Assunto", systemImage: "checkmark.circle.fill")
	            }
	            .tint(.green)
	            Button {
	                Haptics.impact(.medium)
	                onMarkPurchased()
	            } label: {
	                Label("Acquistato", systemImage: "cart.fill")
	            }
	            .tint(.blue)
                /* Button {
                    Haptics.impact(.medium)
                    onMove()
                } label: {
                    Label("Sposta in cassetto", systemImage: "folder.badge.plus")
                } */
                .tint(.teal)
	            if shouldShowPrescription {
	                Button {
	                    Haptics.impact(.medium)
	                    onRequestPrescription?()
	                } label: {
	                    Label("Richiedi ricetta", systemImage: "envelope.fill")
	                }
	                .tint(.orange)
	            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

func computeSections(for medicines: [Medicine], logs: [Log], option: Option?) -> (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]) {
    let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    let now = Date()
    let cal = Calendar.current
    let endOfDay: Date = {
        let start = cal.startOfDay(for: now)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
    }()
    
    enum StockStatus {
        case ok
        case low
        case critical
        case unknown
    }
    
    func remainingUnits(for m: Medicine) -> Int? {
        if let therapies = m.therapies, !therapies.isEmpty {
            return therapies.reduce(0) { $0 + Int($1.leftover()) }
        }
        return m.remainingUnitsWithoutTherapy()
    }
    
    func nextOccurrence(for m: Medicine) -> Date? {
        guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
        var best: Date? = nil
        for t in therapies {
            let rule = rec.parseRecurrenceString(t.rrule ?? "")
            let startDate = t.start_date ?? now
            if let d = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: t.doses as NSSet?) {
                if best == nil || d < best! { best = d }
            }
        }
        return best
    }
    
    func icsCode(for date: Date) -> String {
        let weekday = cal.component(.weekday, from: date)
        switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" }
    }
    
    func occursToday(_ t: Therapy) -> Bool {
        let rule = rec.parseRecurrenceString(t.rrule ?? "")
        let start = t.start_date ?? now
        if start > endOfDay { return false }
        if let until = rule.until, cal.startOfDay(for: until) < cal.startOfDay(for: now) { return false }
        
        let freq = rule.freq.uppercased()
        let interval = rule.interval ?? 1
        
        switch freq {
        case "DAILY":
            let startSOD = cal.startOfDay(for: start)
            let todaySOD = cal.startOfDay(for: now)
            if let days = cal.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                return days % max(1, interval) == 0
            }
            return false
            
        case "WEEKLY":
            let todayCode = icsCode(for: now)
            let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
            guard byDays.contains(todayCode) else { return false }
            
            let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
            let todayWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
            if let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                return weeks % max(1, interval) == 0
            }
            return false
            
        default:
            return false
        }
    }
    
    func stockStatus(for m: Medicine) -> StockStatus {
        let threshold = m.stockThreshold(option: option)
        if let therapies = m.therapies, !therapies.isEmpty {
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
            }
            if totalDailyUsage <= 0 {
                return totalLeftover > 0 ? .ok : .unknown
            }
            let coverage = totalLeftover / totalDailyUsage
            if coverage <= 0 { return .critical }
            return coverage < Double(threshold) ? .low : .ok
        }
        if let remaining = m.remainingUnitsWithoutTherapy() {
            if remaining <= 0 { return .critical }
            return remaining < threshold ? .low : .ok
        }
        return .unknown
    }
    
    var purchase: [Medicine] = []
    var oggi: [Medicine] = []
    var ok: [Medicine] = []
    
    for m in medicines {
        let status = stockStatus(for: m)
        if status == .critical || status == .low {
            purchase.append(m)
            continue
        }
        if let therapies = m.therapies, !therapies.isEmpty, therapies.contains(where: { occursToday($0) }) {
            oggi.append(m)
        } else {
            ok.append(m)
        }
    }
    
    oggi.sort { (m1, m2) in
        let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
        let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
        if d1 == d2 {
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }
    
    purchase.sort { (m1, m2) in
        let s1 = stockStatus(for: m1)
        let s2 = stockStatus(for: m2)
        if s1 != s2 { return (s1 == .critical) && (s2 != .critical) }
        let r1 = remainingUnits(for: m1) ?? Int.max
        let r2 = remainingUnits(for: m2) ?? Int.max
        if r1 == r2 {
            return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
        }
        return r1 < r2
    }
    
    ok.sort { (m1, m2) in
        let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
        let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
        if d1 == d2 {
            let r1 = remainingUnits(for: m1) ?? Int.max
            let r2 = remainingUnits(for: m2) ?? Int.max
            if r1 == r2 {
                return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
            }
            return r1 < r2
        }
        return d1 < d2
    }
    
    return (purchase, oggi, ok)
}

func isOutOfStock(_ medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
    if let therapies = medicine.therapies, !therapies.isEmpty {
        var totalLeft: Double = 0
        for therapy in therapies {
            totalLeft += Double(therapy.leftover())
        }
        return totalLeft <= 0
    }
    if let remaining = medicine.remainingUnitsWithoutTherapy() {
        return remaining <= 0
    }
    return false
}

func needsPrescriptionBeforePurchase(_ medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
    guard medicine.obbligo_ricetta else { return false }
    if medicine.hasPendingNewPrescription() { return false }
    return isOutOfStock(medicine, recurrenceManager: recurrenceManager)
}
