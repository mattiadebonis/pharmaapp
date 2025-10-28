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
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    
    @ObservedObject var viewModel: FeedViewModel
    @State private var selectedMedicine: Medicine?
    @StateObject private var locationVM = LocationSearchViewModel()
    
    var body: some View {
        let sections = computeSections()
        
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Sezione "Da acquistare": più discreta nel copy e nello stile
                    Text("Da acquistare (\(sections.purchase.count))")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                    if sections.purchase.isEmpty {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tutto a posto: nessun acquisto necessario")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                Text("Le scorte dei tuoi medicinali sono al sicuro.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(sections.purchase) { medicine in
                                let showToday = hasTherapyToday(medicine)
                                row(for: medicine, showCoverageInfo: true, infoMode: showToday ? .nextDose : .frequency, showPurchaseShortcut: true, section: .purchase)
                            }
                        }
                    }
                }

                if !(sections.oggi.isEmpty && sections.ok.isEmpty) {
                    let totalOk = sections.oggi.count + sections.ok.count
                    HStack {

                        Text("In ordine (\(totalOk))")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                    VStack(spacing: 0) {
                        // Prima quelli con terapia oggi (mostrano orario)
                        ForEach(sections.oggi) { medicine in
                            row(for: medicine, showCoverageInfo: false, infoMode: MedicineRowView.InfoMode.nextDose, section: .tuttoOk)
                        }
                        // Poi i restanti
                        ForEach(sections.ok) { medicine in
                            row(for: medicine, showCoverageInfo: false, infoMode: MedicineRowView.InfoMode.frequency, section: .tuttoOk)
                        }
                    }
                }
            }
        }
        // Ricostruisce la vista quando cambia il numero di log (assunzioni/acquisti)
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
                    .presentationDetents([.medium, .large])
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
        .onChange(of: selectedMedicine) { newValue in
            if (newValue == nil) {
                viewModel.clearSelection()
            }
        }
        .onAppear {
            // Avvia ricerca farmacia per mostrare nome e distanza
            locationVM.ensureStarted()
        }
    }
    
    // MARK: - Row builder (gestures + card)
    private func row(for medicine: Medicine, showCoverageInfo: Bool, infoMode: MedicineRowView.InfoMode, showPurchaseShortcut: Bool = false, section: MedicineRowView.RowSection = .tuttoOk) -> some View {
        MedicineRowView(
            medicine: medicine,
            isSelected: viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine),
            toggleSelection: { viewModel.toggleSelection(for: medicine) },
            showCoverageInfo: showCoverageInfo,
            infoMode: infoMode, showPurchaseShortcut: showPurchaseShortcut, section: section
        )
        .padding(8)
        .background(viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine) ? Color.gray.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        // Usa gesture con including: .gesture per non interferire con i pulsanti interni
        .gesture(
            TapGesture().onEnded {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: medicine)
                } else {
                    selectedMedicine = medicine
                }
            }, including: .gesture
        )
        .gesture(
            LongPressGesture().onEnded { _ in
                selectedMedicine = medicine
                Haptics.impact(.medium)
            }, including: .gesture
        )
        .accessibilityIdentifier("MedicineRow_\(medicine.objectID)")
    }
    
    // MARK: - New sorting algorithm (sections)
    private func computeSections() -> (purchase: [Medicine], oggi: [Medicine], ok: [Medicine]) {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let cal = Calendar.current
        let endOfDay: Date = {
            let start = cal.startOfDay(for: now)
            return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()
        let coverageThreshold = Int(options.first?.day_threeshold_stocks_alarm ?? 7)
        
        enum StockStatus {
            case ok
            case low
            case critical
            case unknown
        }
        
        // Calcolo unità rimanenti per una medicine, basato su logs e package
        func remainingUnits(for m: Medicine) -> Int? {
            if let therapies = m.therapies, !therapies.isEmpty {
                return therapies.reduce(0) { $0 + Int($1.leftover()) }
            }
            return m.remainingUnitsWithoutTherapy()
        }
        
        func nextOccurrenceToday(for m: Medicine) -> Date? {
            guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
            var best: Date? = nil
            for t in therapies {
                let rule = rec.parseRecurrenceString(t.rrule ?? "")
                let startDate = t.start_date ?? now
                if let d = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: t.doses as NSSet?) {
                    if cal.isDate(d, inSameDayAs: now) && d <= endOfDay {
                        if best == nil || d < best! { best = d }
                    }
                }
            }
            return best
        }
        
        // Prossima assunzione (anche oltre oggi): usata come primo criterio d'ordinamento
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
        
        // MARK: - Pianificazione: conteggio dosi previste oggi
        func icsCode(for date: Date) -> String {
            let weekday = cal.component(.weekday, from: date)
            switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" }
        }
        
        func occursToday(_ t: Therapy) -> Bool {
            let rule = rec.parseRecurrenceString(t.rrule ?? "")
            let start = t.start_date ?? now
            // Se la therapy parte dopo oggi, non è prevista oggi
            if start > endOfDay { return false }
            // Rispetta eventuale UNTIL
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
                
                // Verifica intervallo settimanale
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
        
        func scheduledDosesTodayCount(for t: Therapy) -> Int {
            guard occursToday(t) else { return 0 }
            let count = t.doses?.count ?? 0
            return max(0, count)
        }
        
        func scheduledDosesTodayCount(for m: Medicine) -> Int {
            guard let therapies = m.therapies, !therapies.isEmpty else { return 0 }
            return therapies.reduce(0) { $0 + scheduledDosesTodayCount(for: $1) }
        }
        
        func intakeLogsTodayCount(for m: Medicine) -> Int {
            // Conta solo le assunzioni odierne legate a terapie che ricorrono oggi (o senza therapy per compatibilità)
            let todaysTherapies: Set<Therapy> = Set((m.therapies ?? []).filter { occursToday($0) })
            return logs.filter { log in
                guard log.medicine == m, log.type == "intake", cal.isDate(log.timestamp, inSameDayAs: now) else { return false }
                if let t = log.therapy { return todaysTherapies.contains(t) }
                return true
            }.count
        }
        
        // Soglie fisse per classificazione
        // <5 unità  => sezione "Oggi"
        // <7 unità  => sezione "Da tenere d'occhio"
        // Nota: da ora "Oggi" considera SOLO dosi odierne rimanenti, non la criticità scorte
        func coverageDays(for m: Medicine) -> Double? {
            guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
            var totalLeftover: Double = 0
            var totalDailyUsage: Double = 0
            for therapy in therapies {
                totalLeftover += Double(therapy.leftover())
                totalDailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: rec)
            }
            if totalDailyUsage <= 0 {
                return totalLeftover > 0 ? Double.greatestFiniteMagnitude : 0
            }
            return totalLeftover / totalDailyUsage
        }
        
        func stockStatus(for m: Medicine) -> StockStatus {
            if let coverage = coverageDays(for: m) {
                if coverage <= 0 {
                    return .critical
                }
                return coverage < Double(coverageThreshold) ? .low : .ok
            }
            if let remaining = m.remainingUnitsWithoutTherapy() {
                if remaining <= 0 { return .critical }
                return remaining < 7 ? .low : .ok
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
        
        // Ordinamento: 1) prossima assunzione (ASC) 2) stato scorte (rimanenti, ASC) 3) nome
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
        
        // Ordina Da comprare: prima i critical, poi rimanenti ASC, poi nome
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
    
    // MARK: - Low stock detection (per mostrare la card)
    private func hasLowStock() -> Bool {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let threshold = Int(options.first?.day_threeshold_stocks_alarm ?? 7)
        for m in medicines {
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
                    if remaining <= 0 || remaining < 7 { return true }
                }
            }
        }
        return false
    }
    
    // MARK: - Nearest pharmacy card
    struct NearestPharmacyCard: View {
        @ObservedObject var viewModel: LocationSearchViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "cross.case.fill")
                        .foregroundStyle(.green)
                    Text("Farmacia più vicina")
                        .font(.headline)
                    Spacer()
                    if let d = viewModel.distanceString { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(.top, 4)
                
                if let name = viewModel.pinItem?.title {
                    // Al posto della mappa, mostra nome farmacia e distanza
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                        if let d = viewModel.distanceString {
                            Text(d)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let opening = viewModel.todayOpeningText {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text("Oggi: \(opening)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            viewModel.openInMaps()
                        } label: {
                            Label("Apri in Mappe", systemImage: "arrow.turn.up.right")
                        }
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 60)
                        .overlay(
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Cerco farmacie vicine…")
                                    .foregroundStyle(.secondary)
                            }
                        )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
            )
            .onAppear { viewModel.ensureStarted() }
        }
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
