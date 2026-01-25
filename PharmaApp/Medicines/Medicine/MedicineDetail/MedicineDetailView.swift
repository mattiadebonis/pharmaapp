import SwiftUI
import CoreData
import UIKit
import MessageUI

struct MedicineDetailView: View {

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = MedicineFormViewModel(
        context: PersistenceController.shared.container.viewContext
    )
	    @StateObject private var actionsViewModel = MedicineRowViewModel(
	        managedObjectContext: PersistenceController.shared.container.viewContext
	    )
	    @State private var emailDetent: PresentationDetent = .fraction(0.55)
	    @State private var customThresholdValue: Int = 7
	    @State private var intakeConfirmationEnabled: Bool = false
    @State private var selectedDoctorID: NSManagedObjectID? = nil
    @State private var therapySheet: TherapySheetState?
	    @State private var showThresholdSheet = false
	    @State private var showIntakeConfirmationSheet = false
	    @State private var showDoctorSheet = false
    @State private var deadlineMonthInput: String = ""
    @State private var deadlineYearInput: String = ""
    
    @ObservedObject var medicine: Medicine
    let package: Package
    let medicinePackage: MedicinePackage?
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest private var therapies: FetchedResults<Therapy>
    @FetchRequest private var intakeLogs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) private var allMedicines: FetchedResults<Medicine>
    
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    @State private var showEmailSheet = false
    @State private var showLogsSheet = false
    
    private let stockDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Errore salvataggio: \(error)")
        }
    }
    
    init(medicine: Medicine, package: Package, medicinePackage: MedicinePackage? = nil) {
        _medicine = ObservedObject(wrappedValue: medicine)
        self.package = package
        self.medicinePackage = medicinePackage
        let predicate: NSPredicate
        if let medicinePackage {
            predicate = NSPredicate(format: "medicinePackage == %@", medicinePackage)
        } else {
            predicate = NSPredicate(format: "medicine == %@", medicine)
        }
        _therapies = FetchRequest(
            entity: Therapy.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Therapy.start_date, ascending: true)],
            predicate: predicate
        )
        _intakeLogs = FetchRequest(fetchRequest: Log.extractIntakeLogsFiltered(medicine: medicine))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                stockManagementSection
                therapiesInlineSection
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(medicine.nome.isEmpty ? "Dettagli" : medicine.nome)
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if medicine.obbligo_ricetta {
                            Button {
                                showDoctorSheet = true
                            } label: {
                                Label("Medico prescrittore", systemImage: "stethoscope")
                            }
                        }
                        Button {
                            showLogsSheet = true
                        } label: {
                            Label("Visualizza log", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            showThresholdSheet = true
                        } label: {
                            Label("Soglia scorte", systemImage: "bell.badge")
                        }
                        Button {
                            showIntakeConfirmationSheet = true
                        } label: {
                            Label("Conferma assunzione", systemImage: "checkmark.circle")
                        }
                        Button {
                            deletePackage()
                        } label: {
                            Label("Rimuovi confezione", systemImage: "minus.circle")
                                .foregroundStyle(.orange)
                        }
                        Button(role: .destructive) {
                            deleteMedicine()
                        } label: {
                            Label("Elimina", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionButtonsView
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Color(.systemGroupedBackground))
        }
        .onAppear {
            let current = Int(medicine.custom_stock_threshold)
            customThresholdValue = current > 0 ? current : 7
            loadRulesState()
            selectedDoctorID = medicine.prescribingDoctor?.objectID
            syncDeadlineInputs()
        }
        .sheet(isPresented: $showThresholdSheet) {
            ThresholdSheet(
                value: $customThresholdValue,
                onChange: { newValue in
                    medicine.custom_stock_threshold = Int32(newValue)
                    saveContext()
                }
            )
        }
        .sheet(isPresented: $showIntakeConfirmationSheet) {
            IntakeConfirmationSheet(
                isEnabled: $intakeConfirmationEnabled,
                onPersist: persistIntakeConfirmation
            )
        }
	        .sheet(isPresented: $showDoctorSheet) {
	            DoctorSheet(
	                selectedDoctorID: $selectedDoctorID,
	                doctors: doctors,
                onChange: { newID in
                    selectedDoctorID = newID
                    medicine.prescribingDoctor = doctors.first(where: { $0.objectID == newID })
                    saveContext()
                }
            )
        }
        .sheet(isPresented: $showEmailSheet) {
            EmailRequestSheet(
                doctorName: doctorDisplayName,
                primaryMedicine: medicine,
                emailAddress: doctorEmail,
                phoneInternational: doctorPhoneInternational,
                baseMedicines: suggestionMedicines,
                emailBuilder: { meds in emailBody(for: meds) },
                onCopy: { meds in
                    UIPasteboard.general.string = emailBody(for: meds)
                    meds.forEach { med in
                        actionsViewModel.addNewPrescriptionRequest(for: med)
                        actionsViewModel.addNewPrescription(for: med)
                    }
                },
                onSend: { meds in
                    meds.forEach { med in
                        actionsViewModel.addNewPrescriptionRequest(for: med)
                        actionsViewModel.addNewPrescription(for: med)
                    }
                }
            )
            .onAppear { emailDetent = .fraction(0.55) }
            .presentationDetents([.fraction(0.55), .large], selection: $emailDetent)
        }
        .sheet(isPresented: $showLogsSheet) {
            NavigationStack {
                MedicineLogsView(medicine: medicine)
                    .navigationTitle("Log di \(medicine.nome)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showLogsSheet = false }
                        }
                    }
            }
        }
        .sheet(item: $therapySheet) { state in
            TherapyFormView(
                medicine: medicine,
                package: package,
                context: context,
                medicinePackage: medicinePackage,
                editingTherapy: state.therapy
            )
            .presentationDetents([.large])
        }
        .onChange(of: selectedDoctorID) { newValue in
            if let newValue, let doc = doctors.first(where: { $0.objectID == newValue }) {
                medicine.prescribingDoctor = doc
                saveContext()
            } else {
                medicine.prescribingDoctor = nil
                saveContext()
            }
        }
    }
    
    private func openTherapyForm(for therapy: Therapy?) {
        if let therapy {
            therapySheet = .edit(therapy)
        } else {
            therapySheet = .create()
        }
    }

    private struct TherapySheetState: Identifiable {
        let id: AnyHashable
        let therapy: Therapy?

        static func edit(_ therapy: Therapy) -> TherapySheetState {
            TherapySheetState(id: therapy.objectID, therapy: therapy)
        }

        static func create() -> TherapySheetState {
            TherapySheetState(id: UUID(), therapy: nil)
        }
    }
    
    private struct PrimaryAction {
        let label: String
        let icon: String
        let color: Color
    }
    
    // MARK: - Computed properties
    private var currentOption: Option? {
        options.first
    }
    
    private var primaryAction: PrimaryAction? {
        if let option = currentOption,
           medicine.obbligo_ricetta,
           medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager) {
            if medicine.hasPendingNewPrescription() {
                return PrimaryAction(label: "Compra", icon: "cart.fill", color: .blue)
            } else {
                return PrimaryAction(label: "Richiedi ricetta", icon: "envelope", color: .orange)
            }
        }
        return PrimaryAction(label: "Registra acquisto", icon: "cart.fill", color: .blue)
    }

    private var detailAccentColor: Color {
        if totalLeftover <= 0 {
            return .red
        }
        return medicine.obbligo_ricetta ? .blue : .green
    }

    private var packageSummary: String? {
        formattedPackageLabel(package)
    }
    
    private var activeIngredient: String? {
        let active = medicine.principio_attivo.trimmingCharacters(in: .whitespacesAndNewlines)
        return active.isEmpty ? nil : active
    }

    private var coverageSummaryText: String {
        guard let date = estimatedDepletionDate else { return "N/D" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 0 {
            return "Oggi"
        }
        return "\(days)g"
    }
    
    private var therapyCount: Int {
        therapies.count
    }

    private var deadlineSummaryText: String {
        medicine.deadlineLabel ?? "Non impostata"
    }
    
    private var therapySummarySubtitle: String {
        guard let therapy = therapies.first else {
            return "Nessuna terapia attiva"
        }
        let rruleString = therapy.rrule ?? ""
        let description = recurrenceManager
            .describeRecurrence(rule: recurrenceManager.parseRecurrenceString(rruleString))
            .capitalized
        let timeString = earliestDoseTime(for: therapy)
        let subtitleParts = [description, timeString].compactMap { $0 }
        return subtitleParts.isEmpty ? "" : subtitleParts.joined(separator: " • ")
    }
    
    private var stockDisplayValue: String {
        let units = totalLeftover
        return units == 1 ? "1 unità" : "\(units) unità"
    }
    
    private var stockEstimateSubtitle: String? {
        guard let date = estimatedDepletionDate else { return nil }
        return "Stimato fino al \(stockDateFormatter.string(from: date))"
    }

    private var packageUnitSize: Int {
        max(1, Int(package.numero))
    }

    private var stockUnitsForSelectedPackage: Int {
        guard let context = medicine.managedObjectContext ?? package.managedObjectContext else { return 0 }
        let stockService = StockService(context: context)
        return max(0, stockService.units(for: package))
    }

    private var stockUnitsText: String {
        stockUnitsForSelectedPackage == 1 ? "1 unità" : "\(stockUnitsForSelectedPackage) unità"
    }

    private var stockPackagesForSelectedPackage: Int {
        let units = stockUnitsForSelectedPackage
        guard units > 0 else { return 0 }
        return Int(ceil(Double(units) / Double(packageUnitSize)))
    }

    private var stockPackagesText: String {
        stockPackagesForSelectedPackage == 1 ? "1 confezione" : "\(stockPackagesForSelectedPackage) confezioni"
    }

    private var estimatedCoverageDaysForSelectedPackage: Double? {
        let relevant = therapies.filter { $0.package.objectID == package.objectID }
        guard !relevant.isEmpty else { return nil }
        var totalDaily: Double = 0
        for therapy in relevant {
            totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }
        guard totalDaily > 0 else { return nil }
        return Double(stockUnitsForSelectedPackage) / totalDaily
    }

    private var stockEstimateInlineText: String? {
        guard let coverage = estimatedCoverageDaysForSelectedPackage else { return nil }
        if coverage < 1 {
            return "<1g"
        }
        let days = Int(coverage.rounded(.down))
        return days == 1 ? "~1g" : "~\(days)g"
    }

    private var currentTherapiesSet: Set<Therapy> {
        Set(therapies)
    }

    private func recurrenceDescription(for therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let description = recurrenceManager.describeRecurrence(rule: rule)
        return description.capitalized
    }
    
    /// Builds the same style of text as the "Descrizione terapia" in TherapyForm: "Per [person] [dose] [frequency] [times], [confirmation]"
    private func therapyDescriptionText(for therapy: Therapy) -> String {
        var parts: [String] = []
        if let personName = personDisplayName(for: therapy.person), !personName.isEmpty {
            parts.append("Per \(personName)")
        }
        parts.append(doseDisplayText(for: therapy))
        parts.append(frequencySummaryText(for: therapy))
        if let timesText = timesDescriptionText(for: therapy) {
            parts.append(timesText)
        }
        
        return "\(parts.joined(separator: " "))"
    }
    
    private func personDisplayName(for person: Person?) -> String? {
        guard let person else { return nil }
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? nil : first
    }
    
    private func doseDisplayText(for therapy: Therapy) -> String {
        let pkg = therapy.package
        let tipologia = (pkg.tipologia).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unit: String = tipologia.contains("capsul") ? "capsula" : "compressa"
        return "1 \(unit)"
    }
    
    private func frequencySummaryText(for therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        if rule.freq == "DAILY" {
            if rule.interval <= 1 { return "Ogni giorno" }
            return "Ogni \(rule.interval) giorni"
        }
        if !rule.byDay.isEmpty {
            let names = rule.byDay.map { dayCodeToItalian($0) }
            return names.joined(separator: ", ")
        }
        return "Ogni giorno"
    }
    
    private func dayCodeToItalian(_ code: String) -> String {
        switch code {
        case "MO": return "Lunedì"
        case "TU": return "Martedì"
        case "WE": return "Mercoledì"
        case "TH": return "Giovedì"
        case "FR": return "Venerdì"
        case "SA": return "Sabato"
        case "SU": return "Domenica"
        default: return code
        }
    }
    
    private func timesDescriptionText(for therapy: Therapy) -> String? {
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return doseSet
            .sorted { $0.time < $1.time }
            .map { "alle \(formatter.string(from: $0.time))" }
            .joined(separator: ", ")
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

    private func allowedEvents(on day: Date, for therapy: Therapy) -> Int {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? day
        let perDay = max(1, therapy.doses?.count ?? 0)
        return recurrenceManager.allowedEvents(on: day, rule: rule, startDate: start, dosesPerDay: perDay)
    }

    private func occursToday(_ therapy: Therapy, now: Date) -> Bool {
        return allowedEvents(on: now, for: therapy) > 0
    }

    private func scheduledTimesToday(for therapy: Therapy, now: Date) -> [Date] {
        let today = Calendar.current.startOfDay(for: now)
        let allowed = allowedEvents(on: today, for: therapy)
        guard allowed > 0 else { return [] }
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return [] }
        let sortedDoses = doseSet.sorted { $0.time < $1.time }
        let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
        return limitedDoses.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }
    }

    private func intakeCountToday(for therapy: Therapy, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = intakeLogs.filter { calendar.isDate($0.timestamp, inSameDayAs: now) }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        if therapies.count == 1 { return unassigned.count }
        return unassigned.filter { $0.package == therapy.package }.count
    }
    
    private func nextDose(for therapy: Therapy) -> Date? {
        let now = Date()
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let startDate = therapy.start_date ?? now

        let calendar = Calendar.current
        let timesToday = scheduledTimesToday(for: therapy, now: now)
        if calendar.isDateInToday(now), !timesToday.isEmpty {
            let takenCount = intakeCountToday(for: therapy, now: now)
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
    
    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        } else if calendar.isDateInTomorrow(date) {
            return "Domani"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private var estimatedDepletionDate: Date? {
        guard !currentTherapiesSet.isEmpty else { return nil }
        let usageData = currentTherapiesSet.reduce(into: (left: 0.0, daily: 0.0)) { result, therapy in
            result.left += Double(therapy.leftover())
            result.daily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }
        guard usageData.daily > 0, usageData.left > 0 else { return nil }
        let days = usageData.left / usageData.daily
        return Calendar.current.date(byAdding: .day, value: Int(days.rounded(.down)), to: Date())
    }
    
    private var totalLeftover: Int {
        if !therapies.isEmpty {
            return therapies.reduce(0) { total, therapy in
                total + Int(therapy.leftover())
            }
        }
        return StockService(context: context).units(for: package)
    }
    
    private var leftoverColor: Color {
        totalLeftover <= 0 ? .red : .primary
    }
    
    private var assignedDoctor: Doctor? {
        medicine.prescribingDoctor
    }
    
    private var assignedDoctorEmail: String? {
        guard let email = assignedDoctor?.mail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return nil
        }
        return email
    }

    private var assignedDoctorPhoneInternational: String? {
        guard let raw = assignedDoctor?.telefono?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return CommunicationService.normalizeInternationalPhone(raw)
    }

    private var assignedDoctorName: String? {
        doctorFullName(assignedDoctor)
    }
    
    private var doctorWithEmail: Doctor? {
        if let doctor = assignedDoctor, let email = doctor.mail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return doctor
        }
        return doctors.first(where: { !($0.mail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    
    private var doctorEmail: String? {
        doctorWithEmail?.mail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var doctorPhoneInternational: String? {
        if let assigned = assignedDoctorPhoneInternational {
            return assigned
        }
        if let raw = doctorWithEmail?.telefono?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let normalized = CommunicationService.normalizeInternationalPhone(raw) {
            return normalized
        }
        if let raw = doctors.first(where: { !($0.telefono ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .telefono?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return CommunicationService.normalizeInternationalPhone(raw)
        }
        return nil
    }
    
    private var doctorDisplayName: String {
        if let assignedName = assignedDoctorName, !assignedName.isEmpty {
            return assignedName
        }
        let first = doctorWithEmail?.nome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? "Dottore" : first
    }
    
    private var suggestionMedicines: [Medicine] {
        let rec = recurrenceManager
        let filtered = allMedicines.filter { med in
            med.objectID != medicine.objectID && shouldIncludeInSuggestions(med)
        }
        let scored = filtered.map { med -> (Medicine, Double) in
            let coverage = coverageDays(for: med, recurrenceManager: rec) ?? Double.greatestFiniteMagnitude
            return (med, coverage)
        }
        .sorted { $0.1 < $1.1 }
        return Array(scored.prefix(6).map { $0.0 })
    }
    
    private func earliestDoseTime(for therapy: Therapy) -> String? {
        guard let doses = therapy.doses as? Set<Dose>,
              let earliest = doses.sorted(by: { $0.time < $1.time }).first else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: earliest.time)
    }
    
    private func handlePrimaryAction(_ action: PrimaryAction) {
        if action.label == "Richiedi ricetta" {
            showEmailSheet = true
        } else {
            viewModel.addPurchase(for: medicine, for: package)
        }
    }
    
    private func deletePackage() {
        let relatedLogs = (medicine.logs ?? []).filter { $0.package?.objectID == package.objectID }
        let relatedTherapies = package.therapies ?? []
        let relatedStocks = package.stocks ?? []
        let relatedEntries = (package.medicinePackages ?? []).filter { $0.medicine == medicine }

        for log in relatedLogs {
            context.delete(log)
        }

        for therapy in relatedTherapies {
            if let doses = therapy.doses as? Set<Dose> {
                for dose in doses {
                    context.delete(dose)
                }
            }
            if let logs = therapy.logs {
                for log in logs {
                    context.delete(log)
                }
            }
            context.delete(therapy)
        }

        for stock in relatedStocks {
            context.delete(stock)
        }

        for entry in relatedEntries {
            context.delete(entry)
        }

        context.delete(package)

        do {
            try context.save()
            dismiss()
        } catch {
            print("Errore eliminazione confezione: \(error.localizedDescription)")
        }
    }
    
    private func deleteMedicine() {
        // Core Data has required relationships (e.g., Log.medicine, Therapy.medicine, Package.medicine),
        // so we must delete dependents first to avoid validation errors.
        let relatedLogs = (medicine.logs as? Set<Log>) ?? []
        let relatedTherapies = (medicine.therapies as? Set<Therapy>) ?? []
        let relatedPackages = medicine.packages
        let relatedEntries = medicine.medicinePackages ?? []

        for log in relatedLogs {
            context.delete(log)
        }
        for therapy in relatedTherapies {
            if let doses = therapy.doses as? Set<Dose> {
                for dose in doses {
                    context.delete(dose)
                }
            }
            context.delete(therapy)
        }
        for package in relatedPackages {
            context.delete(package)
        }

        for entry in relatedEntries {
            context.delete(entry)
        }

        context.delete(medicine)
        do {
            try context.save()
            dismiss()
        } catch {
            print("Errore eliminazione medicina: \(error.localizedDescription)")
        }
    }
    
    private func emailBody(for meds: [Medicine]) -> String {
        let list = meds.map { "- \($0.nome)" }.joined(separator: "\n")
        return """
        Gentile \(doctorDisplayName),

        avrei bisogno della ricetta per:
        \(list)

        Potresti inviarla appena possibile? Grazie!

        """
    }
    
    private func sendEmailBody(for meds: [Medicine]) {
        guard let email = doctorEmail else { return }
        let subjectList = meds.map { $0.nome }.joined(separator: ", ")
        let subject = "Richiesta ricetta \(subjectList)"
        let body = emailBody(for: meds)
        let components: [String: String] = [
            "subject": subject,
            "body": body
        ]
        let query = components.compactMap { key, value in
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).map { "\(key)=\($0)" }
        }.joined(separator: "&")
        if let url = URL(string: "mailto:\(email)?\(query)") {
            openURL(url)
        }
    }
    
    private func doctorFullName(_ doctor: Doctor?) -> String {
        guard let doctor else { return "" }
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first
    }
    
    private func coverageDays(for med: Medicine, recurrenceManager: RecurrenceManager) -> Double? {
        if let therapies = med.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            guard totalDaily > 0 else { return nil }
            return totalLeft / totalDaily
        } else if let remaining = med.remainingUnitsWithoutTherapy(), remaining > 0 {
            return Double(remaining)
        }
        return nil
    }
    
    private func shouldIncludeInSuggestions(_ med: Medicine) -> Bool {
        guard med.obbligo_ricetta else { return false }
        let threshold = Int(currentOption?.day_threeshold_stocks_alarm ?? 7)
        if let therapies = med.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
            }
            if totalLeft <= 0 { return true }
            guard totalDaily > 0 else { return false }
            return (totalLeft / totalDaily) < Double(threshold)
        }
        if let remaining = med.remainingUnitsWithoutTherapy() {
            return remaining <= 0 || remaining < threshold
        }
        return false
    }
}

// MARK: - Decorative sections
extension MedicineDetailView {
    private var stockManagementSection: some View {
        Section {
            Stepper(
                value: Binding(
                    get: { stockUnitsForSelectedPackage },
                    set: { viewModel.setStockUnits(medicine: medicine, package: package, targetUnits: $0) }
                ),
                in: 0...9999
            ) {
                HStack(spacing: 8) {
                    Text(stockUnitsText)
                    Spacer()
                    if let estimate = stockEstimateInlineText {
                        Text(estimate)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Scadenza")
                        .foregroundStyle(.secondary)
                    TextField("MM", text: Binding(
                        get: { deadlineMonthInput },
                        set: { newValue in
                            let sanitized = sanitizeMonthInput(newValue)
                            if sanitized != deadlineMonthInput {
                                deadlineMonthInput = sanitized
                            }
                            updateDeadlineFromInputs()
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)

                    Text("/")
                        .foregroundStyle(.secondary)

                    TextField("YYYY", text: Binding(
                        get: { deadlineYearInput },
                        set: { newValue in
                            let sanitized = sanitizeYearInput(newValue)
                            if sanitized != deadlineYearInput {
                                deadlineYearInput = sanitized
                            }
                            updateDeadlineFromInputs()
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 70)

                    Spacer()
                }
            }
        } header: {
            Text("Scorte e prescrizione")
                .font(.body.weight(.semibold))
        }
        .textCase(nil)
    }

    private var actionButtonsView: some View {
        VStack(spacing: 12) {
            if let action = primaryAction, action.label == "Richiedi ricetta" {
                Button {
                    handlePrimaryAction(action)
                } label: {
                    Label(action.label, systemImage: action.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(action.color)
            }

            Button {
                actionsViewModel.addIntake(for: medicine, package: package)
            } label: {
                Label("Assunto", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CapsuleActionButtonStyle(fill: .green, textColor: .white))

            Button {
                viewModel.addPurchase(for: medicine, for: package)
            } label: {
                Label("Acquistato", systemImage: "cart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CapsuleActionButtonStyle(fill: .blue, textColor: .white))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var therapiesInlineSection: some View {
        Section {
            if therapies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nessuna terapia aggiunta.")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } else {
                ForEach(therapies, id: \.objectID) { therapy in
                    Button {
                        openTherapyForm(for: therapy)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(therapyDescriptionText(for: therapy))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let next = nextDose(for: therapy) {
                                Text("Prossima: \(formattedDate(next))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("Terapie")
                    .font(.body.weight(.semibold))
                Spacer()
                Button {
                    openTherapyForm(for: nil)
                } label: {
                    Label("",systemImage: "plus")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Aggiungi terapia")
            }
        }
        .textCase(nil)
    }

    private func loadRulesState() {
        let fallbackConfirmation = therapies.contains(where: { $0.manual_intake_registration })
        let resolvedConfirmation = medicine.manual_intake_registration || fallbackConfirmation
        intakeConfirmationEnabled = resolvedConfirmation
        let needsConfirmationSync = medicine.manual_intake_registration != resolvedConfirmation ||
            therapies.contains(where: { $0.manual_intake_registration != resolvedConfirmation })
        if needsConfirmationSync {
            medicine.manual_intake_registration = resolvedConfirmation
            persistIntakeConfirmation()
        }
    }
    
    private func persistIntakeConfirmation() {
        medicine.manual_intake_registration = intakeConfirmationEnabled
        for therapy in therapies {
            therapy.manual_intake_registration = intakeConfirmationEnabled
        }
        saveContext()
    }

    private func syncDeadlineInputs() {
        if let info = medicine.deadlineMonthYear {
            deadlineMonthInput = String(format: "%02d", info.month)
            deadlineYearInput = String(info.year)
        } else {
            deadlineMonthInput = ""
            deadlineYearInput = ""
        }
    }

    private func sanitizeMonthInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(2))
    }

    private func sanitizeYearInput(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        return String(digits.prefix(4))
    }

    private func clearDeadline() {
        deadlineMonthInput = ""
        deadlineYearInput = ""
        medicine.updateDeadline(month: nil, year: nil)
        saveContext()
    }

    private func updateDeadlineFromInputs() {
        let monthText = deadlineMonthInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearText = deadlineYearInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if monthText.isEmpty && yearText.isEmpty {
            clearDeadline()
            return
        }

        guard let month = Int(monthText),
              let year = Int(yearText),
              (1...12).contains(month),
              (2000...2100).contains(year) else {
            return
        }

        medicine.updateDeadline(month: month, year: year)
        saveContext()
    }

    private struct IntakeConfirmationSheet: View {
        @Binding var isEnabled: Bool
        let onPersist: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section(
                        footer: Text("Valido per tutte le terapie di questo farmaco.")
                    ) {
                        Toggle(isOn: $isEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chiedi conferma assunzione")
                                Text("Quando ricevi il promemoria, conferma manualmente l'assunzione.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: isEnabled) { _ in
                            onPersist()
                        }
                    }
                }
                .navigationTitle("Conferma assunzione")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { dismiss() }
                    }
                }
            }
            .presentationDetents([.fraction(0.3), .medium])
        }
    }

    private struct ThresholdSheet: View {
        @Binding var value: Int
        let onChange: (Int) -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Stepper(value: $value, in: 1...60) {
                            Text("Avvisami quando restano \(value) giorni")
                        }
                        .onChange(of: value, perform: onChange)
                    }
                }
                .navigationTitle("Soglia scorte")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { dismiss() }
                    }
                }
            }
            .presentationDetents([.fraction(0.3), .medium])
        }
    }
    
    private struct DoctorSheet: View {
        @Binding var selectedDoctorID: NSManagedObjectID?
        let doctors: FetchedResults<Doctor>
        let onChange: (NSManagedObjectID?) -> Void
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Picker("Medico", selection: $selectedDoctorID) {
                            Text("Nessuno").tag(NSManagedObjectID?.none)
                            ForEach(doctors, id: \.objectID) { doc in
                                Text(doctorFullName(doc)).tag(Optional(doc.objectID))
                            }
                        }
                        .onChange(of: selectedDoctorID, perform: onChange)
                    }
                }
                .navigationTitle("Medico")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Chiudi") { dismiss() }
                    }
                }
            }
            .presentationDetents([.fraction(0.3), .medium])
        }
        
        private func doctorFullName(_ doctor: Doctor) -> String {
            let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return first.isEmpty ? "Medico" : first
        }
    }
    
}
// MARK: - UI helpers
extension MedicineDetailView {
}

