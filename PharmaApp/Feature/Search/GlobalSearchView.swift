import SwiftUI
import CoreData
import MapKit
import UIKit

struct GlobalSearchView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appRouter: AppRouter

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    @FetchRequest(fetchRequest: MedicinePackage.extractEntries())
    private var medicineEntries: FetchedResults<MedicinePackage>

    @FetchRequest(fetchRequest: Therapy.extractTherapies())
    private var therapies: FetchedResults<Therapy>

    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>

    @FetchRequest(fetchRequest: Person.extractPersons())
    private var persons: FetchedResults<Person>

    @StateObject private var locationVM = LocationSearchViewModel()
    @StateObject private var cabinetViewModel = CabinetViewModel()
    @State private var query: String = ""
    @State private var selectedScope: SearchScope = .all
    @State private var activeAction: QuickAction?

    @State private var selectedMedicine: Medicine?
    @State private var selectedMedicineEntry: MedicinePackage?
    @State private var selectedPackage: Package?
    @State private var selectedDoctor: Doctor?
    @State private var isDoctorDetailPresented = false
    @State private var selectedPerson: Person?
    @State private var isPersonDetailPresented = false

    @State private var fullscreenBarcodeCodiceFiscale: String?
    @State private var isCatalogSearchPresented = false
    @State private var shouldAutoStartScan = false
    @State private var shouldAutoFocusSearch = false
    @State private var pendingCatalogSelection: CatalogSelection?
    @State private var catalogStockEditorState: CatalogStockEditorState?
    @State private var catalogTherapyEditorState: CatalogTherapyEditorState?
    @State private var catalogMedicines: [CatalogSelection] = []
    @State private var inlineFeedback: CommandFeedback?
    @State private var pharmacyResults: [PharmacyResult] = []
    @State private var pharmacySearchTask: Task<Void, Never>?

    @AppStorage("search.recent.items") private var recentItemsRaw: String = ""

    private let maxRecentItems = 5

    private enum SearchScope: String, CaseIterable, Identifiable {
        case all = "Tutti"
        case medicines = "Farmaci"
        case therapies = "Terapie"
        case contacts = "Contatti"

        var id: String { rawValue }

        var menuLabel: String {
            switch self {
            case .all: return "Farmaci / Terapie / Contatti"
            case .medicines: return "Farmaci"
            case .therapies: return "Terapie"
            case .contacts: return "Contatti"
            }
        }
    }

    private enum QuickAction: Hashable, Identifiable {
        case lowStock
        case today
        case person(NSManagedObjectID)

        var id: String {
            switch self {
            case .lowStock: return "lowStock"
            case .today: return "today"
            case .person(let oid): return "person-\(oid)"
            }
        }
    }

    private enum RecentKind: String, Codable {
        case medicine
        case medicineEntry
        case therapy
        case doctor
        case person
        case query
    }

    private struct RecentItem: Identifiable, Codable {
        let id: UUID
        let kind: RecentKind
        let objectURI: String?
        let title: String
        let subtitle: String?
        let timestamp: Date
    }

    private struct NextDoseEntry: Identifiable {
        let medicine: Medicine
        let nextDose: Date

        var id: NSManagedObjectID { medicine.objectID }
    }

    private struct CommandFeedback: Identifiable {
        enum Kind {
            case success
            case error

            var title: String {
                switch self {
                case .success:
                    return "Operazione completata"
                case .error:
                    return "Operazione non riuscita"
                }
            }
        }

        let id: UUID = UUID()
        let kind: Kind
        let message: String
    }

    private struct CatalogResolvedContext {
        let selection: CatalogSelection
        let medicine: Medicine
        let package: Package
        let entry: MedicinePackage
    }

    private struct CatalogStockEditorState: Identifiable {
        let id: UUID = UUID()
        let context: CatalogResolvedContext
        let initialUnits: Int
        let deadlineMonth: String
        let deadlineYear: String
    }

    private struct CatalogTherapyEditorState: Identifiable {
        let id: UUID = UUID()
        let context: CatalogResolvedContext
    }

    private struct WatchEntry: Identifiable {
        enum Badge {
            case lowStock
            case today
            case expiring

            var text: String {
                switch self {
                case .lowStock: return "Scorte basse"
                case .today: return "Oggi"
                case .expiring: return "In scadenza"
                }
            }
        }

        let medicine: Medicine
        let badge: Badge
        let detail: String
        let priority: Int
        let sortValue: Double

        var id: NSManagedObjectID { medicine.objectID }
    }

    private struct PharmacyResult: Identifiable {
        let id = UUID()
        let mapItem: MKMapItem
        var name: String { mapItem.name ?? "Farmacia" }
        var address: String? {
            let pm = mapItem.placemark
            let text = [pm.thoroughfare, pm.subThoroughfare, pm.locality]
                .compactMap { $0 }
                .joined(separator: " ")
            return text.isEmpty ? nil : text
        }
        var phone: String? {
            guard let p = mapItem.phoneNumber, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return p
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recurrenceManager: RecurrenceManager {
        .shared
    }

    private var stockService: MedicineStockService {
        MedicineStockService(context: managedObjectContext)
    }

    private var option: Option? {
        Option.current(in: managedObjectContext)
    }

    private var medicineRowSnapshots: [NSManagedObjectID: CabinetViewModel.CabinetRowSnapshot] {
        cabinetViewModel.buildRowSnapshots(entries: filteredMedicineEntries, option: option)
    }

    private var recentItems: [RecentItem] {
        guard let data = recentItemsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private var topRecentItems: [RecentItem] {
        Array(
            recentItems
                .filter { item in
                    item.kind == .medicine || item.kind == .medicineEntry
                }
                .prefix(maxRecentItems)
        )
    }

    private func queryHasResults(_ text: String) -> Bool {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        if medicineEntries.contains(where: {
            ($0.medicine.nome).localizedCaseInsensitiveContains(q)
            || ($0.medicine.principio_attivo).localizedCaseInsensitiveContains(q)
        }) { return true }
        if therapies.contains(where: {
            (therapyMedicine($0)?.nome ?? "").localizedCaseInsensitiveContains(q)
            || (therapyMedicine($0)?.principio_attivo ?? "").localizedCaseInsensitiveContains(q)
        }) { return true }
        if doctors.contains(where: {
            ($0.nome ?? "").localizedCaseInsensitiveContains(q)
            || ($0.cognome ?? "").localizedCaseInsensitiveContains(q)
        }) { return true }
        if persons.contains(where: {
            ($0.nome ?? "").localizedCaseInsensitiveContains(q)
            || ($0.cognome ?? "").localizedCaseInsensitiveContains(q)
        }) { return true }
        return false
    }

    private var lowStockOrExpiringMedicines: [Medicine] {
        let lowStock = Set(
            medicines.filter { $0.isInEsaurimento(option: option!, recurrenceManager: recurrenceManager) }
        )
        let expiring = Set(
            medicines.filter { $0.deadlineStatus == .expiringSoon || $0.deadlineStatus == .expired }
        )
        return lowStock.union(expiring)
            .sorted { lhs, rhs in
                let leftDays = stockCoverageDays(for: lhs) ?? Int.max
                let rightDays = stockCoverageDays(for: rhs) ?? Int.max
                if leftDays == rightDays {
                    return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
                }
                return leftDays < rightDays
            }
    }

    private var todayDoseEntries: [NextDoseEntry] {
        let now = Date()
        let calendar = Calendar.current
        return medicines.compactMap { medicine in
            guard let next = medicine.nextIntakeDate(from: now, recurrenceManager: recurrenceManager),
                  calendar.isDateInToday(next) else {
                return nil
            }
            return NextDoseEntry(medicine: medicine, nextDose: next)
        }
        .sorted { $0.nextDose < $1.nextDose }
    }

    private var nextDoseEntries: [NextDoseEntry] {
        let now = Date()
        return medicines.compactMap { medicine in
            guard let next = medicine.nextIntakeDate(from: now, recurrenceManager: recurrenceManager) else {
                return nil
            }
            return NextDoseEntry(medicine: medicine, nextDose: next)
        }
        .sorted { $0.nextDose < $1.nextDose }
    }

    private func medicinesForPerson(_ person: Person) -> [Medicine] {
        guard let therapySet = person.therapies else { return [] }
        var seen = Set<NSManagedObjectID>()
        var result: [Medicine] = []
        for therapy in therapySet {
            let medicine = therapy.medicine
            if !seen.contains(medicine.objectID) {
                seen.insert(medicine.objectID)
                result.append(medicine)
            }
        }
        return result.sorted { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }
    }

    private var availableQuickActions: [QuickAction] {
        var actions: [QuickAction] = []
        if !lowStockOrExpiringMedicines.isEmpty {
            actions.append(.lowStock)
        }
        if !todayDoseEntries.isEmpty {
            actions.append(.today)
        }
        if persons.count > 1 {
            for person in persons {
                if !personMedicinesForObjectID(person.objectID).isEmpty {
                    actions.append(.person(person.objectID))
                }
            }
        }
        return actions
    }

    private func quickActionTitle(_ action: QuickAction) -> String {
        switch action {
        case .lowStock: return "Scorte basse"
        case .today: return "Oggi"
        case .person(let oid):
            if let person = try? managedObjectContext.existingObject(with: oid) as? Person {
                return personDisplayName(for: person)
            }
            return "Persona"
        }
    }

    private func quickActionCount(_ action: QuickAction) -> Int {
        switch action {
        case .lowStock: return lowStockOrExpiringMedicines.count
        case .today: return todayDoseEntries.count
        case .person(let oid): return personMedicinesForObjectID(oid).count
        }
    }

    private var watchEntries: [WatchEntry] {
        var grouped: [NSManagedObjectID: WatchEntry] = [:]
        let calendar = Calendar.current
        let now = Date()

        for medicine in medicines {
            if medicine.isInEsaurimento(option: option!, recurrenceManager: recurrenceManager) {
                let days = stockCoverageDays(for: medicine)
                let detail: String
                let sortValue: Double
                if let days {
                    detail = days <= 0 ? "0 giorni" : "\(days) giorni"
                    sortValue = Double(max(days, 0))
                } else {
                    detail = "Scorte da verificare"
                    sortValue = 9_999
                }
                grouped[medicine.objectID] = WatchEntry(
                    medicine: medicine,
                    badge: .lowStock,
                    detail: detail,
                    priority: 0,
                    sortValue: sortValue
                )
            }

            if let next = medicine.nextIntakeDate(from: now, recurrenceManager: recurrenceManager),
               calendar.isDateInToday(next) {
                let candidate = WatchEntry(
                    medicine: medicine,
                    badge: .today,
                    detail: hourFormatter.string(from: next),
                    priority: 1,
                    sortValue: next.timeIntervalSinceReferenceDate
                )
                if let existing = grouped[medicine.objectID] {
                    if candidate.priority < existing.priority || (candidate.priority == existing.priority && candidate.sortValue < existing.sortValue) {
                        grouped[medicine.objectID] = candidate
                    }
                } else {
                    grouped[medicine.objectID] = candidate
                }
            }

            if medicine.deadlineStatus == .expiringSoon || medicine.deadlineStatus == .expired {
                let days = daysUntilDeadline(for: medicine) ?? Int.max
                let detail: String
                if days < 0 {
                    detail = "Scaduto"
                } else {
                    detail = "\(days) giorni"
                }
                let candidate = WatchEntry(
                    medicine: medicine,
                    badge: .expiring,
                    detail: detail,
                    priority: 2,
                    sortValue: Double(days)
                )
                if let existing = grouped[medicine.objectID] {
                    if candidate.priority < existing.priority || (candidate.priority == existing.priority && candidate.sortValue < existing.sortValue) {
                        grouped[medicine.objectID] = candidate
                    }
                } else {
                    grouped[medicine.objectID] = candidate
                }
            }
        }

        return grouped.values
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    if lhs.sortValue == rhs.sortValue {
                        return lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
                    }
                    return lhs.sortValue < rhs.sortValue
                }
                return lhs.priority < rhs.priority
            }
            .prefix(5)
            .map { $0 }
    }

    private var suggestedActiveTherapies: [NextDoseEntry] {
        Array(nextDoseEntries.prefix(3))
    }

    private var suggestedTopMedicines: [(medicine: Medicine, intakeCount: Int)] {
        medicines.compactMap { medicine in
            let count = medicine.effectiveIntakeLogs().count
            guard count > 0 else { return nil }
            return (medicine, count)
        }
        .sorted { lhs, rhs in
            if lhs.intakeCount == rhs.intakeCount {
                return lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
            }
            return lhs.intakeCount > rhs.intakeCount
        }
        .prefix(3)
        .map { $0 }
    }

    private var filteredMedicineEntries: [MedicinePackage] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .medicines else { return [] }
        return cabinetViewModel.searchEntries(
            query: trimmedQuery,
            entries: Array(medicineEntries),
            option: option
        )
    }

    private var filteredTherapies: [Therapy] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .therapies else { return [] }
        return therapies.filter { therapy in
            let medicineName = therapyMedicine(therapy)?.nome ?? ""
            let principle = therapyMedicine(therapy)?.principio_attivo ?? ""
            let personName = therapyPerson(therapy).map(personDisplayName(for:)) ?? "Persona"
            return medicineName.localizedCaseInsensitiveContains(trimmedQuery)
            || principle.localizedCaseInsensitiveContains(trimmedQuery)
            || personName.localizedCaseInsensitiveContains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            therapyMedicineName(lhs).localizedCaseInsensitiveCompare(therapyMedicineName(rhs)) == .orderedAscending
        }
    }

    private var filteredDoctors: [Doctor] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .contacts else { return [] }
        return doctors.filter { doctor in
            (doctor.nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.cognome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.telefono ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.mail ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.segreteria_nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.segreteria_telefono ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.segreteria_mail ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            doctorDisplayName(lhs).localizedCaseInsensitiveCompare(doctorDisplayName(rhs)) == .orderedAscending
        }
    }

    private var filteredPersons: [Person] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .contacts else { return [] }
        return persons.filter { person in
            (person.nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (person.cognome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (person.codice_fiscale ?? "").localizedCaseInsensitiveContains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            personDisplayName(for: lhs).localizedCaseInsensitiveCompare(personDisplayName(for: rhs)) == .orderedAscending
        }
    }

    private var hasTextSearchResults: Bool {
        !filteredMedicineEntries.isEmpty
            || !filteredTherapies.isEmpty
            || !filteredDoctors.isEmpty
            || !filteredPersons.isEmpty
            || !pharmacyResults.isEmpty
    }

    private var medicinesInCabinetIdentityKeys: Set<String> {
        Set(
            medicines
                .filter { medicine in
                    medicine.in_cabinet || (medicine.medicinePackages?.isEmpty == false)
                }
                .map { medicine in
                    catalogIdentityKey(name: medicine.nome, principle: medicine.principio_attivo)
                }
        )
    }

    private var medicinesInCabinetNames: Set<String> {
        Set(
            medicines
                .filter { medicine in
                    medicine.in_cabinet || (medicine.medicinePackages?.isEmpty == false)
                }
                .map { medicine in
                    normalizeCatalogText(medicine.nome)
                }
        )
    }

    private var preferredDoctor: Doctor? {
        let now = Date()
        if let open = doctors.first(where: { activeDoctorInterval(for: $0, now: now) != nil }) {
            return open
        }
        if let today = doctors.first(where: { doctorTodaySlotText(for: $0) != nil }) {
            return today
        }
        return doctors.first
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                if let activeAction {
                    shortcutResultsSection(for: activeAction)
                } else {
                    recentSection
                }
            } else {
                searchResultsSections
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if trimmedQuery.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    ForEach(Array(availableQuickActions.enumerated()), id: \.element.id) { index, action in
                        let count = quickActionCount(action)
                        Button {
                            handleActionTap(action)
                        } label: {
                            HStack(spacing: 6) {
                                Text(quickActionTitle(action))
                                    .font(.system(size: 17, weight: .regular))
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(activeAction == action ? Color.white.opacity(0.85) : Color.secondary)
                                }
                            }
                            .foregroundStyle(activeAction == action ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(activeAction == action ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                                    .shadow(color: Color.primary.opacity(0.08), radius: 8, x: 0, y: 2)
                            )
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.45, dampingFraction: 0.65, blendDuration: 0)
                                .delay(Double(index) * 0.06),
                            value: trimmedQuery.isEmpty
                        )
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .animation(.spring(response: 0.45, dampingFraction: 0.65, blendDuration: 0), value: trimmedQuery.isEmpty)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Cerca farmaci, terapie, contatti"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            guard !trimmedQuery.isEmpty else { return }
            addRecentQuery(trimmedQuery)
        }
        .background(
            SearchFieldAutoFocusInstaller(shouldFocus: shouldAutoFocusSearch) {
                shouldAutoFocusSearch = false
            }
        )
        .onChange(of: query) { value in
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                activeAction = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil || selectedMedicineEntry != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMedicine = nil
                    selectedMedicineEntry = nil
                    selectedPackage = nil
                }
            }
        )) {
            if let entry = selectedMedicineEntry {
                MedicineDetailView(
                    medicine: entry.medicine,
                    package: entry.package,
                    medicinePackage: entry
                )
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
            } else if let medicine = selectedMedicine {
                if let package = selectedPackage ?? getPackage(for: medicine) {
                    MedicineDetailView(medicine: medicine, package: package)
                        .presentationDetents([.fraction(0.75), .large])
                        .presentationDragIndicator(.visible)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Completa i dati del farmaco")
                            .font(.headline)
                        Text("Aggiungi una confezione per aprire il dettaglio completo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
        .navigationDestination(isPresented: $isDoctorDetailPresented) {
            if let doctor = selectedDoctor {
                DoctorDetailView(doctor: doctor)
            }
        }
        .navigationDestination(isPresented: $isPersonDetailPresented) {
            if let person = selectedPerson {
                PersonDetailView(person: person)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { fullscreenBarcodeCodiceFiscale != nil },
            set: { if !$0 { fullscreenBarcodeCodiceFiscale = nil } }
        )) {
            if let cf = fullscreenBarcodeCodiceFiscale {
                FullscreenBarcodeView(codiceFiscale: cf) {
                    fullscreenBarcodeCodiceFiscale = nil
                }
            }
        }
    }

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cerca")
                    .font(.system(size: 26, weight: .semibold))
                Text("Farmaci, terapie, contatti, farmacie")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowSeparator(.hidden)
    }

    private var scopeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchScope.allCases) { scope in
                        Button {
                            selectedScope = scope
                        } label: {
                            Text(scope.rawValue)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(selectedScope == scope ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selectedScope == scope ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } footer: {
            Text(scopeFooterText)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var utilitySection: some View {
        Section {
            ProfilePharmacyCard()
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
        } header: {
            sectionHeader("Farmacia")
        }

        Section {
            ForEach(doctors) { doctor in
                Button {
                    openDoctor(doctor)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(doctorDisplayName(doctor))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(doctorPrimaryLineFor(doctor))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            if doctors.isEmpty {
                emptyLine("Nessun dottore aggiunto")
            }
        } header: {
            sectionHeader("Dottori")
        }

        if !personsWithCodiceFiscale.isEmpty {
            Section {
                ForEach(personsWithCodiceFiscale) { person in
                    Button {
                        fullscreenBarcodeCodiceFiscale = person.codice_fiscale
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(personDisplayName(for: person))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                            CodiceFiscaleBarcodeView(codiceFiscale: person.codice_fiscale!)
                                .frame(height: 50)
                            Text(person.codice_fiscale!)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader("Tessere sanitarie")
            }
        }
    }

    private var personsWithCodiceFiscale: [Person] {
        persons.filter { person in
            guard let cf = person.codice_fiscale else { return false }
            return !cf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func doctorPrimaryLineFor(_ doctor: Doctor) -> String {
        let now = Date()
        if let active = activeDoctorInterval(for: doctor, now: now) {
            return "Aperto fino alle \(OpeningHoursParser.timeString(from: active.end))"
        }
        if let today = doctorTodaySlotText(for: doctor) {
            return "Oggi \(today)"
        }
        if let next = doctorNextOpeningLabel(for: doctor, now: now) {
            return "Prossima apertura: \(next)"
        }
        return "Orari non disponibili"
    }

    @ViewBuilder
    private var watchSection: some View {
        Section {
            if watchEntries.isEmpty {
                emptyLine("Nessun elemento urgente al momento")
            } else {
                ForEach(watchEntries) { entry in
                    Button {
                        openMedicine(entry.medicine)
                    } label: {
                        watchRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader("Da tenere d'occhio")
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        Section {
            if topRecentItems.isEmpty {
                emptyLine("Nessun recente")
            } else {
                ForEach(topRecentItems) { item in
                    Button {
                        openRecent(item)
                    } label: {
                        recentRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader("Recenti")
        }
    }

    @ViewBuilder
    private var focusSuggestionsSections: some View {
        Section {
            if suggestedActiveTherapies.isEmpty && suggestedTopMedicines.isEmpty && recentItems.filter({ $0.kind == .medicine || $0.kind == .medicineEntry }).isEmpty {
                emptyLine("Nessun suggerimento disponibile")
            } else {
                ForEach(suggestedActiveTherapies) { entry in
                    Button {
                        openMedicine(entry.medicine)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Terapia attiva · \(camelCase(entry.medicine.nome))")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            Text("Prossima dose alle \(hourFormatter.string(from: entry.nextDose))")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(suggestedTopMedicines, id: \.medicine.objectID) { item in
                    Button {
                        openMedicine(item.medicine)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Farmaco usato spesso · \(camelCase(item.medicine.nome))")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            Text("\(item.intakeCount) registrazioni")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(Array(recentItems.filter { $0.kind == .medicine || $0.kind == .medicineEntry }.prefix(3))) { item in
                    Button {
                        openRecent(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recente · \(item.title)")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            sectionHeader("Suggerimenti")
        }

        if !availableQuickActions.isEmpty {
            Section {
                if !lowStockOrExpiringMedicines.isEmpty {
                    quickActionRow(title: "Scorte basse") { handleActionTap(.lowStock) }
                }
                if !todayDoseEntries.isEmpty {
                    quickActionRow(title: "Oggi") { handleActionTap(.today) }
                }
            } header: {
                sectionHeader("Filtri")
            }
        }
    }

    @ViewBuilder
    private var searchResultsSections: some View {
        if !filteredMedicineEntries.isEmpty {
            Section {
                ForEach(filteredMedicineEntries) { entry in
                    Button {
                        openMedicineEntry(entry)
                    } label: {
                        medicineRow(entry)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                sectionHeader("Farmaci")
            }
        }

        if filteredMedicineEntries.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    emptyLine("Nessun farmaco trovato per \"\(trimmedQuery)\"")
                    Text("La ricerca include solo farmaci presenti nell'armadietto. Per aggiungerne uno nuovo usa il + nella schermata Armadietto.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listRowSeparator(.hidden)
        }
    }

    private var scopeFooterText: String {
        switch selectedScope {
        case .all:
            return "Farmaci presenti nell'armadietto, terapie e contatti."
        case .medicines:
            return "Mostra solo farmaci gia presenti nell'armadietto."
        case .therapies:
            return "Mostra solo terapie attive o salvate."
        case .contacts:
            return "Mostra solo dottori e persone."
        }
    }

    private var emptySearchMessage: String {
        switch selectedScope {
        case .all:
            return "La ricerca include farmaci gia nell'armadietto, terapie e contatti. Per aggiungere un nuovo farmaco usa il + nella schermata Armadietto."
        case .medicines:
            return "La ricerca farmaci vale solo per quelli gia nell'armadietto. Per aggiungerne uno nuovo usa il + nella schermata Armadietto."
        case .therapies:
            return "Nessuna terapia trovata con questa ricerca."
        case .contacts:
            return "Nessun contatto trovato con questa ricerca."
        }
    }

    @ViewBuilder
    private func shortcutResultsSection(for action: QuickAction) -> some View {
        switch action {
        case .lowStock:
            Section {
                if lowStockOrExpiringMedicines.isEmpty {
                    emptyLine("Nessun farmaco con scorte basse o in scadenza")
                } else {
                    ForEach(lowStockOrExpiringMedicines) { medicine in
                        Button {
                            openMedicine(medicine)
                        } label: {
                            fullMedicineRow(for: medicine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader("Scorte basse")
            }

        case .today:
            Section {
                if todayDoseEntries.isEmpty {
                    emptyLine("Nessuna dose per oggi")
                } else {
                    ForEach(todayDoseEntries) { entry in
                        Button {
                            openMedicine(entry.medicine)
                        } label: {
                            fullMedicineRow(for: entry.medicine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader("Oggi")
            }

        case .person(let oid):
            let personMedicines = personMedicinesForObjectID(oid)
            Section {
                if personMedicines.isEmpty {
                    emptyLine("Nessun farmaco per questa persona")
                } else {
                    ForEach(personMedicines) { medicine in
                        Button {
                            openMedicine(medicine)
                        } label: {
                            fullMedicineRow(for: medicine)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader(quickActionTitle(action))
            }
        }
    }

    private func personMedicinesForObjectID(_ oid: NSManagedObjectID) -> [Medicine] {
        guard let person = try? managedObjectContext.existingObject(with: oid) as? Person else { return [] }
        return medicinesForPerson(person)
    }

    private func fullMedicineRow(for medicine: Medicine) -> some View {
        let entry = medicine.medicinePackages?.first
        return MedicineRowView(
            medicine: medicine,
            medicinePackage: entry,
            subtitleMode: .activeTherapies,
            snapshot: entry.flatMap { medicineRowSnapshots[$0.objectID]?.presentation }
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func watchRow(_ entry: WatchEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(camelCase(entry.medicine.nome))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(entry.badge.text)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                )
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(entry.detail)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recentRow(_ item: RecentItem) -> some View {
        switch item.kind {
        case .medicine:
            if let medicine: Medicine = object(from: item.objectURI) {
                fullMedicineRow(for: medicine)
            } else {
                recentFallbackRow(item)
            }

        case .medicineEntry:
            if let entry: MedicinePackage = object(from: item.objectURI) {
                fullMedicineRow(for: entry.medicine)
            } else {
                recentFallbackRow(item)
            }

        case .therapy:
            if let therapy: Therapy = object(from: item.objectURI) {
                recentTherapyRow(therapy)
            } else {
                recentFallbackRow(item)
            }

        case .doctor:
            if let doctor: Doctor = object(from: item.objectURI) {
                recentDoctorRow(doctor)
            } else {
                recentFallbackRow(item)
            }

        case .person:
            if let person: Person = object(from: item.objectURI) {
                recentPersonRow(person)
            } else {
                recentFallbackRow(item)
            }

        case .query:
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recentFallbackRow(_ item: RecentItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: recentKindIcon(item.kind))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentMedicineRow(_ medicine: Medicine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "pill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(camelCase(medicine.nome))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if !medicine.principio_attivo.isEmpty {
                        Text(medicine.principio_attivo)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    if let days = stockCoverageDays(for: medicine) {
                        Text("· \(days) giorni di scorta")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func recentTherapyRow(_ therapy: Therapy) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(therapyMedicineName(therapy))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                let nextDose = recurrenceManager.nextOccurrence(
                    rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
                    startDate: therapy.start_date ?? Date(),
                    after: Date(),
                    doses: therapy.doses as NSSet?
                )
                if let nextDose {
                    Text("Prossima dose \(doseDateTimeFormatter.string(from: nextDose))")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Terapia")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func recentDoctorRow(_ doctor: Doctor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "stethoscope")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(doctorDisplayName(doctor))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(doctorPrimaryLineFor(doctor))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func recentPersonRow(_ person: Person) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(personDisplayName(for: person))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                if let cf = person.codice_fiscale, !cf.isEmpty {
                    Text(cf)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func recentKindIcon(_ kind: RecentKind) -> String {
        switch kind {
        case .medicine, .medicineEntry: return "pill"
        case .therapy: return "calendar.badge.clock"
        case .doctor: return "stethoscope"
        case .person: return "person"
        case .query: return "magnifyingglass"
        }
    }

    private func medicineRow(_ entry: MedicinePackage) -> some View {
        MedicineRowView(
            medicine: entry.medicine,
            medicinePackage: entry,
            subtitleMode: .activeTherapies,
            snapshot: medicineRowSnapshots[entry.objectID]?.presentation
        )
    }

    private func therapyRow(_ therapy: Therapy) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(therapyMedicineName(therapy))
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)

            let nextDose = recurrenceManager.nextOccurrence(
                rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
                startDate: therapy.start_date ?? Date(),
                after: Date(),
                doses: therapy.doses as NSSet?
            )

            if let nextDose {
                Text("Prossima dose \(doseDateTimeFormatter.string(from: nextDose))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            } else {
                Text(therapyPerson(therapy).map(personDisplayName(for:)) ?? "Persona")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func doctorRow(_ doctor: Doctor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(doctorDisplayName(doctor))
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)

            if let subtitle = doctorSearchSubtitle(doctor) {
                Text(subtitle)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func personRow(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(personDisplayName(for: person))
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)

            if let cf = person.codice_fiscale, !cf.isEmpty {
                Text(cf)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pharmacyRow(_ pharmacy: PharmacyResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "cross.case")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.green)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(pharmacy.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                if let address = pharmacy.address {
                    Text(address)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                if let phone = pharmacy.phone {
                    Text(phone)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func medicineStatusRow(medicine: Medicine, badge: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(camelCase(medicine.nome))
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(badge)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.18))
                )
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text(detail)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private func quickActionRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func handleActionTap(_ action: QuickAction) {
        query = ""
        if activeAction == action {
            activeAction = nil
        } else {
            activeAction = action
        }
    }

    private func openMedicine(
        _ medicine: Medicine,
        package: Package? = nil
    ) {
        selectedMedicineEntry = nil
        selectedPackage = package
        selectedMedicine = medicine
        addRecent(
            kind: .medicine,
            objectID: medicine.objectID,
            title: camelCase(medicine.nome),
            subtitle: nil
        )
    }

    private func openMedicineEntry(_ entry: MedicinePackage) {
        selectedMedicine = nil
        selectedPackage = nil
        selectedMedicineEntry = entry
        addRecent(
            kind: .medicineEntry,
            objectID: entry.objectID,
            title: camelCase(entry.medicine.nome),
            subtitle: nil
        )
    }

    private func handleCatalogAddToCabinet(_ selection: CatalogSelection) {
        _ = resolveCatalogContext(for: selection)
        do {
            try saveManagedContextIfNeeded()
            inlineFeedback = CommandFeedback(kind: .success, message: "Aggiunto all'armadietto.")
        } catch {
            managedObjectContext.rollback()
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito ad aggiungere il farmaco all'armadietto."
            )
        }
    }

    private func handleCatalogAddPackage(_ selection: CatalogSelection) {
        let resolved = resolveCatalogContext(for: selection)
        do {
            try saveManagedContextIfNeeded()
        } catch {
            managedObjectContext.rollback()
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito a preparare la modifica scorte."
            )
            return
        }

        let currentUnits = StockService(context: managedObjectContext).units(for: resolved.package)
        let (month, year) = deadlineInputs(for: resolved.medicine, package: resolved.package)
        let defaultTarget = currentUnits + max(1, selection.units)
        catalogStockEditorState = CatalogStockEditorState(
            context: resolved,
            initialUnits: defaultTarget,
            deadlineMonth: month,
            deadlineYear: year
        )
    }

    private func handleCatalogAddTherapy(_ selection: CatalogSelection) {
        let resolved = resolveCatalogContext(for: selection)
        do {
            try saveManagedContextIfNeeded()
            catalogTherapyEditorState = CatalogTherapyEditorState(context: resolved)
        } catch {
            managedObjectContext.rollback()
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito ad aprire il form terapia."
            )
        }
    }

    private func resolveCatalogContext(for selection: CatalogSelection) -> CatalogResolvedContext {
        let medicine = existingCatalogMedicine(for: selection) ?? createCatalogMedicine(from: selection)
        medicine.in_cabinet = true
        medicine.obbligo_ricetta = medicine.obbligo_ricetta || selection.requiresPrescription

        let package = existingCatalogPackage(for: medicine, selection: selection)
            ?? createCatalogPackage(for: medicine, selection: selection)
        let entry = existingCatalogEntry(for: medicine, package: package)
            ?? createCatalogEntry(for: medicine, package: package)

        return CatalogResolvedContext(
            selection: selection,
            medicine: medicine,
            package: package,
            entry: entry
        )
    }

    private func existingCatalogMedicine(for selection: CatalogSelection) -> Medicine? {
        let identity = catalogIdentityKey(name: selection.name, principle: selection.principle)
        if let exact = medicines.first(where: {
            catalogIdentityKey(name: $0.nome, principle: $0.principio_attivo) == identity
        }) {
            return exact
        }

        let normalizedName = normalizeCatalogText(selection.name)
        return medicines.first(where: { normalizeCatalogText($0.nome) == normalizedName })
    }

    private func existingCatalogPackage(for medicine: Medicine, selection: CatalogSelection) -> Package? {
        medicine.packages.first(where: { packageMatchesCatalogSelection($0, selection: selection) })
    }

    private func existingCatalogEntry(for medicine: Medicine, package: Package) -> MedicinePackage? {
        if let latest = MedicinePackage.latestActiveEntry(
            for: medicine,
            package: package,
            in: managedObjectContext
        ) {
            return latest
        }
        return medicine.medicinePackages?.first(where: { $0.package.objectID == package.objectID })
    }

    private func packageMatchesCatalogSelection(_ package: Package, selection: CatalogSelection) -> Bool {
        let sameUnits = Int(package.numero) == max(1, selection.units)
        let sameType = normalizeCatalogText(package.tipologia) == normalizeCatalogText(selection.tipologia)
        let sameValue = package.valore == selection.valore
        let sameUnit = normalizeCatalogText(package.unita) == normalizeCatalogText(selection.unita)
        let sameVolume = normalizeCatalogText(package.volume) == normalizeCatalogText(selection.volume)
        return sameUnits && sameType && sameValue && sameUnit && sameVolume
    }

    private func createCatalogMedicine(from selection: CatalogSelection) -> Medicine {
        let medicine = Medicine(context: managedObjectContext)
        medicine.id = UUID()
        medicine.source_id = medicine.id
        medicine.visibility = "local"
        medicine.nome = selection.name
        medicine.principio_attivo = selection.principle
        medicine.obbligo_ricetta = selection.requiresPrescription
        medicine.in_cabinet = true
        return medicine
    }

    private func createCatalogPackage(for medicine: Medicine, selection: CatalogSelection) -> Package {
        let package = Package(context: managedObjectContext)
        package.id = UUID()
        package.source_id = package.id
        package.visibility = "local"
        package.tipologia = selection.tipologia.isEmpty ? "Confezione" : selection.tipologia
        package.numero = Int32(max(1, selection.units))
        package.unita = selection.unita.isEmpty ? "unita" : selection.unita
        package.volume = selection.volume
        package.valore = max(0, selection.valore)
        package.principio_attivo = selection.principle
        package.medicine = medicine
        medicine.addToPackages(package)
        return package
    }

    private func createCatalogEntry(for medicine: Medicine, package: Package) -> MedicinePackage {
        let entry = MedicinePackage(context: managedObjectContext)
        entry.id = UUID()
        entry.created_at = Date()
        entry.source_id = entry.id
        entry.visibility = "local"
        entry.medicine = medicine
        entry.package = package
        entry.cabinet = nil
        medicine.addToMedicinePackages(entry)
        return entry
    }

    private func saveManagedContextIfNeeded() throws {
        if managedObjectContext.hasChanges {
            try managedObjectContext.save()
        }
    }

    private func saveCatalogStock(
        _ resolved: CatalogResolvedContext,
        targetUnits: Int,
        monthInput: String,
        yearInput: String
    ) -> Bool {
        let parsedDeadline = parseDeadlineInputs(monthInput: monthInput, yearInput: yearInput)
        guard parsedDeadline.isValid else {
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Scadenza non valida. Usa formato MM/YYYY."
            )
            return false
        }

        do {
            try saveManagedContextIfNeeded()
        } catch {
            managedObjectContext.rollback()
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito a salvare la scadenza."
            )
            return false
        }

        guard let purchaseOperationId = stockService.addPurchase(
            medicine: resolved.medicine,
            package: resolved.package
        ) else {
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito a registrare l'acquisto."
            )
            return false
        }

        guard let purchasedEntry = MedicinePackage.fetchByPurchaseOperationId(
            purchaseOperationId,
            in: managedObjectContext
        ) else {
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito ad associare la confezione acquistata."
            )
            return false
        }

        purchasedEntry.updateDeadline(month: parsedDeadline.month, year: parsedDeadline.year)
        do {
            try saveManagedContextIfNeeded()
        } catch {
            managedObjectContext.rollback()
            inlineFeedback = CommandFeedback(
                kind: .error,
                message: "Non sono riuscito a salvare la scadenza."
            )
            return false
        }

        stockService.setStockUnits(
            medicine: resolved.medicine,
            package: resolved.package,
            targetUnits: max(0, targetUnits)
        )

        catalogStockEditorState = nil
        inlineFeedback = CommandFeedback(
            kind: .success,
            message: "Confezione aggiunta e scorte aggiornate."
        )
        return true
    }

    private func parseDeadlineInputs(
        monthInput: String,
        yearInput: String
    ) -> (isValid: Bool, month: Int?, year: Int?) {
        let monthText = monthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = yearInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if monthText.isEmpty && yearText.isEmpty {
            return (true, nil, nil)
        }

        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return (false, nil, nil)
        }

        return (true, month, year)
    }

    private func deadlineInputs(for medicine: Medicine, package: Package) -> (month: String, year: String) {
        if let entry = MedicinePackage.latestActiveEntry(for: medicine, package: package, in: managedObjectContext),
           let info = entry.deadlineMonthYear {
            return (String(format: "%02d", info.month), String(info.year))
        }
        return ("", "")
    }

    private func openTherapy(_ therapy: Therapy) {
        guard let medicine = therapyMedicine(therapy) else { return }
        selectedPackage = therapyPackage(therapy) ?? getPackage(for: medicine)
        selectedMedicine = medicine
        addRecent(
            kind: .therapy,
            objectID: therapy.objectID,
            title: medicine.nome,
            subtitle: "Terapia"
        )
    }

    private func openDoctor(_ doctor: Doctor) {
        selectedDoctor = doctor
        isDoctorDetailPresented = true
        addRecent(
            kind: .doctor,
            objectID: doctor.objectID,
            title: doctorDisplayName(doctor),
            subtitle: doctorPhone(doctor)
        )
    }

    private func openPerson(_ person: Person) {
        selectedPerson = person
        isPersonDetailPresented = true
        addRecent(
            kind: .person,
            objectID: person.objectID,
            title: personDisplayName(for: person),
            subtitle: person.codice_fiscale
        )
    }

    private func openPreferredDoctor() {
        guard let doctor = preferredDoctor else { return }
        openDoctor(doctor)
    }

    private func openPharmacyDirections() {
        locationVM.ensureStarted()

        guard let item = pharmacyMapItem() else {
            if let url = URL(string: "maps://?q=farmacia") {
                openURL(url)
            }
            return
        }

        let options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), item], launchOptions: options)
    }

    private func pharmacyMapItem() -> MKMapItem? {
        guard let pin = locationVM.pinItem else { return nil }
        if let item = pin.mapItem {
            return item
        }
        let placemark = MKPlacemark(coordinate: pin.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = pin.title
        return item
    }

    private func stockCoverageDays(for medicine: Medicine) -> Int? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }

        var totalLeftover: Double = 0
        var totalDaily: Double = 0
        for therapy in therapies {
            totalLeftover += Double(therapy.leftover())
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }

        guard totalDaily > 0 else { return nil }
        return Int(floor(totalLeftover / totalDaily))
    }

    private func daysUntilDeadline(for medicine: Medicine) -> Int? {
        guard let deadline = medicine.deadlineMonthStartDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: deadline).day
    }

    private func pharmacyDistanceText() -> String? {
        guard let meters = locationVM.distanceMeters else { return nil }
        if meters < 1000 {
            let roundedMeters = Int((meters / 10).rounded()) * 10
            return "\(roundedMeters) m"
        }
        let km = (meters / 1000 * 10).rounded() / 10
        return String(format: "%.1f km", km)
    }

    private func doctorDisplayName(_ doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Dottore" : full
    }

    private func doctorPhone(_ doctor: Doctor) -> String? {
        let phone = doctor.telefono?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (phone?.isEmpty == false) ? phone : nil
    }

    private func secretaryPhone(_ doctor: Doctor) -> String? {
        let phone = doctor.segreteria_telefono?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (phone?.isEmpty == false) ? phone : nil
    }

    private func doctorSearchSubtitle(_ doctor: Doctor) -> String? {
        if let phone = doctorPhone(doctor) {
            return phone
        }
        if let phone = secretaryPhone(doctor) {
            return "Segreteria: \(phone)"
        }
        return nil
    }

    private func doctorTodaySlotText(for doctor: Doctor) -> String? {
        let schedule = doctor.scheduleDTO
        let todayWeekday = doctorWeekday(for: Date())
        guard let daySchedule = schedule.days.first(where: { $0.day == todayWeekday }) else { return nil }
        return daySlotText(from: daySchedule)
    }

    private func daySlotText(from daySchedule: DoctorScheduleDTO.DaySchedule) -> String? {
        switch daySchedule.mode {
        case .closed:
            return nil
        case .continuous:
            let start = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let end = daySchedule.primary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !start.isEmpty, !end.isEmpty else { return nil }
            return "\(start)-\(end)"
        case .split:
            let firstStart = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let firstEnd = daySchedule.primary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondStart = daySchedule.secondary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondEnd = daySchedule.secondary.end.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !firstStart.isEmpty, !firstEnd.isEmpty, !secondStart.isEmpty, !secondEnd.isEmpty else { return nil }
            return "\(firstStart)-\(firstEnd) / \(secondStart)-\(secondEnd)"
        }
    }

    private func activeDoctorInterval(for doctor: Doctor, now: Date) -> (start: Date, end: Date)? {
        guard let todaySlot = doctorTodaySlotText(for: doctor) else { return nil }
        return OpeningHoursParser.activeInterval(from: todaySlot, now: now)
    }

    private func doctorWeekday(for date: Date) -> DoctorScheduleDTO.DaySchedule.Weekday {
        let weekday = Calendar.current.component(.weekday, from: date)
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }

    private func doctorNextOpeningLabel(for doctor: Doctor, now: Date) -> String? {
        let schedule = doctor.scheduleDTO
        let today = doctorWeekday(for: now)

        if let todaySchedule = schedule.days.first(where: { $0.day == today }),
           let time = nextOpeningTimeLabelToday(from: todaySchedule, now: now) {
            return "oggi \(time)"
        }

        for offset in 1...7 {
            let weekday = weekdayByAdding(offset, from: today)
            guard let daySchedule = schedule.days.first(where: { $0.day == weekday }),
                  let start = firstOpeningTimeLabel(from: daySchedule) else {
                continue
            }
            return "\(weekdayShortLabel(weekday)) \(start)"
        }

        return nil
    }

    private func nextOpeningTimeLabelToday(from daySchedule: DoctorScheduleDTO.DaySchedule, now: Date) -> String? {
        let nowSeconds = secondsSinceMidnight(now)

        switch daySchedule.mode {
        case .closed:
            return nil

        case .continuous:
            let start = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let startSeconds = parseTimeSeconds(start), nowSeconds < startSeconds else { return nil }
            return start

        case .split:
            let firstStart = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            let secondStart = daySchedule.secondary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstSeconds = parseTimeSeconds(firstStart), nowSeconds < firstSeconds {
                return firstStart
            }
            if let secondSeconds = parseTimeSeconds(secondStart), nowSeconds < secondSeconds {
                return secondStart
            }
            return nil
        }
    }

    private func firstOpeningTimeLabel(from daySchedule: DoctorScheduleDTO.DaySchedule) -> String? {
        switch daySchedule.mode {
        case .closed:
            return nil
        case .continuous:
            let start = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            return start.isEmpty ? nil : start
        case .split:
            let firstStart = daySchedule.primary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            if !firstStart.isEmpty { return firstStart }
            let secondStart = daySchedule.secondary.start.trimmingCharacters(in: .whitespacesAndNewlines)
            return secondStart.isEmpty ? nil : secondStart
        }
    }

    private func secondsSinceMidnight(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60
    }

    private func parseTimeSeconds(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 3600 + minute * 60
    }

    private func weekdayByAdding(_ days: Int, from start: DoctorScheduleDTO.DaySchedule.Weekday) -> DoctorScheduleDTO.DaySchedule.Weekday {
        let ordered = weekdayOrdered
        guard let index = ordered.firstIndex(of: start) else { return start }
        let nextIndex = (index + days) % ordered.count
        return ordered[nextIndex]
    }

    private var weekdayOrdered: [DoctorScheduleDTO.DaySchedule.Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }

    private func weekdayShortLabel(_ weekday: DoctorScheduleDTO.DaySchedule.Weekday) -> String {
        switch weekday {
        case .monday: return "lun"
        case .tuesday: return "mar"
        case .wednesday: return "mer"
        case .thursday: return "gio"
        case .friday: return "ven"
        case .saturday: return "sab"
        case .sunday: return "dom"
        }
    }

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }

    private func therapyPerson(_ therapy: Therapy) -> Person? {
        therapy.value(forKey: "person") as? Person
    }

    private func therapyMedicine(_ therapy: Therapy) -> Medicine? {
        therapy.value(forKey: "medicine") as? Medicine
    }

    private func therapyPackage(_ therapy: Therapy) -> Package? {
        therapy.value(forKey: "package") as? Package
    }

    private func therapyUUID(_ therapy: Therapy) -> UUID? {
        therapy.value(forKey: "id") as? UUID
    }

    private func therapyMedicineName(_ therapy: Therapy) -> String {
        camelCase(therapyMedicine(therapy)?.nome ?? "Terapia")
    }

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            if let therapyPackage = therapyPackage(therapy) {
                return therapyPackage
            }
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        return medicine.packages.first
    }

    private func loadCatalogMedicinesIfNeeded() {
        guard catalogMedicines.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = loadCatalogMedicines()
            DispatchQueue.main.async {
                catalogMedicines = loaded
            }
        }
    }

    private func loadCatalogMedicines() -> [CatalogSelection] {
        let bundle = Bundle.main
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

        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let entries = catalogEntries(from: object) else {
            return []
        }

        var results: [CatalogSelection] = []
        results.reserveCapacity(800)

        for entry in entries {
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
            )
            let principle = principleValues.isEmpty ? name : principleValues.joined(separator: ", ")

            let packages = entry["confezioni"] as? [[String: Any]] ?? []
            guard !packages.isEmpty else { continue }

            let dosageSource = (info?["descrizioneFormaDosaggio"] as? String)
                ?? (entry["descrizioneFormaDosaggio"] as? String)
            let dosage = parseCatalogDosage(from: dosageSource)

            for package in packages {
                let rawPackageLabel = (package["denominazionePackage"] as? String) ?? "Confezione"
                let packageLabel = rawPackageLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                let packageId = (package["idPackage"] as? String)
                    ?? (entry["id"] as? String)
                    ?? UUID().uuidString

                let selection = CatalogSelection(
                    id: packageId,
                    name: name,
                    principle: principle,
                    requiresPrescription: catalogRequiresPrescription(package),
                    packageLabel: packageLabel.isEmpty ? "Confezione" : packageLabel,
                    units: max(1, extractCatalogUnitCount(from: packageLabel)),
                    tipologia: packageLabel.isEmpty ? "Confezione" : packageLabel,
                    valore: dosage.value,
                    unita: dosage.unit,
                    volume: extractCatalogVolume(from: packageLabel)
                )
                results.append(selection)
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.packageLabel.localizedCaseInsensitiveCompare(rhs.packageLabel) == .orderedAscending
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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
            let key = normalizeCatalogText(trimmed)
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

    private func parseCatalogDosage(from description: String?) -> (value: Int32, unit: String) {
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

    private func extractCatalogUnitCount(from text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "\\d+") else { return 0 }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard let last = matches.last,
              let range = Range(last.range, in: text),
              let value = Int(text[range]) else {
            return 0
        }
        return value
    }

    private func extractCatalogVolume(from text: String) -> String {
        let uppercase = text.uppercased()
        guard let regex = try? NSRegularExpression(pattern: "\\d+\\s*(ML|L)") else { return "" }
        let range = NSRange(location: 0, length: (uppercase as NSString).length)
        guard let match = regex.firstMatch(in: uppercase, range: range),
              let matchRange = Range(match.range, in: uppercase) else {
            return ""
        }
        return uppercase[matchRange].lowercased()
    }

    private func normalizeCatalogText(_ text: String) -> String {
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

    private func camelCase(_ text: String) -> String {
        text
            .lowercased()
            .split(separator: " ")
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    private func catalogIdentityKey(name: String, principle: String) -> String {
        let normalizedName = normalizeCatalogText(name)
        let normalizedPrinciple = normalizeCatalogText(principle)
        if normalizedPrinciple.isEmpty {
            return normalizedName
        }
        return "\(normalizedName)|\(normalizedPrinciple)"
    }

    private func addRecent(kind: RecentKind, objectID: NSManagedObjectID?, title: String, subtitle: String?) {
        guard kind == .medicine || kind == .medicineEntry else { return }
        let objectURI = objectID?.uriRepresentation().absoluteString
        let item = RecentItem(
            id: UUID(),
            kind: kind,
            objectURI: objectURI,
            title: title,
            subtitle: subtitle,
            timestamp: Date()
        )

        var updated = recentItems
        updated.removeAll { existing in
            existing.kind == item.kind
            && existing.objectURI == item.objectURI
            && existing.title == item.title
        }
        updated.insert(item, at: 0)
        if updated.count > maxRecentItems {
            updated = Array(updated.prefix(maxRecentItems))
        }
        saveRecentItems(updated)
    }

    private func addRecentQuery(_ text: String) {
        guard !text.isEmpty else { return }
        addRecent(kind: .query, objectID: nil, title: text, subtitle: selectedScope.menuLabel)
    }

    private func saveRecentItems(_ items: [RecentItem]) {
        guard let data = try? JSONEncoder().encode(items),
              let raw = String(data: data, encoding: .utf8) else {
            return
        }
        recentItemsRaw = raw
    }

    private func searchNearbyPharmacies(query: String) {
        pharmacySearchTask?.cancel()
        guard !query.isEmpty, selectedScope == .all else {
            pharmacyResults = []
            return
        }
        pharmacySearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "farmacia \(query)"
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])
            if let location = locationVM.pinItem?.coordinate ?? CLLocationManager().location?.coordinate {
                request.region = MKCoordinateRegion(
                    center: location,
                    span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
                )
            }
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    pharmacyResults = response.mapItems
                        .prefix(5)
                        .map { PharmacyResult(mapItem: $0) }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    pharmacyResults = []
                }
            }
        }
    }

    private func openRecent(_ item: RecentItem) {
        switch item.kind {
        case .medicine:
            guard let medicine: Medicine = object(from: item.objectURI) else { return }
            openMedicine(medicine)

        case .medicineEntry:
            guard let entry: MedicinePackage = object(from: item.objectURI) else { return }
            openMedicineEntry(entry)

        case .therapy:
            guard let therapy: Therapy = object(from: item.objectURI) else { return }
            openTherapy(therapy)

        case .doctor:
            guard let doctor: Doctor = object(from: item.objectURI) else { return }
            openDoctor(doctor)

        case .person:
            guard let person: Person = object(from: item.objectURI) else { return }
            openPerson(person)

        case .query:
            query = item.title
            activeAction = nil
        }
    }

    private func object<T: NSManagedObject>(from uriString: String?) -> T? {
        guard let uriString,
              let uri = URL(string: uriString),
              let coordinator = managedObjectContext.persistentStoreCoordinator,
              let objectID = coordinator.managedObjectID(forURIRepresentation: uri),
              let object = try? managedObjectContext.existingObject(with: objectID) as? T else {
            return nil
        }
        return object
    }

    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let doseDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "EEE HH:mm"
        return formatter
    }()

    private static let logDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }()

    private var hourFormatter: DateFormatter {
        Self.hourFormatter
    }

    private var doseDateTimeFormatter: DateFormatter {
        Self.doseDateTimeFormatter
    }

    private var logDateTimeFormatter: DateFormatter {
        Self.logDateTimeFormatter
    }
}

private struct CatalogStockEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let medicineName: String
    let initialUnits: Int
    let initialDeadlineMonth: String
    let initialDeadlineYear: String
    let onSave: (_ targetUnits: Int, _ monthInput: String, _ yearInput: String) -> Bool

    @State private var targetUnits: Int
    @State private var monthInput: String
    @State private var yearInput: String

    init(
        medicineName: String,
        initialUnits: Int,
        initialDeadlineMonth: String,
        initialDeadlineYear: String,
        onSave: @escaping (_ targetUnits: Int, _ monthInput: String, _ yearInput: String) -> Bool
    ) {
        self.medicineName = medicineName
        self.initialUnits = initialUnits
        self.initialDeadlineMonth = initialDeadlineMonth
        self.initialDeadlineYear = initialDeadlineYear
        self.onSave = onSave
        _targetUnits = State(initialValue: initialUnits)
        _monthInput = State(initialValue: initialDeadlineMonth)
        _yearInput = State(initialValue: initialDeadlineYear)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Scorte")) {
                    Stepper(value: $targetUnits, in: 0...9999) {
                        Text("Unità disponibili: \(targetUnits)")
                    }
                }

                Section(header: Text("Scadenza")) {
                    HStack(spacing: 8) {
                        DeadlineMonthYearField(
                            month: $monthInput,
                            year: $yearInput
                        )
                        .frame(width: 110)

                        Spacer()
                    }
                    Text(deadlineSummaryText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(medicineName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        if onSave(targetUnits, monthInput, yearInput) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var deadlineSummaryText: String {
        guard let month = Int(monthInput),
              let year = Int(yearInput),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return "Scadenza non impostata"
        }
        return String(format: "Scadenza: %02d/%04d", month, year)
    }

}

private struct SearchFieldScannerAccessoryInstaller: UIViewControllerRepresentable {
    let shouldFocus: Bool
    let onDidFocus: () -> Void
    let onTapScanner: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDidFocus: onDidFocus, onTapScanner: onTapScanner)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onDidFocus = onDidFocus
        context.coordinator.onTapScanner = onTapScanner
        context.coordinator.configureSearchField(from: uiViewController, shouldFocus: shouldFocus)
    }

    final class Coordinator: NSObject {
        var onDidFocus: () -> Void
        var onTapScanner: () -> Void
        private weak var installedTextField: UISearchTextField?
        private var retryScheduled = false
        private var isAttemptingFocus = false
        private let scannerContainerTag = 9_241

        init(onDidFocus: @escaping () -> Void, onTapScanner: @escaping () -> Void) {
            self.onDidFocus = onDidFocus
            self.onTapScanner = onTapScanner
        }

        func configureSearchField(from viewController: UIViewController, shouldFocus: Bool) {
            guard let searchController = viewController.findSearchControllerForSearchTab() else {
                scheduleRetry(from: viewController, shouldFocus: shouldFocus)
                return
            }

            let textField = searchController.searchBar.searchTextField
            restoreSearchIcon(on: searchController.searchBar, textField: textField)

            installScannerButton(on: textField)
            if shouldFocus {
                requestFocus(from: viewController)
            }
        }

        private func restoreSearchIcon(on searchBar: UISearchBar, textField: UISearchTextField) {
            searchBar.setImage(UIImage(systemName: "magnifyingglass"), for: .search, state: .normal)
            if textField.leftView == nil {
                let imageView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
                imageView.tintColor = .secondaryLabel
                imageView.contentMode = .scaleAspectFit
                imageView.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
                textField.leftView = imageView
            }
            textField.leftViewMode = .always
        }

        private func installScannerButton(on textField: UISearchTextField) {
            if installedTextField === textField, textField.rightView?.tag == scannerContainerTag {
                return
            }

            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "vial.viewfinder"), for: .normal)
            button.tintColor = .systemBlue
            button.addTarget(self, action: #selector(didTapScanner), for: .touchUpInside)
            button.frame = CGRect(x: 0, y: 0, width: 26, height: 26)
            button.accessibilityLabel = "Scannerizza farmaco"

            let container = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 26))
            container.tag = scannerContainerTag
            button.center = CGPoint(x: container.bounds.midX, y: container.bounds.midY)
            button.autoresizingMask = [
                .flexibleLeftMargin,
                .flexibleRightMargin,
                .flexibleTopMargin,
                .flexibleBottomMargin
            ]
            container.addSubview(button)

            textField.rightView = container
            textField.rightViewMode = .always
            textField.clearButtonMode = .whileEditing
            installedTextField = textField
        }

        private func requestFocus(from viewController: UIViewController) {
            guard !isAttemptingFocus else { return }
            isAttemptingFocus = true
            attemptFocus(from: viewController, attemptsRemaining: 12)
        }

        private func attemptFocus(from viewController: UIViewController, attemptsRemaining: Int) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                guard let searchController = viewController.findSearchControllerForSearchTab() else {
                    return self.retryFocus(from: viewController, attemptsRemaining: attemptsRemaining - 1)
                }

                searchController.isActive = true
                let textField = searchController.searchBar.searchTextField
                if !textField.isFirstResponder {
                    textField.becomeFirstResponder()
                }

                if textField.isFirstResponder {
                    self.isAttemptingFocus = false
                    self.onDidFocus()
                } else {
                    self.retryFocus(from: viewController, attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }

        private func retryFocus(from viewController: UIViewController, attemptsRemaining: Int) {
            guard attemptsRemaining > 0 else {
                isAttemptingFocus = false
                return
            }
            attemptFocus(from: viewController, attemptsRemaining: attemptsRemaining)
        }

        private func scheduleRetry(from viewController: UIViewController, shouldFocus: Bool) {
            guard !retryScheduled else { return }
            retryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                self.retryScheduled = false
                self.configureSearchField(from: viewController, shouldFocus: shouldFocus)
            }
        }

        @objc
        private func didTapScanner() {
            onTapScanner()
        }
    }
}

private extension UIViewController {
    func findSearchControllerForSearchTab() -> UISearchController? {
        var current: UIViewController? = self
        while let controller = current {
            if let searchController = controller.navigationItem.searchController {
                return searchController
            }
            current = controller.parent
        }

        if let nav = navigationController,
           let searchController = nav.topViewController?.navigationItem.searchController {
            return searchController
        }

        if let root = view.window?.rootViewController {
            return root.findSearchControllerInChildrenForSearchTab()
        }

        return nil
    }

    func findSearchControllerInChildrenForSearchTab() -> UISearchController? {
        if let searchController = navigationItem.searchController {
            return searchController
        }
        for child in children {
            if let searchController = child.findSearchControllerInChildrenForSearchTab() {
                return searchController
            }
        }
        return nil
    }
}
