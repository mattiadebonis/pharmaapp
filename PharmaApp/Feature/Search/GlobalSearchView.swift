import SwiftUI
import CoreData
import MapKit
import UIKit

struct GlobalSearchView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.openURL) private var openURL

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    @FetchRequest(fetchRequest: Therapy.extractTherapies())
    private var therapies: FetchedResults<Therapy>

    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>

    @FetchRequest(fetchRequest: Person.extractPersons())
    private var persons: FetchedResults<Person>

    @StateObject private var locationVM = LocationSearchViewModel()
    @State private var query: String = ""
    @State private var selectedScope: SearchScope = .all
    @State private var activeShortcut: SearchShortcut?

    @State private var selectedMedicine: Medicine?
    @State private var selectedPackage: Package?
    @State private var selectedDoctor: Doctor?
    @State private var isDoctorDetailPresented = false
    @State private var selectedPerson: Person?
    @State private var isPersonDetailPresented = false

    @State private var isCatalogSearchPresented = false
    @State private var pendingCatalogSelection: CatalogSelection?
    @State private var catalogSelection: CatalogSelection?

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

    private enum SearchShortcut: String, CaseIterable, Identifiable {
        case lowStock
        case expiring
        case nextDoses
        case pharmacy
        case doctor
        case recent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .lowStock: return "Scorte basse"
            case .expiring: return "In scadenza"
            case .nextDoses: return "Prossime dosi"
            case .pharmacy: return "Farmacia"
            case .doctor: return "Dottore"
            case .recent: return "Recenti"
            }
        }
    }

    private enum RecentKind: String, Codable {
        case medicine
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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recurrenceManager: RecurrenceManager {
        RecurrenceManager(context: managedObjectContext)
    }

    private var option: Option? {
        Option.current(in: managedObjectContext)
    }

    private var recentItems: [RecentItem] {
        guard let data = recentItemsRaw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private var topRecentItems: [RecentItem] {
        Array(recentItems.prefix(maxRecentItems))
    }

    private var lowStockMedicines: [Medicine] {
        medicines
            .filter { medicine in
                medicine.isInEsaurimento(option: option!, recurrenceManager: recurrenceManager)
            }
            .sorted { lhs, rhs in
                let leftDays = stockCoverageDays(for: lhs) ?? Int.max
                let rightDays = stockCoverageDays(for: rhs) ?? Int.max
                if leftDays == rightDays {
                    return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
                }
                return leftDays < rightDays
            }
    }

    private var expiringMedicines: [Medicine] {
        medicines
            .filter { medicine in
                medicine.deadlineStatus == .expiringSoon || medicine.deadlineStatus == .expired
            }
            .sorted { lhs, rhs in
                let leftDays = daysUntilDeadline(for: lhs) ?? Int.max
                let rightDays = daysUntilDeadline(for: rhs) ?? Int.max
                if leftDays == rightDays {
                    return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
                }
                return leftDays < rightDays
            }
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

    private var filteredMedicines: [Medicine] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .medicines else { return [] }
        return medicines.filter { medicine in
            medicine.nome.localizedCaseInsensitiveContains(trimmedQuery)
            || medicine.principio_attivo.localizedCaseInsensitiveContains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
        }
    }

    private var filteredTherapies: [Therapy] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .therapies else { return [] }
        return therapies.filter { therapy in
            let medicineName = therapy.medicine.nome
            let principle = therapy.medicine.principio_attivo
            let personName = personDisplayName(for: therapy.person)
            return medicineName.localizedCaseInsensitiveContains(trimmedQuery)
            || principle.localizedCaseInsensitiveContains(trimmedQuery)
            || personName.localizedCaseInsensitiveContains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            lhs.medicine.nome.localizedCaseInsensitiveCompare(rhs.medicine.nome) == .orderedAscending
        }
    }

    private var filteredDoctors: [Doctor] {
        guard !trimmedQuery.isEmpty else { return [] }
        guard selectedScope == .all || selectedScope == .contacts else { return [] }
        return doctors.filter { doctor in
            (doctor.nome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
            || (doctor.cognome ?? "").localizedCaseInsensitiveContains(trimmedQuery)
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
        }
        .sorted { lhs, rhs in
            personDisplayName(for: lhs).localizedCaseInsensitiveCompare(personDisplayName(for: rhs)) == .orderedAscending
        }
    }

    private var hasSearchResults: Bool {
        !filteredMedicines.isEmpty || !filteredTherapies.isEmpty || !filteredDoctors.isEmpty || !filteredPersons.isEmpty
    }

    private var pharmacyPrimaryLine: String {
        if let today = locationVM.todayOpeningText?.trimmingCharacters(in: .whitespacesAndNewlines), !today.isEmpty {
            if let active = OpeningHoursParser.activeInterval(from: today, now: Date()) {
                return "Aperta fino alle \(OpeningHoursParser.timeString(from: active.end))"
            }
            if let next = OpeningHoursParser.nextInterval(from: today, after: Date()) {
                return "Prossima apertura: oggi \(OpeningHoursParser.timeString(from: next.start))"
            }
            return "Orari oggi \(today)"
        }
        if locationVM.isLikelyOpen == true {
            return "Aperta ora"
        }
        return "Orari non disponibili"
    }

    private var pharmacySecondaryLine: String {
        if let distance = pharmacyDistanceText() {
            return "a \(distance) · Indicazioni"
        }
        return "Indicazioni"
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

    private var doctorPrimaryLine: String {
        guard let doctor = preferredDoctor else {
            return "Aggiungi un dottore"
        }

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

    private var doctorSecondaryLine: String {
        if let doctor = preferredDoctor, doctorPhone(doctor) != nil {
            return "Chiama · Regole urgenze"
        }
        return "Regole urgenze"
    }

    var body: some View {
        List {
            if !trimmedQuery.isEmpty {
                searchResultsSections
            } else {
                utilitySection
                recentSection
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca un farmaco o una terapia...")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            guard !trimmedQuery.isEmpty else { return }
            addRecentQuery(trimmedQuery)
        }
        .background(
            SearchFieldScannerAccessoryInstaller {
                isCatalogSearchPresented = true
            }
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(SearchScope.allCases) { scope in
                        Button {
                            selectedScope = scope
                        } label: {
                            if selectedScope == scope {
                                Label(scope.menuLabel, systemImage: "checkmark")
                            } else {
                                Text(scope.menuLabel)
                            }
                        }
                    }
                } label: {
                    Image(systemName: selectedScope == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                }
            }
        }
        .onAppear {
            locationVM.ensureStarted()
        }
        .onChange(of: query) { value in
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                activeShortcut = nil
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { isPresented in
                if !isPresented {
                    selectedMedicine = nil
                    selectedPackage = nil
                }
            }
        )) {
            if let medicine = selectedMedicine {
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
        .sheet(isPresented: $isCatalogSearchPresented, onDismiss: {
            if let pending = pendingCatalogSelection {
                pendingCatalogSelection = nil
                DispatchQueue.main.async {
                    catalogSelection = pending
                }
            }
        }) {
            NavigationStack {
                CatalogSearchScreen { selection in
                    pendingCatalogSelection = selection
                    isCatalogSearchPresented = false
                }
            }
        }
        .sheet(item: $catalogSelection) { selection in
            MedicineWizardView(prefill: selection) {
                catalogSelection = nil
            }
            .environment(\.managedObjectContext, managedObjectContext)
            .presentationDetents([.fraction(0.5), .large])
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

    private var shortcutSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchShortcut.allCases) { shortcut in
                        Button {
                            handleShortcutTap(shortcut)
                        } label: {
                            Text(shortcut.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(activeShortcut == shortcut ? Color.white : Color.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(activeShortcut == shortcut ? Color.accentColor : Color.secondary.opacity(0.16))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var utilitySection: some View {
        Section {
            utilityRow(
                title: "Farmacia",
                primary: pharmacyPrimaryLine,
                secondary: pharmacySecondaryLine,
                action: openPharmacyDirections
            )

            utilityRow(
                title: preferredDoctor.map(doctorDisplayName) ?? "Dottore",
                primary: doctorPrimaryLine,
                secondary: doctorSecondaryLine,
                action: openPreferredDoctor
            )
        } header: {
            sectionHeader("Ora utile")
        }
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
            if suggestedActiveTherapies.isEmpty && suggestedTopMedicines.isEmpty && recentItems.isEmpty {
                emptyLine("Nessun suggerimento disponibile")
            } else {
                ForEach(suggestedActiveTherapies) { entry in
                    Button {
                        openMedicine(entry.medicine)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Terapia attiva · \(entry.medicine.nome)")
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
                            Text("Farmaco usato spesso · \(item.medicine.nome)")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.primary)
                            Text("\(item.intakeCount) registrazioni")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                ForEach(Array(recentItems.prefix(3))) { item in
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

        Section {
            quickActionRow(title: "Scorte basse") { applyQuickAction(.lowStock) }
            quickActionRow(title: "In scadenza") { applyQuickAction(.expiring) }
            quickActionRow(title: "Prossime dosi") { applyQuickAction(.nextDoses) }
        } header: {
            sectionHeader("Azioni rapide")
        }
    }

    @ViewBuilder
    private var searchResultsSections: some View {
        if hasSearchResults {
            if !filteredMedicines.isEmpty {
                Section {
                    ForEach(filteredMedicines) { medicine in
                        Button {
                            openMedicine(medicine)
                        } label: {
                            medicineRow(medicine)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    sectionHeader("Farmaci")
                }
            }

            if !filteredTherapies.isEmpty {
                Section {
                    ForEach(filteredTherapies, id: \.objectID) { therapy in
                        Button {
                            openTherapy(therapy)
                        } label: {
                            therapyRow(therapy)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    sectionHeader("Terapie")
                }
            }

            if !filteredDoctors.isEmpty || !filteredPersons.isEmpty {
                Section {
                    ForEach(filteredDoctors, id: \.objectID) { doctor in
                        Button {
                            openDoctor(doctor)
                        } label: {
                            doctorRow(doctor)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(filteredPersons, id: \.objectID) { person in
                        Button {
                            openPerson(person)
                        } label: {
                            personRow(person)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    sectionHeader("Contatti")
                }
            }
        } else {
            Section {
                emptyLine("Nessun risultato per \"\(trimmedQuery)\"")
            }
            .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private func shortcutResultsSection(for shortcut: SearchShortcut) -> some View {
        switch shortcut {
        case .lowStock:
            Section {
                if lowStockMedicines.isEmpty {
                    emptyLine("Nessun farmaco in scorte basse")
                } else {
                    ForEach(lowStockMedicines) { medicine in
                        Button {
                            openMedicine(medicine)
                        } label: {
                            medicineStatusRow(
                                medicine: medicine,
                                badge: "Scorte basse",
                                detail: stockCoverageDays(for: medicine).map { "\($0) giorni" } ?? "Da verificare"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader("Scorte basse")
            }

        case .expiring:
            Section {
                if expiringMedicines.isEmpty {
                    emptyLine("Nessun farmaco in scadenza")
                } else {
                    ForEach(expiringMedicines) { medicine in
                        Button {
                            openMedicine(medicine)
                        } label: {
                            let days = daysUntilDeadline(for: medicine) ?? Int.max
                            medicineStatusRow(
                                medicine: medicine,
                                badge: "In scadenza",
                                detail: days < 0 ? "Scaduto" : "\(days) giorni"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader("In scadenza")
            }

        case .nextDoses:
            Section {
                if nextDoseEntries.isEmpty {
                    emptyLine("Nessuna prossima dose")
                } else {
                    ForEach(nextDoseEntries.prefix(10)) { entry in
                        Button {
                            openMedicine(entry.medicine)
                        } label: {
                            medicineStatusRow(
                                medicine: entry.medicine,
                                badge: Calendar.current.isDateInToday(entry.nextDose) ? "Oggi" : "Prossima",
                                detail: doseDateTimeFormatter.string(from: entry.nextDose)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                sectionHeader("Prossime dosi")
            }

        case .recent:
            recentSection

        case .pharmacy, .doctor:
            EmptyView()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    private func utilityRow(title: String, primary: String, secondary: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(primary)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                Text(secondary)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func watchRow(_ entry: WatchEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.medicine.nome)
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

    private func recentRow(_ item: RecentItem) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medicineRow(_ medicine: Medicine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(medicine.nome)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.primary)
            if !medicine.principio_attivo.isEmpty {
                Text(medicine.principio_attivo)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func therapyRow(_ therapy: Therapy) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(therapy.medicine.nome)
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
                Text(personDisplayName(for: therapy.person))
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

            if let phone = doctorPhone(doctor) {
                Text(phone)
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

    private func medicineStatusRow(medicine: Medicine, badge: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(medicine.nome)
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

    private func handleShortcutTap(_ shortcut: SearchShortcut) {
        switch shortcut {
        case .pharmacy:
            activeShortcut = nil
            query = ""
            openPharmacyDirections()

        case .doctor:
            activeShortcut = nil
            query = ""
            openPreferredDoctor()

        default:
            query = ""
            if activeShortcut == shortcut {
                activeShortcut = nil
            } else {
                activeShortcut = shortcut
            }
        }
    }

    private func applyQuickAction(_ shortcut: SearchShortcut) {
        query = ""
        activeShortcut = shortcut
    }

    private func openMedicine(_ medicine: Medicine, package: Package? = nil) {
        selectedPackage = package
        selectedMedicine = medicine
        addRecent(
            kind: .medicine,
            objectID: medicine.objectID,
            title: medicine.nome,
            subtitle: medicine.principio_attivo.isEmpty ? nil : medicine.principio_attivo
        )
    }

    private func openTherapy(_ therapy: Therapy) {
        selectedPackage = therapy.package
        selectedMedicine = therapy.medicine
        addRecent(
            kind: .therapy,
            objectID: therapy.objectID,
            title: therapy.medicine.nome,
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

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        return medicine.packages.first
    }

    private func addRecent(kind: RecentKind, objectID: NSManagedObjectID?, title: String, subtitle: String?) {
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

    private func openRecent(_ item: RecentItem) {
        switch item.kind {
        case .medicine:
            guard let medicine: Medicine = object(from: item.objectURI) else { return }
            openMedicine(medicine)

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
            activeShortcut = nil
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

    private var hourFormatter: DateFormatter {
        Self.hourFormatter
    }

    private var doseDateTimeFormatter: DateFormatter {
        Self.doseDateTimeFormatter
    }
}

private struct SearchFieldScannerAccessoryInstaller: UIViewControllerRepresentable {
    let onTapScanner: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTapScanner: onTapScanner)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.onTapScanner = onTapScanner
        context.coordinator.installScannerButton(from: uiViewController)
    }

    final class Coordinator: NSObject {
        var onTapScanner: () -> Void
        private weak var installedTextField: UISearchTextField?
        private var retryScheduled = false
        private let scannerContainerTag = 9_241

        init(onTapScanner: @escaping () -> Void) {
            self.onTapScanner = onTapScanner
        }

        func installScannerButton(from viewController: UIViewController) {
            guard let searchController = viewController.findSearchControllerForSearchTab() else {
                scheduleRetry(from: viewController)
                return
            }

            let textField = searchController.searchBar.searchTextField
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

        private func scheduleRetry(from viewController: UIViewController) {
            guard !retryScheduled else { return }
            retryScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak viewController] in
                guard let self, let viewController else { return }
                self.retryScheduled = false
                self.installScannerButton(from: viewController)
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