private struct EmailRequestSheet: View {
    let doctorName: String
    let primaryMedicine: Medicine
    let emailAddress: String?
    let phoneInternational: String?
    let baseMedicines: [Medicine]
    let emailBuilder: ([Medicine]) -> String
    let onCopy: ([Medicine]) -> Void
    let onSend: ([Medicine]) -> Void
    
    @State private var selectedMedicines: Set<NSManagedObjectID>
    @State private var mailComposeData: MailComposeData?
    @State private var showMailFallbackAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    init(doctorName: String,
         primaryMedicine: Medicine,
         emailAddress: String?,
         phoneInternational: String?,
         baseMedicines: [Medicine],
         emailBuilder: @escaping ([Medicine]) -> String,
         onCopy: @escaping ([Medicine]) -> Void,
         onSend: @escaping ([Medicine]) -> Void) {
        self.doctorName = doctorName
        self.primaryMedicine = primaryMedicine
        self.emailAddress = emailAddress
        self.phoneInternational = phoneInternational
        self.baseMedicines = baseMedicines
        self.emailBuilder = emailBuilder
        self.onCopy = onCopy
        self.onSend = onSend
        _selectedMedicines = State(initialValue: [primaryMedicine.objectID])
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Messaggio da inviare a \(doctorName)")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 12) {
                        Button {
                            onCopy(selectedList)
                            dismiss()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.title3)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Copia testo")

                        if emailAddress != nil {
                            Button {
                                sendEmail()
                            } label: {
                                Image(systemName: "envelope.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Invia email")
                        }

                        if phoneInternational != nil {
                            Button {
                                communicationService.sendWhatsApp(
                                    to: doctorContact,
                                    text: whatsappText
                                )
                                onSend(selectedList)
                                dismiss()
                            } label: {
                                // SF Symbol generico: se vuoi l’icona ufficiale WhatsApp, inserisci un asset e sostituisci questa Image.
                                Image(systemName: "message.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            .accessibilityLabel("Invia messaggio WhatsApp")
                        }
                    }
                }
                
                ScrollView {
                    Text(emailBuilder(selectedList))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                
                if availableMedicines.count > 1 {
                    Text("Altri farmaci che richiedono ricetta")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(availableMedicines, id: \.objectID) { med in
                                Button {
                                    toggleSelection(for: med)
                                } label: {
                                    let isSelected = selectedMedicines.contains(med.objectID)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(med.nome)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(isSelected ? "Selezionato" : "Seleziona")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .frame(minWidth: 140)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isSelected ? Color.blue.opacity(0.15) : Color(.systemBackground))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Richiedi ricetta")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $mailComposeData) { data in
            MailComposeView(data: data) { _ in
                mailComposeData = nil
                dismiss()
            }
        }
        .alert("Impossibile aprire Mail", isPresented: $showMailFallbackAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Testo copiato negli appunti. Installa o configura un'app Mail per inviare la richiesta.")
        }
    }

    // MARK: - Helpers

    private func sendEmail() {
        guard let email = emailAddress?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else { return }

        let meds = selectedList
        let subject = emailSubject
        let body = emailBuilder(meds)

        onSend(meds)

        if MFMailComposeViewController.canSendMail() {
            mailComposeData = MailComposeData(
                recipients: [email],
                subject: subject,
                body: body
            )
            return
        }

        guard let mailtoURL = CommunicationService.makeMailtoURL(email: email, subject: subject, body: body) else {
            handleMailFallback(body: body)
            return
        }

        guard UIApplication.shared.canOpenURL(mailtoURL) else {
            handleMailFallback(body: body)
            return
        }

        openURL(mailtoURL) { success in
            if success {
                dismiss()
                return
            }

            UIApplication.shared.open(mailtoURL, options: [:]) { opened in
                if opened {
                    dismiss()
                } else {
                    handleMailFallback(body: body)
                }
            }
        }
    }

    private func handleMailFallback(body: String) {
        UIPasteboard.general.string = body
        showMailFallbackAlert = true
    }

    private var communicationService: CommunicationService {
        CommunicationService(openURL: openURL)
    }

    private var doctorContact: DoctorContact {
        DoctorContact(
            name: doctorName,
            email: emailAddress,
            phoneInternational: phoneInternational
        )
    }

    private var emailSubject: String {
        let names = selectedList.map { $0.nome }.joined(separator: ", ")
        if selectedList.count == 1, let first = selectedList.first {
            return "Richiesta ricetta per \(first.nome)"
        }
        return "Richiesta ricetta per \(names)"
    }

    private var whatsappText: String {
        // Testo precompilato multi-linea (WhatsApp supporta i newline).
        emailBuilder(selectedList)
    }
    
    private var selectedList: [Medicine] {
        availableMedicines.filter { selectedMedicines.contains($0.objectID) }
    }
    
    private var availableMedicines: [Medicine] {
        var result: [Medicine] = []
        result.append(primaryMedicine)
        for med in baseMedicines {
            if med.objectID != primaryMedicine.objectID {
                result.append(med)
            }
        }
        return result
    }
    
    private func toggleSelection(for med: Medicine) {
        let id = med.objectID
        if selectedMedicines.contains(id) {
            if selectedMedicines.count > 1 {
                selectedMedicines.remove(id)
            }
        } else {
            selectedMedicines.insert(id)
        }
    }

    // MARK: - Mail composer

    private struct MailComposeData: Identifiable {
        let id = UUID()
        let recipients: [String]
        let subject: String
        let body: String
    }

    private struct MailComposeView: UIViewControllerRepresentable {
        @Environment(\.dismiss) private var dismiss

        let data: MailComposeData
        let onFinish: (MFMailComposeResult) -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
            let parent: MailComposeView

            init(_ parent: MailComposeView) {
                self.parent = parent
            }

            func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
                controller.dismiss(animated: true) {
                    self.parent.onFinish(result)
                    self.parent.dismiss()
                }
            }
        }

        func makeUIViewController(context: Context) -> MFMailComposeViewController {
            let vc = MFMailComposeViewController()
            vc.setToRecipients(data.recipients)
            vc.setSubject(data.subject)
            vc.setMessageBody(data.body, isHTML: false)
            vc.mailComposeDelegate = context.coordinator
            return vc
        }

        func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    }
}

// MARK: - Logs modal
struct MedicineLogsView: View {
    @Environment(\.managedObjectContext) private var context
    let medicine: Medicine
    
