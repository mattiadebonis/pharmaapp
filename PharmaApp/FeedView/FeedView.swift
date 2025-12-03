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

struct FeedView: View {
    @EnvironmentObject private var appVM: AppViewModel
    enum Mode {
        case insights
        case medicines
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

    init(viewModel: FeedViewModel, mode: Mode = .medicines) {
        self.viewModel = viewModel
        self.mode = mode
    }
    
    var body: some View {
        let sections = computeSections()
        let insightsContext = buildInsightsContext(for: sections)
        Group {
            switch mode {
            case .insights:
                insightsScreen(sections: sections, insightsContext: insightsContext)
            case .medicines:
                medicinesScreen(sections: sections)
            }
        }
        .onAppear {
            locationVM.ensureStarted()
        }
    }

    private func orderedRows(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> [(medicine: Medicine, section: MedicineRowView.RowSection)] {
        sections.purchase.map { ($0, .purchase) } +
        sections.oggi.map { ($0, .tuttoOk) } +
        sections.ok.map { ($0, .tuttoOk) }
    }

    @ViewBuilder
    private func insightsScreen(sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]), insightsContext: AIInsightsContext?) -> some View {
        let rows = orderedRows(for: sections)
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if let insightsContext {
                    AIInsightsPanel(context: insightsContext)
                } else {
                    insightsPlaceholder
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
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
        cabinet.medicines.sorted { (lhs, rhs) in
            let left = (lhs.nome ?? "").lowercased()
            let right = (rhs.nome ?? "").lowercased()
            return left < right
        }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Nessun consiglio per oggi")
                .font(.headline)
            Text("Quando ci saranno scadenze o acquisti da fare vedrai qui le azioni suggerite.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        let therapyLines = sections.oggi.compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceManager: rec)
        }
        let upcomingLines = sections.ok.prefix(3).compactMap { medicine in
            nextDoseHighlight(for: medicine, recurrenceManager: rec)
        }
        var prescriptionLines: [String] = []
        for medicine in medicines {
            let hasPendingPrescription = medicine.hasPendingNewPrescription()
            if hasPendingPrescription {
                continue
            }
            if medicine.hasNewPrescritpionRequest() {
                prescriptionLines.append("\(medicine.nome): in attesa della risposta del medico")
            } else if needsPrescriptionBeforePurchase(medicine, recurrenceManager: rec) {
                prescriptionLines.append("\(medicine.nome): chiedi subito la ricetta")
            }
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
        let upcomingDates = therapies.compactMap { therapy -> Date? in
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let start = therapy.start_date ?? now
            return recurrenceManager.nextOccurrence(rule: rule, startDate: start, after: now, doses: therapy.doses as NSSet?)
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

    private var pharmacyHighlightLine: String? {
        guard let pin = locationVM.pinItem else { return nil }
        var details: [String] = []
        if let distance = locationVM.distanceString, !distance.isEmpty {
            details.append(distance)
        }
        if let opening = locationVM.todayOpeningText, !opening.isEmpty {
            details.append("\(opening)")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: " · ")))"
        return "\(pin.title)\(suffix)"
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
        struct Pin: Identifiable { let id = UUID(); let title: String; let coordinate: CLLocationCoordinate2D }
        @Published var pinItem: Pin?
        @Published var distanceString: String?
        @Published var todayOpeningText: String?
        
        private let manager = CLLocationManager()
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
        
        private func searchNearestPharmacy(around location: CLLocation) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "pharmacy"
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: location.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
            
            let search = MKLocalSearch(request: request)
            search.start { [weak self] response, error in
                guard let self = self, let item = response?.mapItems.min(by: { (a, b) in
                    let da = a.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                    let db = b.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
                    return da < db
                }) else { return }
                
                let coord = item.placemark.coordinate
                let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                DispatchQueue.main.async {
                    self.region = MKCoordinateRegion(center: coord, span: span)
                    self.pinItem = Pin(title: item.name ?? "Farmacia", coordinate: coord)
                    if let dist = item.placemark.location?.distance(from: location) {
                        self.distanceString = Self.format(distance: dist)
                    }
                    self.resolveTodayHours(for: item.name ?? "")
                }
            }
        }
        
        func openInMaps() {
            guard let pin = pinItem else { return }
            let placemark = MKPlacemark(coordinate: pin.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = pin.title
            item.openInMaps()
        }
        
        private static func format(distance: CLLocationDistance) -> String {
            if distance < 1000 { return "\(Int(distance)) m" }
            return String(format: "%.1f km", distance / 1000)
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
        
        private func resolveTodayHours(for name: String) {
            guard let url = Bundle.main.url(forResource: "farmacie", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([PharmacyJSON].self, from: data) else {
                todayOpeningText = nil
                return
            }
            let normalizedTarget = normalize(name)
            // Match farmacia per nome (contains bidirezionale, case/diacritics insensitive)
            guard let match = list.first(where: { p in
                let n = normalize(p.Nome)
                return n.contains(normalizedTarget) || normalizedTarget.contains(n)
            }) else {
                todayOpeningText = nil
                return
            }
            // Trova l'orario del giorno corrente basandosi sul nome del giorno in italiano
            let df = DateFormatter(); df.locale = Locale(identifier: "it_IT"); df.dateFormat = "EEEE"
            let weekday = df.string(from: Date()).lowercased()
            let dayOrari = match.Orari?.first(where: { day in
                normalize(day.data).hasPrefix(weekday)
            })
            todayOpeningText = dayOrari?.orario_apertura
        }
        
        private func normalize(_ s: String) -> String {
            let lowered = s.lowercased()
            let folded = lowered.folding(options: .diacriticInsensitive, locale: .current)
            let allowed = folded.filter { $0.isLetter || $0.isNumber || $0 == " " }
            return allowed.replacingOccurrences(of: "  ", with: " ")
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
            if shouldShowPrescription {
                Button {
                    Haptics.impact(.medium)
                    onRequestPrescription?()
                } label: {
                    Label("Richiedi ricetta", systemImage: "envelope.fill")
                }
                .tint(.orange)
            }
            Button {
                Haptics.impact(.medium)
                onMove()
            } label: {
                Label("Sposta", systemImage: "folder.fill")
            }
            .tint(.purple)
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
    if medicine.hasNewPrescritpionRequest() { return false }
    return isOutOfStock(medicine, recurrenceManager: recurrenceManager)
}