    @FetchRequest var logs: FetchedResults<Log>
    
    init(medicine: Medicine) {
        self.medicine = medicine
        _logs = FetchRequest(
            entity: Log.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Log.timestamp, ascending: false)],
            predicate: NSPredicate(format: "medicine == %@", medicine)
        )
    }
    
    var body: some View {
        List {
            if logs.isEmpty {
                Text("Nessun log disponibile.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(logs, id: \.objectID) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.type ?? "Evento")
                            .font(.headline)
                        Text(dateFormatter.string(from: log.timestamp ?? Date()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let pkg = log.package {
                            Text(packageSummary(pkg))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private func packageSummary(_ pkg: Package) -> String {
        formattedPackageLabel(pkg) ?? "Confezione"
    }
    
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
}

// MARK: - Package formatting helper
private func formattedPackageLabel(_ pkg: Package) -> String? {
    let typeRaw = pkg.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
    let quantity: String? = {
        if pkg.numero > 0 {
            let unitLabel = typeRaw.isEmpty ? "unità" : typeRaw.lowercased()
            return "\(pkg.numero) \(unitLabel)"
        }
        return typeRaw.isEmpty ? nil : typeRaw.capitalized
    }()
    let dosage: String? = {
        guard pkg.valore > 0 else { return nil }
        let unit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(pkg.valore)" : "\(pkg.valore) \(unit)"
    }()
    if let quantity, let dosage {
        return "\(quantity) da \(dosage)"
    }
    if let quantity { return quantity }
    if let dosage { return dosage }
    return nil
}
