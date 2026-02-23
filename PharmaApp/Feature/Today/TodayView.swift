import SwiftUI
import CoreData
import MapKit
import UIKit
import MessageUI

/// Vista dedicata al tab "Oggi" (ex insights) con logica locale
struct TodayView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.openURL) private var openURL
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractRecentLogs(days: 90))
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>
    @StateObject private var viewModel = TodayViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()
    private let therapyRecurrenceManager = RecurrenceManager.shared

    @State private var selectedMedicine: Medicine?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.75)
    @State private var prescriptionEmailMedicine: Medicine?
    @State private var prescriptionToConfirm: Medicine?
    @State private var pendingPrescriptionMedicine: Medicine?
    @State private var selectedDoctorID: NSManagedObjectID?
    @State private var showDoctorPicker = false
    @State private var showAddDoctorSheet = false
    @State private var doctorIDsBeforeAdd: Set<NSManagedObjectID> = []
    @State private var completionToastKey: String?
    @State private var completionToastWorkItem: DispatchWorkItem?
    @State private var completionUndoOperationIds: [UUID] = []
    @State private var completionUndoLogID: NSManagedObjectID?
    @State private var completionUndoKey: String?
    @State private var completionUndoOperationKey: OperationKey?
    @State private var completedTodoIDs: Set<String> = []
    @State private var completingTodoIDs: Set<String> = []
    @State private var disappearingTodoIDs: Set<String> = []
    @State private var completedTodoCache: [String: CompletedTodoSnapshot] = [:]
    @State private var completedBlockedSubtasks: Set<String> = []
    @State private var pendingPrescriptionMedIDs: Set<MedicineId> = []
    @State private var lastCompletionResetDay: Date?
    @State private var didHydrateCompletionState = false
    @State private var isHydratingCompletionState = false
    @State private var mailComposeData: MailComposeData?
    @State private var messageComposeData: MessageComposeData?
    @State private var intakeGuardrailPrompt: IntakeGuardrailPrompt?
    @State private var showCodiceFiscaleFullScreen = false
    @State private var codiceFiscaleEntries: [PrescriptionCFEntry] = []
    @State private var isProfilePresented = false
    @State private var refreshStateWorkItem: DispatchWorkItem?
    @State private var lastRefreshStateExecutionAt: Date = .distantPast
    @State private var isTherapySectionExpanded = true

    @ScaledMetric(relativeTo: .body) private var timingColumnWidth: CGFloat = 112
    private let pharmacyCardCornerRadius: CGFloat = 16
    private let pharmacyAccentColor = Color(red: 0.20, green: 0.62, blue: 0.36)
    private let completionFillDuration: TimeInterval = 0.16
    private let completionHoldDuration: TimeInterval = 1.0
    private let completionDisappearDuration: TimeInterval = 0.18
    private let completionToastDuration: TimeInterval = 2.0
    private let refreshDebounceDuration: TimeInterval = 0.5
    private let refreshThrottleDuration: TimeInterval = 0.5
    private let purchaseSectionAnchorID = "today.purchase.section.anchor"
    private let completionStateDayKey = "pharmaapp.today.completion.day"
    private let completionStateTodoIDsKey = "pharmaapp.today.completion.todoIDs"
    private let completionStateBlockedSubtasksKey = "pharmaapp.today.completion.blockedSubtasks"
    private let showDoctorOfficeSuggestion = false

    private enum CompletedSection {
        case therapy
        case purchase
        case other
    }

    private struct CompletedTodoSnapshot {
        let item: TodayTodoItem
        let section: CompletedSection
        let index: Int
    }

    private struct DoctorPickerSheet: View {
        let doctors: FetchedResults<Doctor>
        @Binding var selectedDoctorID: NSManagedObjectID?
        let onConfirm: (NSManagedObjectID?) -> Void
        let onAddDoctor: () -> Void
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Picker("Medico", selection: $selectedDoctorID) {
                            Text("Seleziona medico").tag(NSManagedObjectID?.none)
                            ForEach(doctors, id: \.objectID) { doc in
                                Text(doctorFullName(doc)).tag(Optional(doc.objectID))
                            }
                        }
                    }
                    Section {
                        Button("Aggiungi medico") {
                            dismiss()
                            onAddDoctor()
                        }
                    }
                }
                .navigationTitle("Medico prescrittore")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annulla") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continua") {
                            onConfirm(selectedDoctorID)
                            dismiss()
                        }
                        .disabled(selectedDoctorID == nil)
                    }
                }
            }
        }

        private func doctorFullName(_ doctor: Doctor) -> String {
            let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return first.isEmpty ? "Medico" : first
        }
    }

    var body: some View {
        let state = viewModel.state
        let basePurchaseItems = state.purchaseItems
        let baseTherapyItems = state.therapyItems
        let therapyItems = visibleItems(mergedItems(base: baseTherapyItems, section: .therapy))
        let watchItems: [TodayTodoItem] = {
            var seenMedicineIDs: Set<MedicineId> = []
            return basePurchaseItems.filter { item in
                guard isWatchMedicineItem(item),
                      let medicineID = item.medicineId,
                      seenMedicineIDs.insert(medicineID).inserted
                else { return false }
                return true
            }
        }()
        let contentList = List {
            todayControlCenterHeader(
                therapyItems: therapyItems,
                watchItems: watchItems
            )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .id(purchaseSectionAnchorID)

            Section {
                if isTherapySectionExpanded {
                    ForEach(Array(therapyItems.enumerated()), id: \.element.id) { entry in
                        let item = entry.element
                        let isLast = entry.offset == therapyItems.count - 1
                        todoListRow(
                            for: item,
                            isCompleted: isTodoSemanticallyCompleted(item),
                            isLast: isLast
                        )
                    }
                }
            } header: {
                sectionHeader(
                    title: nil,
                    subtitle: "Oggi da assumere",
                    count: therapyItems.count,
                    isExpanded: isTherapySectionExpanded,
                    topPadding: 8
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isTherapySectionExpanded.toggle()
                    }
                }
            }

            Section {
                if watchItems.isEmpty {
                    Text("Nessuna scorta a rischio")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(watchItems, id: \.id) { item in
                        riskAttentionRow(for: item)
                    }
                }
            } header: {
                staticSectionHeader(title: "Scorte a rischio", topPadding: 8, bottomPadding: 3)
            }
        }

        let content = ScrollViewReader { proxy in
            contentList
                .onAppear {
                    handlePendingRoute(with: proxy)
                }
                .onChange(of: appRouter.pendingRoute) { _ in
                    handlePendingRoute(with: proxy)
                }
        }
        .fullScreenCover(isPresented: $showCodiceFiscaleFullScreen) {
            CodiceFiscaleFullscreenView(
                entries: codiceFiscaleEntries
            ) {
                showCodiceFiscaleFullScreen = false
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacingIfAvailable(4)
        .listRowSpacing(0)
        .safeAreaInset(edge: .bottom) {
            if completionToastKey != nil {
                completionToastView
                    .padding(.horizontal, 14)
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
                onDidSend: { sendPrescriptionRequest(for: medicine) }
            )
            .presentationDetents([.height(250), .medium])
            .presentationDragIndicator(.visible)
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
                onDidSend: { sendPrescriptionRequest(for: medicine) }
            )
        }
        .sheet(item: $messageComposeData) { data in
            MessageComposeView(data: data) { _ in
                messageComposeData = nil
            }
        }
        .sheet(item: $mailComposeData) { data in
            MailComposeView(data: data) { _ in
                mailComposeData = nil
            }
        }
        .sheet(isPresented: $showDoctorPicker) {
            DoctorPickerSheet(
                doctors: doctors,
                selectedDoctorID: $selectedDoctorID,
                onConfirm: { doctorId in
                    guard let medicine = pendingPrescriptionMedicine else { return }
                    guard let doctorId, let doctor = doctors.first(where: { $0.objectID == doctorId }) else { return }
                    assignPrescribingDoctor(doctor, to: medicine)
                    pendingPrescriptionMedicine = nil
                    prescriptionToConfirm = medicine
                },
                onAddDoctor: {
                    showDoctorPicker = false
                    presentAddDoctorFlow()
                }
            )
        }
        .sheet(isPresented: $showAddDoctorSheet) {
            NavigationStack {
                AddDoctorView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Chiudi") { showAddDoctorSheet = false }
                        }
                    }
            }
        }
        .onChange(of: showDoctorPicker) { isPresented in
            if !isPresented && !showAddDoctorSheet {
                pendingPrescriptionMedicine = nil
            }
        }
        .onChange(of: showAddDoctorSheet) { isPresented in
            guard !isPresented else { return }
            handleAddDoctorDismiss()
        }
        .sheet(item: $intakeGuardrailPrompt) { prompt in
            IntakeGuardrailSheet(
                title: prompt.warning.title,
                message: prompt.warning.message,
                onCancel: { intakeGuardrailPrompt = nil },
                onConfirm: { confirmGuardrailOverride(prompt) }
            )
            .presentationDetents([.medium])
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
                    .presentationDetents([.fraction(0.75), .large], selection: $detailSheetDetent)
                    .presentationDragIndicator(.visible)
                } else {
                    VStack(spacing: 12) {
                        Text("Completa i dati del medicinale")
                            .font(.headline)
                        Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
        .sheet(isPresented: $isProfilePresented) {
            NavigationStack {
                ProfileView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isProfilePresented = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Profilo")
            }
        }
        .navigationTitle("Oggi")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            locationVM.ensureStarted()
            hydrateCompletionStateIfNeeded()
            resetCompletionIfNewDay()
            refreshState()
        }
        .onChange(of: completedTodoIDs) { _ in
            guard !isHydratingCompletionState else { return }
            persistCompletionState()
            refreshState()
        }
        .onChange(of: completedBlockedSubtasks) { _ in
            guard !isHydratingCompletionState else { return }
            persistCompletionState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: PersistenceController.shared.container.viewContext
        )) { notification in
            handleContextObjectsDidChange(notification)
        }

        mapItemWrappedView(content)
    }

    private func handlePendingRoute(with proxy: ScrollViewProxy) {
        guard let route = appRouter.pendingRoute else { return }
        switch route {
        case .today:
            appRouter.markRouteHandled(route)
        case .todayPurchaseList:
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(purchaseSectionAnchorID, anchor: .top)
            }
            appRouter.markRouteHandled(route)
        case .pharmacy:
            openPharmacySuggestionInMaps()
            appRouter.markRouteHandled(route)
        case .codiceFiscaleFullscreen, .profile, .scan, .addMedicine:
            break
        }
    }

    private func completionKey(for item: TodayTodoItem) -> String {
        viewModel.completionKey(for: item)
    }

    private func handlePrescriptionRequestTap(for medicine: Medicine) {
        if medicine.prescribingDoctor != nil {
            prescriptionToConfirm = medicine
            return
        }
        pendingPrescriptionMedicine = medicine
        if doctors.isEmpty {
            presentAddDoctorFlow()
        } else {
            selectedDoctorID = nil
            showDoctorPicker = true
        }
    }

    private func presentAddDoctorFlow() {
        doctorIDsBeforeAdd = Set(doctors.map { $0.objectID })
        showAddDoctorSheet = true
    }

    private func handleAddDoctorDismiss() {
        guard let medicine = pendingPrescriptionMedicine else { return }
        let currentIDs = Set(doctors.map { $0.objectID })
        let newIDs = currentIDs.subtracting(doctorIDsBeforeAdd)
        if let newID = newIDs.first, let doctor = doctors.first(where: { $0.objectID == newID }) {
            assignPrescribingDoctor(doctor, to: medicine)
            pendingPrescriptionMedicine = nil
            prescriptionToConfirm = medicine
            return
        }
        pendingPrescriptionMedicine = nil
    }

    private func assignPrescribingDoctor(_ doctor: Doctor, to medicine: Medicine) {
        medicine.prescribingDoctor = doctor
        do {
            try viewContext.save()
        } catch {
            print("Errore salvataggio medico prescrittore: \(error)")
        }
    }

    private func cacheCompletedItem(_ item: TodayTodoItem) {
        let key = completionKey(for: item)
        guard completedTodoCache[key] == nil else { return }
        if let snapshot = completedTodoSnapshot(for: item) {
            completedTodoCache[key] = snapshot
        }
    }

    private func completedTodoSnapshot(for item: TodayTodoItem) -> CompletedTodoSnapshot? {
        if let index = viewModel.state.therapyItems.firstIndex(of: item) {
            return CompletedTodoSnapshot(item: item, section: .therapy, index: index)
        }
        if let index = viewModel.state.purchaseItems.firstIndex(of: item) {
            return CompletedTodoSnapshot(item: item, section: .purchase, index: index)
        }
        if let index = viewModel.state.otherItems.firstIndex(of: item) {
            return CompletedTodoSnapshot(item: item, section: .other, index: index)
        }
        return nil
    }

    private func mergedItems(base: [TodayTodoItem], section: CompletedSection) -> [TodayTodoItem] {
        var result = base
        let existingKeys = Set(base.map { completionKey(for: $0) })
        let cached = completedTodoCache
            .filter { $0.value.section == section && completedTodoIDs.contains($0.key) }
            .map { $0.value }
            .sorted { $0.index < $1.index }
        var inserted = 0
        for snapshot in cached {
            let key = completionKey(for: snapshot.item)
            if existingKeys.contains(key) { continue }
            let insertionIndex = min(snapshot.index + inserted, result.count)
            result.insert(snapshot.item, at: insertionIndex)
            inserted += 1
        }
        return result
    }

    private func visibleItems(_ items: [TodayTodoItem]) -> [TodayTodoItem] {
        items.filter { isTodoVisible($0) }
    }

    private func isTodoVisible(_ item: TodayTodoItem) -> Bool {
        let key = completionKey(for: item)
        if completingTodoIDs.contains(key) || disappearingTodoIDs.contains(key) {
            return true
        }
        return !completedTodoIDs.contains(key)
    }

    private func isTodoVisuallyCompleted(_ item: TodayTodoItem) -> Bool {
        let key = completionKey(for: item)
        return completedTodoIDs.contains(key)
            || completingTodoIDs.contains(key)
            || disappearingTodoIDs.contains(key)
    }

    private func isTodoSemanticallyCompleted(_ item: TodayTodoItem) -> Bool {
        completedTodoIDs.contains(completionKey(for: item))
    }

    private func isTodoDisappearing(_ item: TodayTodoItem) -> Bool {
        disappearingTodoIDs.contains(completionKey(for: item))
    }

    private enum StockTrafficState {
        case safe
        case warning
        case critical

        var title: String {
            switch self {
            case .safe: return "Sicure"
            case .warning: return "Attenzione"
            case .critical: return "Critiche"
            }
        }

        var color: Color {
            switch self {
            case .safe: return .green
            case .warning: return .orange
            case .critical: return .red
            }
        }
    }

    @ViewBuilder
    private func todayControlCenterHeader(
        therapyItems: [TodayTodoItem],
        watchItems: [TodayTodoItem]
    ) -> some View {
        let adherence = weeklyAdherencePercentage()
        let stockState = stockTrafficState(for: watchItems)
        let nextDose = nextDoseIndicatorText(for: therapyItems)

        VStack(alignment: .leading, spacing: 12) {
            Text("Terapie sotto controllo")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                controlIndicatorCard(
                    title: "Aderenza",
                    value: adherence.map { "\($0)%" } ?? "—",
                    tint: adherenceColor(for: adherence),
                    valueColor: .primary,
                    valueFont: .system(size: 16, weight: .semibold),
                    titleLineLimit: 2
                )
                controlIndicatorCard(
                    title: "Scorte",
                    value: stockState.title,
                    tint: stockState.color,
                    showsTrafficDot: true
                )
                controlIndicatorCard(
                    title: "Prossima dose",
                    value: nextDose,
                    tint: .blue
                )
            }
        }
    }

    @ViewBuilder
    private func controlIndicatorCard(
        title: String,
        value: String,
        tint: Color,
        showsTrafficDot: Bool = false,
        valueColor: Color = .primary,
        valueFont: Font = .system(size: 16, weight: .semibold),
        titleLineLimit: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(titleLineLimit)

            HStack(spacing: 6) {
                if showsTrafficDot {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)
                }
                Text(value)
                    .font(valueFont)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func weeklyAdherencePercentage() -> Int? {
        let calendar = Calendar.current
        let now = Date()
        let endDay = calendar.startOfDay(for: now)
        guard let startDay = calendar.date(byAdding: .day, value: -6, to: endDay) else { return nil }

        let therapies = weeklyAdherenceTherapies
        guard !therapies.isEmpty else { return nil }

        var therapiesByMedicineId: [UUID: [Therapy]] = [:]
        var medicinesById: [UUID: Medicine] = [:]
        for therapy in therapies {
            let medicine = therapy.medicine
            medicinesById[medicine.id] = medicine
            therapiesByMedicineId[medicine.id, default: []].append(therapy)
        }

        let logsByMedicineDay = weeklyAdherenceLogsIndex(
            medicinesById: medicinesById,
            startDay: startDay,
            endDay: endDay,
            referenceDate: now,
            calendar: calendar
        )

        var totalPlanned = 0
        var totalTaken = 0
        var day = startDay
        while day <= endDay {
            for therapy in therapies {
                let planned = weeklyPlannedCount(
                    for: therapy,
                    on: day,
                    referenceDate: now,
                    calendar: calendar
                )
                let taken = weeklyTakenCount(
                    for: therapy,
                    on: day,
                    therapiesByMedicineId: therapiesByMedicineId,
                    logsByMedicineDay: logsByMedicineDay,
                    calendar: calendar
                )
                totalPlanned += planned
                totalTaken += taken
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        guard totalPlanned > 0 else { return nil }
        let ratio = min(1, Double(totalTaken) / Double(totalPlanned))
        return max(0, min(100, Int((ratio * 100).rounded())))
    }

    private var weeklyAdherenceTherapies: [Therapy] {
        var seen: Set<NSManagedObjectID> = []
        return medicines
            .flatMap { $0.therapies ?? [] }
            .filter { therapy in
                guard let rule = therapy.rrule, !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return false
                }
                return seen.insert(therapy.objectID).inserted
            }
    }

    private func weeklyPlannedCount(
        for therapy: Therapy,
        on day: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let ruleText = therapy.rrule, !ruleText.isEmpty else { return 0 }
        let rule = therapyRecurrenceManager.parseRecurrenceString(ruleText)
        let start = therapy.start_date ?? day
        let dosesPerDay = max(1, therapy.doses?.count ?? 0)
        let planned = therapyRecurrenceManager.allowedEvents(
            on: day,
            rule: rule,
            startDate: start,
            dosesPerDay: dosesPerDay,
            calendar: calendar
        )
        guard planned > 0 else { return 0 }

        // For today, count only doses scheduled up to "now".
        guard calendar.isDate(day, inSameDayAs: referenceDate) else { return planned }
        guard let doseSet = therapy.doses, !doseSet.isEmpty else { return planned }

        let dueToday = doseSet
            .sorted { $0.time < $1.time }
            .reduce(into: 0) { count, dose in
                guard let scheduledAt = weeklyScheduledDoseDate(
                    on: day,
                    at: dose.time,
                    calendar: calendar
                ) else { return }
                if scheduledAt <= referenceDate {
                    count += 1
                }
            }
        return min(planned, dueToday)
    }

    private func weeklyScheduledDoseDate(on day: Date, at time: Date, calendar: Calendar) -> Date? {
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        guard let hour = timeComponents.hour, let minute = timeComponents.minute else { return nil }
        return calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: timeComponents.second ?? 0,
            of: day
        )
    }

    private func weeklyTakenCount(
        for therapy: Therapy,
        on day: Date,
        therapiesByMedicineId: [UUID: [Therapy]],
        logsByMedicineDay: [UUID: [Date: [Log]]],
        calendar _: Calendar
    ) -> Int {
        let medicineID = therapy.medicine.id
        guard let logs = logsByMedicineDay[medicineID]?[day], !logs.isEmpty else { return 0 }

        let assigned = logs.filter { $0.therapy?.objectID == therapy.objectID }.count
        if assigned > 0 { return assigned }

        let unassigned = logs.filter { $0.therapy == nil }
        if unassigned.isEmpty { return 0 }

        let therapyCount = therapiesByMedicineId[medicineID]?.count ?? 0
        if therapyCount <= 1 { return unassigned.count }
        return unassigned.filter { $0.package?.objectID == therapy.package.objectID }.count
    }

    private func weeklyAdherenceLogsIndex(
        medicinesById: [UUID: Medicine],
        startDay: Date,
        endDay: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> [UUID: [Date: [Log]]] {
        var index: [UUID: [Date: [Log]]] = [:]
        for (medicineID, medicine) in medicinesById {
            let effectiveLogs = medicine.effectiveIntakeLogs(calendar: calendar)
            guard !effectiveLogs.isEmpty else { continue }

            for log in effectiveLogs {
                if log.timestamp > referenceDate { continue }
                let day = calendar.startOfDay(for: log.timestamp)
                if day < startDay || day > endDay { continue }
                var dayMap = index[medicineID] ?? [:]
                var dayLogs = dayMap[day] ?? []
                dayLogs.append(log)
                dayMap[day] = dayLogs
                index[medicineID] = dayMap
            }
        }
        return index
    }

    private func adherenceColor(for percentage: Int?) -> Color {
        guard let percentage else { return .secondary }
        if percentage >= 80 { return .green }
        if percentage >= 50 { return .orange }
        return .red
    }

    private func stockTrafficState(for watchItems: [TodayTodoItem]) -> StockTrafficState {
        guard !watchItems.isEmpty else { return .safe }
        for item in watchItems {
            guard let medicineID = item.medicineId,
                  let status = viewModel.state.medicineStatuses[medicineID]
            else { continue }
            if status.isOutOfStock || status.isDepleted {
                return .critical
            }
        }
        return .warning
    }

    private func nextDoseIndicatorText(for therapyItems: [TodayTodoItem]) -> String {
        if let next = therapyItems.first(where: { !isTodoSemanticallyCompleted($0) }),
           let label = rowTimeLabel(for: next),
           !label.isEmpty {
            return label
        }
        if let first = therapyItems.first,
           let label = rowTimeLabel(for: first),
           !label.isEmpty {
            return label
        }
        return "—"
    }

    @ViewBuilder
    private func riskAttentionRow(for item: TodayTodoItem) -> some View {
        let medicine = medicine(for: item)
        Button {
            guard let medicine else { return }
            selectedMedicine = medicine
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(riskMedicineName(for: item))
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(riskAutonomyText(for: item))
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }

    private func riskMedicineName(for item: TodayTodoItem) -> String {
        if let medicine = medicine(for: item) {
            return formattedMedicineName(medicine.nome)
        }
        return formattedMedicineName(item.title)
    }

    private func riskAutonomyText(for item: TodayTodoItem) -> String {
        guard let medicine = medicine(for: item),
              let days = autonomyDays(for: medicine)
        else {
            return "autonomia non disponibile"
        }
        let dayLabel = days == 1 ? "1 giorno" : "\(days) giorni"
        return "autonomia \(dayLabel)"
    }

    @ViewBuilder
    private func staticSectionHeader(
        title: String,
        topPadding: CGFloat = 8,
        bottomPadding: CGFloat = 6
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(todaySectionHeaderColor)
            Spacer()
        }
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }

    @ViewBuilder
    private func collapsibleSectionHeader(
        title: String,
        isExpanded: Bool,
        topPadding: CGFloat = 8,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(todaySectionHeaderColor)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(todaySecondaryTextColor)
            }
            .padding(.top, topPadding)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var contextDetailsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Farmacie vicine")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(todayPharmacyName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                    Text(todayPharmacyInlineStatus)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if let meta = todayPharmacyMetaLine {
                    Text(meta)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Medico")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(todayPreferredDoctorName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.primary)
                    Text(todayDoctorInlineStatus)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                if let phone = todayDoctorPhoneLine {
                    Text(phone)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Numeri utili")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    usefulNumberButton(
                        title: "118",
                        subtitle: "Emergenze",
                        phoneNumber: "118"
                    )
                    usefulNumberButton(
                        title: "116117",
                        subtitle: "Guardia medica",
                        phoneNumber: "116117"
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func usefulNumberButton(title: String, subtitle: String, phoneNumber: String) -> some View {
        Button {
            callUsefulNumber(phoneNumber)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    private func callUsefulNumber(_ number: String) {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty,
              let url = URL(string: "tel://\(digits)")
        else { return }
        openURL(url)
    }

    private var todayUtilityPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            todayPharmacySuggestionView
            todayDoctorSuggestionView
            if !todayWatchMedicineRows.isEmpty {
                todayWatchMedicinesSuggestionView
            }
        }
        .padding(.vertical, 2)
    }

    private var todayPharmacySuggestionView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(todayPharmacyName)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(todayPharmacyInlineStatus)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let meta = todayPharmacyMetaLine {
                Text(meta)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayDoctorSuggestionView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(todayPreferredDoctorName)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(todayDoctorInlineStatus)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let phone = todayDoctorPhoneLine {
                Text(phone)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayWatchMedicinesSuggestionView: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(todayWatchMedicineRows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(row.autonomy)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayPharmacyName: String {
        let name = locationVM.pinItem?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return "Farmacia"
    }

    private var todayPharmacyInlineStatus: String {
        if locationVM.isLikelyOpen == false {
            return "chiusa ora"
        }
        if let status = pharmacyStatusText() {
            return status == "Aperta" ? "aperta ora" : "chiusa ora"
        }
        return "orari non disponibili"
    }

    private var todayPharmacyMetaLine: String? {
        let distance = pharmacyDistanceText()
        let minutes = todayPharmacyTravelMinutesText
        if let distance, let minutes {
            return "\(distance) • \(minutes)"
        }
        return distance ?? minutes
    }

    private var todayPharmacyTravelMinutesText: String? {
        if let walking = pharmacyRouteMinutes(for: .walking), walking <= 5 {
            return "a piedi \(max(1, walking)) min"
        }
        if let driving = pharmacyRouteMinutes(for: .driving) {
            return "in auto \(max(1, driving)) min"
        }
        if let walking = pharmacyRouteMinutes(for: .walking) {
            return "a piedi \(max(1, walking)) min"
        }
        return nil
    }

    private var todayPreferredDoctor: Doctor? {
        let now = Date()
        if let open = doctors.first(where: { activeDoctorInterval(for: $0, now: now) != nil }) {
            return open
        }
        if let today = doctors.first(where: { doctorTodaySlotText(for: $0) != nil }) {
            return today
        }
        return doctors.first
    }

    private var todayPreferredDoctorName: String {
        guard let doctor = todayPreferredDoctor else { return "Dottore" }
        return doctorDisplayName(doctor)
    }

    private var todayDoctorInlineStatus: String {
        guard let doctor = todayPreferredDoctor else { return "nessun dottore" }
        let now = Date()
        if let active = activeDoctorInterval(for: doctor, now: now) {
            return "aperto fino alle \(OpeningHoursParser.timeString(from: active.end))"
        }
        if let todaySlot = doctorTodaySlotText(for: doctor) {
            return "oggi \(todaySlot)"
        }
        return "orari non disponibili"
    }

    private var todayDoctorPhoneLine: String? {
        guard let doctor = todayPreferredDoctor else { return nil }
        let rawPhone = doctor.telefono?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawPhone, !rawPhone.isEmpty {
            return rawPhone
        }
        return doctorPhoneInternational(doctor)
    }

    private var todayWatchMedicines: [Medicine] {
        let purchaseItems = visibleItems(mergedItems(base: viewModel.state.purchaseItems, section: .purchase))
        var seenMedicineIDs: Set<MedicineId> = []
        var medicines: [Medicine] = []
        for item in purchaseItems {
            guard isWatchMedicineItem(item),
                  let medicine = medicine(for: item)
            else { continue }
            let medicineID = MedicineId(medicine.id)
            guard seenMedicineIDs.insert(medicineID).inserted else { continue }
            medicines.append(medicine)
        }
        return medicines
    }

    private var todayWatchMedicineRows: [(name: String, autonomy: String)] {
        todayWatchMedicines.map { medicine in
            let name = formattedMedicineName(medicine.nome)
            guard let days = autonomyDays(for: medicine) else {
                return (name: name, autonomy: "autonomia non disponibile")
            }
            let dayLabel = days == 1 ? "1 giorno" : "\(days) giorni"
            return (name: name, autonomy: "autonomia \(dayLabel)")
        }
    }

    private func isWatchMedicineItem(_ item: TodayTodoItem) -> Bool {
        guard item.category == .purchase,
              let medicine = medicine(for: item)
        else { return false }

        let medicineID = MedicineId(medicine.id)
        if let status = viewModel.state.medicineStatuses[medicineID] {
            return status.isOutOfStock || status.isDepleted || status.purchaseStockStatus != nil
        }

        guard let days = autonomyDays(for: medicine) else { return false }
        return days <= medicine.stockThreshold(option: options.first)
    }

    // MARK: - Helpers insights
    @ViewBuilder
    private func pharmacySuggestionCard() -> some View {
        let isClosed = locationVM.isLikelyOpen == false
        VStack(alignment: .leading, spacing: 6) {
            if let pin = locationVM.pinItem {
                pharmacyHeader(
                    primaryLine: pin.title,
                    statusLine: pharmacyStatusText(),
                    distanceLine: pharmacyDistanceText()
                )
            }
            if !isClosed {
                pharmacyRouteButtons(
                    distanceLine: pharmacyDistanceText(),
                    statusLine: nil
                )
            } else {
                Text("Riprova più tardi o spostati di qualche centinaio di metri.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var pharmacySuggestionText: String {
        guard let pharmacy = locationVM.pinItem?.title.trimmingCharacters(in: .whitespacesAndNewlines),
              !pharmacy.isEmpty else { return pharmacySuggestionFallbackLine }
        return "\(pharmacy) \(pharmacySuggestionStatusText())"
    }

    private var pharmacySuggestionFallbackLine: String { "Ricerca farmacia piu vicina..." }
    private var pharmacySuggestionDrivingMinutes: Int? { pharmacyRouteMinutes(for: .driving) }

    private struct OpenDoctorSuggestion {
        let name: String
        let contact: DoctorContact
    }

    private var openDoctorSuggestion: OpenDoctorSuggestion? {
        let now = Date()
        for doctor in doctors {
            guard activeDoctorInterval(for: doctor, now: now) != nil else { continue }
            let name = doctorDisplayName(doctor)
            return OpenDoctorSuggestion(
                name: name,
                contact: DoctorContact(
                    name: name,
                    email: doctorEmail(doctor),
                    phoneInternational: doctorPhoneInternational(doctor)
                )
            )
        }
        return nil
    }

    private func pharmacySuggestionStatusText() -> String {
        if locationVM.isLikelyOpen == false {
            return "chiusa ora"
        }
        return "aperta"
    }

    @ViewBuilder
    private func pharmacySuggestionRow(text: String, drivingMinutes: Int?) -> some View {
        Button {
            openPharmacySuggestionInMaps()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(todaySecondaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let drivingMinutes {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                        Text("\(max(1, drivingMinutes)) min")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(todaySecondaryTextColor)
                }
            }
            .padding(.vertical, 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func doctorSuggestionRow(_ suggestion: OpenDoctorSuggestion) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Studio \(suggestion.name) aperto")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(todaySecondaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if suggestion.contact.phoneInternational != nil {
                    Button {
                        callDoctor(suggestion.contact)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(todaySecondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
                if suggestion.contact.email != nil {
                    Button {
                        emailDoctor(suggestion.contact)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(todaySecondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 0)
        .contentShape(Rectangle())
    }

    private func activeDoctorInterval(for doctor: Doctor, now: Date) -> (start: Date, end: Date)? {
        guard let todaySlot = doctorTodaySlotText(for: doctor) else { return nil }
        return OpeningHoursParser.activeInterval(from: todaySlot, now: now)
    }

    private func doctorTodaySlotText(for doctor: Doctor) -> String? {
        let schedule = doctor.scheduleDTO
        let todayWeekday = doctorWeekday(for: Date())
        guard let daySchedule = schedule.days.first(where: { $0.day == todayWeekday }) else { return nil }
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

    private func doctorDisplayName(_ doctor: Doctor) -> String {
        let firstName = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let lastName = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fullName.isEmpty ? "Medico" : fullName
    }

    private func doctorEmail(_ doctor: Doctor) -> String? {
        let email = doctor.mail?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (email?.isEmpty == false) ? email : nil
    }

    private func doctorPhoneInternational(_ doctor: Doctor) -> String? {
        let phone = doctor.telefono?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let phone, !phone.isEmpty else { return nil }
        return CommunicationService.normalizeInternationalPhone(phone)
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    @ViewBuilder
    private func pharmacyHeader(primaryLine: String, statusLine: String?, distanceLine: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cross.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(pharmacyAccentColor)
            HStack(spacing: 4) {
                Text(primaryLine)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let statusLine {
                    Text("·")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(statusLine)
                        .font(.system(size: 17, weight: statusLine == "Aperta" ? .semibold : .regular, design: .rounded))
                        .foregroundColor(statusLine == "Aperta" ? pharmacyAccentColor : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .contentShape(Rectangle())
        .onTapGesture {
            openPharmacyDetailsIfAvailable()
        }
    }

    @ViewBuilder
    private func pharmacyMapPreview() -> some View {
        if let region = locationVM.region {
            ZStack {
                Map(coordinateRegion: Binding(
                    get: { locationVM.region ?? region },
                    set: { locationVM.region = $0 }
                ))
                .allowsHitTesting(false)

                if locationVM.pinItem != nil {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.red)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                openPharmacyDetailsIfAvailable()
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Attiva la posizione per vedere la mappa")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            }
            .frame(height: 140)
        }
    }

    private func openPharmacyDetailsIfAvailable() {
        openPharmacySuggestionInMaps()
    }

    @ViewBuilder
    private func pharmacyRouteButtons(distanceLine: String?, statusLine: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if distanceLine != nil || statusLine != nil {
                HStack(spacing: 10) {
                    if let distanceLine {
                        Text("Distanza \(distanceLine)")
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    if let statusLine {
                        Text(statusLine)
                            .font(.system(size: 17, weight: statusLine == "Aperta" ? .semibold : .regular, design: .rounded))
                            .foregroundColor(statusLine == "Aperta" ? pharmacyAccentColor : .secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                pharmacyRouteButton(for: .walking)
                pharmacyRouteButton(for: .driving)
                pharmacyCodiceFiscaleButton()
            }
        }
    }

    private enum PharmacyRouteMode {
        case walking
        case driving

        var title: String {
            switch self {
            case .walking: return "A piedi"
            case .driving: return "In auto"
            }
        }

        var systemImage: String {
            switch self {
            case .walking: return "figure.walk"
            case .driving: return "car.fill"
            }
        }

        var launchOption: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            }
        }
    }

    private func pharmacyRouteButton(for mode: PharmacyRouteMode) -> some View {
        let minutesText = pharmacyRouteMinutesText(for: mode)
        return Button {
            openDirections(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(minutesText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.55)
    }

    private func pharmacyCodiceFiscaleButton() -> some View {
        Button {
            codiceFiscaleEntries = PrescriptionCodiceFiscaleResolver().entriesForRxAndLowStock(in: viewContext)
            showCodiceFiscaleFullScreen = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "creditcard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Codice fiscale")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
    }

    private func pharmacyRouteMinutesText(for mode: PharmacyRouteMode) -> String {
        guard let minutes = pharmacyRouteMinutes(for: mode) else {
            return "Attiva la posizione"
        }
        return "\(minutes) min"
    }

    private func pharmacyRouteMinutes(for mode: PharmacyRouteMode) -> Int? {
        guard let distance = locationVM.distanceMeters else { return nil }
        switch mode {
        case .walking:
            if let exactMinutes = locationVM.walkingRouteMinutes {
                return exactMinutes
            }
            return max(1, Int(round(distance / 83.0)))
        case .driving:
            if let exactMinutes = locationVM.drivingRouteMinutes {
                return exactMinutes
            }
            return max(1, Int(round(distance / 750.0)))
        }
    }

    private func pharmacyDistanceText() -> String? {
        guard let meters = locationVM.distanceMeters else { return nil }
        if meters < 1000 {
            let roundedMeters = Int((meters / 10).rounded()) * 10
            return "\(roundedMeters) m"
        }
        let km = meters / 1000
        let roundedKm = (km * 10).rounded() / 10
        return String(format: "%.1f km", roundedKm)
    }

    private func openDirections(_ mode: PharmacyRouteMode) {
        guard let item = pharmacyMapItem() else { return }
        let launchOptions = [MKLaunchOptionsDirectionsModeKey: mode.launchOption]
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), item], launchOptions: launchOptions)
    }

    private func openPharmacySuggestionInMaps() {
        locationVM.ensureStarted()
        guard canOpenMaps else {
            if let url = URL(string: "maps://?q=farmacia") {
                openURL(url)
            }
            return
        }
        openDirections(.driving)
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

    private func pharmacyStatusText() -> String? {
        guard locationVM.pinItem != nil else { return nil }
        if locationVM.isLikelyOpen == false {
            return nil
        }
        if locationVM.closingTimeText != nil {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == true {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == nil && locationVM.todayOpeningText == nil {
            return nil
        }
        if let slot = locationVM.todayOpeningText {
            let now = Date()
            if OpeningHoursParser.activeInterval(from: slot, now: now) != nil {
                return "Aperta"
            }
        }
        return "Chiuso"
    }

    // MARK: - Todo rows
    private var nestedRowIndent: CGFloat { 38 }

    @ViewBuilder
    private func todoCard<Content: View>(_ content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
    }

    private var condensedSubtitleFont: Font {
        Font.custom("SFProDisplay-CondensedThin", size: 15)
    }

    private var condensedSubtitleColor: Color {
        isDarkMode ? .white.opacity(0.8) : Color.primary.opacity(0.45)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var todayPrimaryTextColor: Color {
        isDarkMode ? .white : .primary
    }

    private var todaySecondaryTextColor: Color {
        isDarkMode ? .white.opacity(0.8) : .secondary
    }

    private var todaySectionHeaderColor: Color {
        isDarkMode ? .white : .black
    }

    private var completedRowFill: Color {
        .clear
    }

    @ViewBuilder
    private func sectionHeader(
        title: String? = nil,
        subtitle: String? = nil,
        count: Int,
        isExpanded: Bool,
        topPadding: CGFloat,
        bottomPadding: CGFloat = 6,
        showDivider: Bool = false,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    if let subtitle {
                        HStack(spacing: 6) {
                            Text(subtitle)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(todaySectionHeaderColor)
                            Text("\(count)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(todaySecondaryTextColor)
                        }
                        .padding(.top, title != nil ? 10 : 0)
                        Divider()
                            .padding(.top, 4)
                    }
                }
                if subtitle == nil {
                    Text("\(count)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(todaySecondaryTextColor)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(todaySecondaryTextColor)
            }
            .contentShape(Rectangle())
            .textCase(nil)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
        }
        .buttonStyle(.plain)
    }

    private var prescriptionStateIconName: String {
        "doc.text"
    }

    @ViewBuilder
    private func todoListRow(for item: TodayTodoItem, isCompleted: Bool, isLast: Bool) -> some View {
        let med = medicine(for: item)
        let leadingTime = rowTimeLabel(for: item)
        let canToggle = canToggleTodo(for: item)
        let hideToggle = shouldHideToggle(for: item)
        let isToggleOn = isTodoVisuallyCompleted(item)
        let rowOpacity: Double = isTodoDisappearing(item) ? 0 : 1
        let rowBackground = isCompleted ? completedRowFill : .clear

        if let blocked = blockedTherapyInfo(for: item) {
            blockedTherapyCard(for: item, info: blocked, leadingTime: leadingTime, isLast: isLast, hideToggle: hideToggle)
                .listRowBackground(rowBackground)
                .opacity(rowOpacity)
        } else if item.category == .purchase,
                  let med,
                  med.obbligo_ricetta,
                  !hasPrescriptionReceived(med) {
            purchaseWithPrescriptionRow(
                for: item,
                medicine: med,
                leadingTime: leadingTime,
                isCompleted: isCompleted,
                isToggleOn: isToggleOn,
                isLast: isLast
            )
                .listRowBackground(rowBackground)
                .opacity(rowOpacity)
        } else {
            let title = mainLineText(for: item)
            let subtitle: String? = {
                guard item.category == .therapy, let med else { return subtitleLine(for: item) }
                return therapyCompactDetailLine(for: item, medicine: med, leadingTime: leadingTime)
            }()
            let auxiliaryInfo: (text: Text, usesDefaultStyle: Bool)? = {
                guard item.category != .therapy else { return nil }
                return auxiliaryLineInfo(for: item)
            }()
            let actionText = actionText(for: item, isCompleted: isCompleted)
            let titleColor: Color = isCompleted ? todaySecondaryTextColor : todayPrimaryTextColor
            let prescriptionMedicine = med
            let usesCondensedSubtitleStyle = item.category == .monitoring
            let isPrescriptionActionEnabled = item.category == .prescription
            let iconName = actionIcon(for: item)
            let swipeButtons = (item.category == .prescription && prescriptionMedicine != nil) ? prescriptionButtons(for: prescriptionMedicine!) : []

            let baseContent: AnyView = {
                if item.category == .prescription {
                    return AnyView(
                        prescriptionRowContent(
                            item: item,
                            titleColor: titleColor,
                            prescriptionMedicine: prescriptionMedicine,
                            iconName: iconName,
                            isEnabled: isPrescriptionActionEnabled,
                            isCompleted: isCompleted,
                            isToggleOn: isToggleOn,
                            leadingTime: leadingTime,
                            onSend: {
                                handlePrescriptionTap(for: item, medicine: prescriptionMedicine, isEnabled: isPrescriptionActionEnabled)
                            },
                            onToggle: { toggleCompletion(for: item) }
                        )
                    )
                } else {
                    return AnyView(
                        TodayTodoRowView(
                            iconName: iconName,
                            actionText: actionText,
                            leadingTime: item.category == .therapy ? nil : leadingTime,
                            title: title,
                            subtitle: subtitle,
                            auxiliaryLine: auxiliaryInfo?.text,
                            auxiliaryUsesDefaultStyle: auxiliaryInfo?.usesDefaultStyle ?? true,
                            isCompleted: isCompleted,
                            isToggleOn: isToggleOn,
                            showToggle: canToggle,
                            hideToggle: hideToggle,
                            onToggle: { if canToggle { toggleCompletion(for: item) } },
                            subtitleFont: usesCondensedSubtitleStyle ? condensedSubtitleFont : nil,
                            subtitleColor: usesCondensedSubtitleStyle ? condensedSubtitleColor : nil,
                            subtitleAlignsWithTitle: item.category == .therapy,
                            auxiliaryFont: usesCondensedSubtitleStyle ? condensedSubtitleFont : nil,
                            auxiliaryColor: usesCondensedSubtitleStyle ? condensedSubtitleColor : nil
                        )
                    )
                }
            }()

            let rowContent: AnyView = {
                if item.category == .prescription && !swipeButtons.isEmpty {
                    return AnyView(applyPrescriptionSwipe(baseContent, buttons: swipeButtons))
                }
                return baseContent
            }()

            rowContent
                .padding(.vertical, 2)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(rowBackground)
                .opacity(rowOpacity)
        }
    }

    @ViewBuilder
    private func applyPrescriptionSwipe<Content: View>(_ content: Content, buttons: [SubtaskButton]) -> some View {
        if buttons.isEmpty {
            content
        } else {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { entry in
                        let button = entry.element
                        Button {
                            button.action()
                        } label: {
                            if let icon = button.icon {
                                Label(button.label, systemImage: icon)
                            } else {
                                Text(button.label)
                            }
                        }
                    }
                }
        }
    }

    private func handlePrescriptionTap(for item: TodayTodoItem, medicine: Medicine?, isEnabled: Bool) {
        guard item.category == .prescription, isEnabled, let medicine else { return }
        prescriptionEmailMedicine = medicine
    }

    private func mainLineText(for item: TodayTodoItem) -> String {
        if item.category == .therapy, let medicine = medicine(for: item) {
            return medicineTitleWithDosage(for: medicine)
        }
        if let medicine = medicine(for: item) {
            return medicineTitleWithDosage(for: medicine)
        }
        return formattedMedicineName(item.title)
    }

    private func therapyTitleText(for item: TodayTodoItem, medicine: Medicine) -> String {
        let base = medicineTitleWithDosage(for: medicine)
        let contexts = therapyContexts(for: item, medicine: medicine)
        guard !contexts.isEmpty else { return base }

        let unit = doseUnit(for: contexts[0].therapy)
        let amounts = contexts.compactMap { context -> Double? in
            if let amount = context.amount { return amount }
            return context.therapy.commonDoseAmount
        }
        let doseText: String? = {
            guard !amounts.isEmpty else { return "dosi variabili" }
            let totalAmount = amounts.reduce(0, +)
            if totalAmount > 0 {
                return doseDisplayText(amount: totalAmount, unit: unit)
            }
            return "dosi variabili"
        }()

        let rawNames = contexts
            .compactMap { personDisplayName(for: $0.therapy.person) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let personNames = rawNames.filter { seen.insert($0).inserted }

        var parts: [String] = [base]
        if let doseText {
            parts.append(doseText)
        }
        if !personNames.isEmpty {
            parts.append("per \(joinedList(personNames))")
        }
        return parts.joined(separator: " · ")
    }

    private func prescriptionMainText(for item: TodayTodoItem, medicine: Medicine?) -> String {
        let medName = medicine.map { medicineTitleWithDosage(for: $0) } ?? formattedMedicineName(item.title)
        let doctorName = medicine.map { prescriptionDoctorName(for: $0) } ?? "medico"
        return "Chiedi ricetta per \(medName) al medico \(doctorName)"
    }

    private func subtitleLine(for item: TodayTodoItem) -> String? {
        if item.category == .therapy, let medicine = medicine(for: item) {
            return therapySubtitleText(for: item, medicine: medicine)
        }
        if item.category == .monitoring {
            return item.detail
        }
        if item.category == .deadline {
            return item.detail
        }
        return nil
    }

    private func therapySubtitleText(for item: TodayTodoItem, medicine: Medicine) -> String? {
        var parts: [String] = []

        if let dosageLabel = medicineDosageLabel(for: medicine) {
            parts.append(dosageLabel)
        }

        let contexts = therapyContexts(for: item, medicine: medicine)
        if !contexts.isEmpty {
            let unit = doseUnit(for: contexts[0].therapy)
            let amounts = contexts.compactMap { context -> Double? in
                if let amount = context.amount { return amount }
                return context.therapy.commonDoseAmount
            }
            let totalAmount = amounts.reduce(0, +)
            if totalAmount > 0 {
                let doseText = doseDisplayText(amount: totalAmount, unit: unit)
                parts.append(doseText)
            } else if !amounts.isEmpty {
                parts.append("dosi variabili")
            }

            let rawNames = contexts
                .compactMap { personDisplayName(for: $0.therapy.person) }
                .filter { !$0.isEmpty }
            var seen: Set<String> = []
            let personNames = rawNames.filter { seen.insert($0).inserted }
            if !personNames.isEmpty {
                parts.append("per \(joinedList(personNames))")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func therapyRouteSubtitle(for medicine: Medicine?) -> String? {
        let packageRoutes = medicine.flatMap { getPackage(for: $0) }?.vie_somministrazione_json
        let routes = administrationRoutesDescription(from: packageRoutes)
            ?? administrationRoutesDescription(from: medicine?.vie_somministrazione_json)
        guard let routes, !routes.isEmpty else { return nil }
        return "Via di somministrazione: \(routes)"
    }

    private func administrationRoutesDescription(from jsonString: String?) -> String? {
        guard let json = jsonString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [])
        else {
            return nil
        }

        let rawRoutes: [String]
        if let array = object as? [String] {
            rawRoutes = array
        } else if let string = object as? String {
            rawRoutes = [string]
        } else if let anyArray = object as? [Any] {
            rawRoutes = anyArray.compactMap { $0 as? String }
        } else {
            return nil
        }

        let cleaned = rawRoutes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else { return nil }

        var seen: Set<String> = []
        let unique = cleaned.filter { seen.insert($0).inserted }
        return unique.joined(separator: ", ")
    }

    private func therapySummaryText(for item: TodayTodoItem, medicine: Medicine?) -> String? {
        guard item.category == .therapy, let medicine else { return nil }
        if let info = viewModel.nextDoseTodayInfo(for: medicine) {
            return therapySummaryText(for: info.therapy, personNameOverride: info.personName)
        }
        guard let therapies = medicine.therapies, let therapy = therapies.first else { return nil }
        return therapySummaryText(for: therapy, personNameOverride: personDisplayName(for: therapy.person))
    }

    private func therapySummaryText(for therapy: Therapy, personNameOverride: String?) -> String {
        let personName = sanitizedPersonName(personNameOverride) ?? personDisplayName(for: therapy.person)
        let dose = doseDisplayText(for: therapy)
        let frequency = frequencySummaryText(for: therapy)
        let timesText = timesDescriptionText(for: therapy)
        var sentence = "\(dose) \(frequency)"
        if let timesText {
            sentence += " \(timesText)"
        }
        if let personName, !personName.isEmpty {
            sentence += " per \(personName)"
        }
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    private func personDisplayName(for person: Person?) -> String? {
        guard let person else { return nil }
        return sanitizedPersonName(person.nome)
    }

    private func sanitizedPersonName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.lowercased() == "persona" { return nil }
        return trimmed
    }

    private func doseDisplayText(for therapy: Therapy) -> String {
        let unit = doseUnit(for: therapy)
        if let common = therapy.commonDoseAmount {
            return doseDisplayText(amount: common, unit: unit)
        }
        return "dosi variabili"
    }

    private func doseDisplayText(amount: Double, unit: String) -> String {
        if amount == 0.5 {
            return "½ \(unit)"
        }
        let isInt = abs(amount.rounded() - amount) < 0.0001
        let numberString: String = {
            if isInt { return String(Int(amount.rounded())) }
            return String(amount).replacingOccurrences(of: ".", with: ",")
        }()
        let unitString: String = {
            guard amount > 1 else { return unit }
            if unit == "compressa" { return "compresse" }
            if unit == "capsula" { return "capsule" }
            return unit
        }()
        return "\(numberString) \(unitString)"
    }

    private func frequencySummaryText(for therapy: Therapy) -> String {
        let rule = therapyRecurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        switch rule.freq {
        case "DAILY":
            if rule.interval <= 1 { return "al giorno" }
            return "ogni \(rule.interval) giorni"
        case "WEEKLY":
            if !rule.byDay.isEmpty {
                let names = rule.byDay.map { dayCodeToItalian($0) }
                return "nei giorni \(joinedList(names))"
            }
            if rule.interval <= 1 { return "a settimana" }
            return "ogni \(rule.interval) settimane"
        case "MONTHLY":
            if rule.interval <= 1 { return "al mese" }
            return "ogni \(rule.interval) mesi"
        case "YEARLY":
            if rule.interval <= 1 { return "all'anno" }
            return "ogni \(rule.interval) anni"
        default:
            return "a intervalli regolari"
        }
    }

    private func dayCodeToItalian(_ code: String) -> String {
        switch code {
        case "MO": return "lunedì"
        case "TU": return "martedì"
        case "WE": return "mercoledì"
        case "TH": return "giovedì"
        case "FR": return "venerdì"
        case "SA": return "sabato"
        case "SU": return "domenica"
        default: return code
        }
    }

    private func joinedList(_ items: [String]) -> String {
        if items.isEmpty { return "" }
        if items.count == 1 { return items[0] }
        if items.count == 2 { return "\(items[0]) e \(items[1])" }
        let prefix = items.dropLast().joined(separator: ", ")
        return "\(prefix) e \(items.last!)"
    }

    private func timesDescriptionText(for therapy: Therapy) -> String? {
        guard let doseSet = therapy.doses as? Set<Dose>, !doseSet.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let includeAmounts = therapy.commonDoseAmount == nil
        let entries = doseSet.sorted { $0.time < $1.time }
        let segments: [String] = entries.map { dose in
            let timeText = formatter.string(from: dose.time)
            if includeAmounts {
                let amountText = doseDisplayText(amount: dose.amountValue, unit: doseUnit(for: therapy))
                return "\(timeText) (\(amountText))"
            }
            return timeText
        }
        guard !segments.isEmpty else { return nil }
        if segments.count == 1 { return segments[0] }
        if segments.count == 2 { return "\(segments[0]) e \(segments[1])" }
        let prefixTimes = segments.dropLast().joined(separator: ", ")
        let last = segments.last!
        return "\(prefixTimes) e \(last)"
    }

    private func doseUnit(for therapy: Therapy) -> String {
        let tipologia = therapy.package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if tipologia.contains("capsul") { return "capsula" }
        if tipologia.contains("compress") { return "compressa" }
        let unitFallback = therapy.package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        if !unitFallback.isEmpty { return unitFallback.lowercased() }
        return "unità"
    }

    private struct TherapyItemIdentity {
        let therapyIds: [UUID]
        let hour: Int
        let minute: Int
    }

    private func therapyItemIdentity(for item: TodayTodoItem) -> TherapyItemIdentity? {
        guard item.category == .therapy else { return nil }
        let parts = item.id.split(separator: "|")
        guard parts.count >= 4, parts[0] == "therapy" else { return nil }

        let rawTime: String
        let therapyIds: [UUID]

        if parts.count >= 6, parts[1] == "group" {
            rawTime = String(parts[3])
            therapyIds = String(parts[4])
                .split(separator: ",")
                .compactMap { UUID(uuidString: String($0)) }
        } else {
            rawTime = String(parts[2])
            if let singleId = UUID(uuidString: String(parts[1])) {
                therapyIds = [singleId]
            } else {
                therapyIds = []
            }
        }

        guard !therapyIds.isEmpty else { return nil }
        let padded: String
        if rawTime.count == 4 {
            padded = rawTime
        } else if rawTime.count == 3 {
            padded = "0\(rawTime)"
        } else {
            return nil
        }
        guard padded.allSatisfy({ $0.isNumber }) else { return nil }
        guard let hour = Int(padded.prefix(2)), let minute = Int(padded.suffix(2)) else { return nil }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return TherapyItemIdentity(therapyIds: therapyIds, hour: hour, minute: minute)
    }

    private struct TherapyDoseContext {
        let therapy: Therapy
        let amount: Double?
    }

    private func therapyContexts(for item: TodayTodoItem, medicine: Medicine) -> [TherapyDoseContext] {
        guard let identity = therapyItemIdentity(for: item) else { return [] }
        guard let therapies = medicine.therapies else { return [] }
        let selected = therapies.filter { identity.therapyIds.contains($0.id) }
        return selected.map { therapy in
            let amount = doseAmountForTime(in: therapy, hour: identity.hour, minute: identity.minute)
            return TherapyDoseContext(therapy: therapy, amount: amount)
        }
    }

    private func doseAmountForTime(in therapy: Therapy, hour: Int, minute: Int) -> Double? {
        guard let doses = therapy.doses, !doses.isEmpty else { return nil }
        let calendar = Calendar.current
        let matching = doses.filter { dose in
            let comps = calendar.dateComponents([.hour, .minute], from: dose.time)
            return comps.hour == hour && comps.minute == minute
        }
        guard !matching.isEmpty else { return nil }
        return matching.map(\.amountValue).reduce(0, +)
    }

    private func therapyDoseDetailText(for item: TodayTodoItem, medicine: Medicine) -> String? {
        let contexts = therapyContexts(for: item, medicine: medicine)
        guard !contexts.isEmpty else { return nil }

        let unit = doseUnit(for: contexts[0].therapy)
        let amounts = contexts.compactMap { context -> Double? in
            if let amount = context.amount {
                return amount
            }
            return context.therapy.commonDoseAmount
        }
        let totalAmount = amounts.reduce(0, +)
        let hasUnknownAmounts = amounts.count != contexts.count

        let doseText: String
        if totalAmount > 0 {
            doseText = doseDisplayText(amount: totalAmount, unit: unit)
        } else {
            doseText = "dosi variabili"
        }

        var parts: [String] = [doseText]
        if !hasUnknownAmounts,
           let totalUnits = totalUnitsText(
            amount: totalAmount,
            packages: contexts.map { $0.therapy.package }
           ) {
            parts.append(totalUnits)
        }

        let rawNames = contexts
            .compactMap { personDisplayName(for: $0.therapy.person) }
            .filter { !$0.isEmpty }
        if !rawNames.isEmpty {
            var seen: Set<String> = []
            let personNames = rawNames.filter { seen.insert($0).inserted }
            parts.append("per \(joinedList(personNames))")
        }

        return parts.joined(separator: " • ")
    }

    private func therapyCompactDetailLine(for item: TodayTodoItem, medicine: Medicine, leadingTime: String?) -> String? {
        var parts: [String] = []
        if let leadingTime {
            let compactTime = compactTimingLabel(leadingTime)
            if !compactTime.isEmpty {
                parts.append(compactTime)
            }
        }
        if let dosage = therapyDosageLine(for: item, medicine: medicine),
           !dosage.isEmpty {
            parts.append(dosage)
        }
        if let person = therapyPersonLine(for: item, medicine: medicine),
           !person.isEmpty {
            parts.append(person)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func compactTimingLabel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("alle ") else { return trimmed }
        let timeOnly = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        return timeOnly.isEmpty ? trimmed : timeOnly
    }

    private func therapyPersonLine(for item: TodayTodoItem, medicine: Medicine) -> String? {
        let contexts = therapyContexts(for: item, medicine: medicine)
        let rawNames = contexts
            .compactMap { personDisplayName(for: $0.therapy.person) }
            .filter { !$0.isEmpty }
        var seen: Set<String> = []
        let personNames = rawNames.filter { seen.insert($0).inserted }
        if !personNames.isEmpty {
            return joinedList(personNames)
        }
        return personNameForTherapy(medicine)
    }

    private func therapyDosageLine(for item: TodayTodoItem, medicine: Medicine) -> String? {
        let contexts = therapyContexts(for: item, medicine: medicine)
        if !contexts.isEmpty {
            let unit = doseUnit(for: contexts[0].therapy)
            let amounts = contexts.compactMap { context -> Double? in
                if let amount = context.amount { return amount }
                return context.therapy.commonDoseAmount
            }
            if !amounts.isEmpty {
                let totalAmount = amounts.reduce(0, +)
                if totalAmount > 0 {
                    return doseDisplayText(amount: totalAmount, unit: unit)
                }
                return "dosi variabili"
            }
            return "dosi variabili"
        }

        if let detail = therapyDoseDetailText(for: item, medicine: medicine) {
            let firstPart = detail.components(separatedBy: " • ").first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstPart, !firstPart.isEmpty {
                return firstPart
            }
        }

        return nil
    }

    private func totalUnitsText(amount: Double, packages: [Package]) -> String? {
        guard let first = packages.first else { return nil }
        let unit = first.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !unit.isEmpty else { return nil }
        guard first.valore > 0 else { return nil }
        let isUniform = packages.allSatisfy { pkg in
            let otherUnit = pkg.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            return otherUnit == unit && pkg.valore == first.valore
        }
        guard isUniform else { return nil }
        let total = amount * Double(first.valore)
        guard total > 0 else { return nil }
        let numberText = formattedAmount(total)
        return "\(numberText) \(unit.lowercased())"
    }

    private func formattedAmount(_ value: Double) -> String {
        let isInt = abs(value.rounded() - value) < 0.0001
        if isInt { return String(Int(value.rounded())) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }

    private func auxiliaryLineInfo(for item: TodayTodoItem) -> (text: Text, usesDefaultStyle: Bool)? {
        if item.category == .therapy {
            return nil
        }
        if item.category == .purchase, let med = medicine(for: item) {
            guard let text = purchaseAuxiliaryLineText(for: item, medicine: med) else { return nil }
            return (text, false)
        }
        return nil
    }

    private func purchaseAuxiliaryLineText(for item: TodayTodoItem, medicine _: Medicine) -> Text? {
        var lines: [Text] = []
        var metaParts: [String] = []

        if item.id.hasPrefix("purchase|deadline|"), let detail = item.detail, !detail.isEmpty {
            metaParts.append(detail)
        }
        if !metaParts.isEmpty {
            lines.append(Text(metaParts.joined(separator: " • ")).foregroundColor(.secondary))
        }

        guard !lines.isEmpty else { return nil }
        return joinTextLines(lines).font(.system(size: 15))
    }

    private func autonomyDays(for medicine: Medicine) -> Int? {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                totalDaily += therapy.stimaConsumoGiornaliero(recurrenceManager: therapyRecurrenceManager)
            }
            if totalLeft <= 0 { return 0 }
            guard totalDaily > 0 else { return nil }
            let days = Int(floor(totalLeft / totalDaily))
            return max(0, days)
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return max(0, remaining)
        }
        return nil
    }


    private func joinTextLines(_ lines: [Text]) -> Text {
        guard let first = lines.first else { return Text("") }
        var result = first
        for line in lines.dropFirst() {
            result = result + Text("\n") + line
        }
        return result
    }

    private func personNameForTherapy(_ medicine: Medicine) -> String? {
        guard let person = viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.personName else { return nil }
        return person.isEmpty ? nil : person
    }

    // MARK: - Terapia bloccata (ricetta/scorte)
    private struct BlockedTherapyInfo {
        let medicine: Medicine
        let needsPrescription: Bool
        let isOutOfStock: Bool
        let isDepleted: Bool
        let doctor: DoctorContact?
        let personName: String?
    }

    private struct IntakeGuardrailPrompt: Identifiable {
        let id = UUID()
        let warning: IntakeGuardrailWarning
        let item: TodayTodoItem
        let medicine: Medicine
        let therapies: [Therapy]
        let operationIds: [UUID]
    }

    private func blockedTherapyInfo(for item: TodayTodoItem) -> BlockedTherapyInfo? {
        guard item.category == .therapy,
              let blocked = viewModel.state.blockedTherapyStatuses[item.id],
              let medicine = medicine(for: item) else { return nil }
        let contact = prescriptionDoctorContact(for: medicine)
        let personName = blocked.personName
        return BlockedTherapyInfo(
            medicine: medicine,
            needsPrescription: blocked.needsPrescription,
            isOutOfStock: blocked.isOutOfStock,
            isDepleted: blocked.isDepleted,
            doctor: contact,
            personName: personName
        )
    }

    @ViewBuilder
    private func blockedTherapyCard(for item: TodayTodoItem, info: BlockedTherapyInfo, leadingTime: String?, isLast: Bool, hideToggle: Bool) -> some View {
        let medName = formattedMedicineName(info.medicine.nome)
        let medSubtitle = therapySubtitleText(for: item, medicine: info.medicine)
        let canToggle = canToggleTodo(for: item)
        let stockWarning = info.isOutOfStock && info.isDepleted
        todoCard(
            blockedStepRow(
                title: medName,
                status: stockWarning ? "Da rifornire" : nil,
                statusIconName: stockWarning ? "exclamationmark.triangle" : nil,
                statusColor: .orange,
                subtitle: medSubtitle,
                subtitleColor: .secondary,
                subtitleAsBadge: false,
                iconName: "pills",
                leadingTime: leadingTime,
                showCircle: canToggle,
                hideToggle: hideToggle,
                isDone: isBlockedSubtaskDone(type: "intake", medicine: info.medicine),
                isToggleOn: isBlockedSubtaskDone(type: "intake", medicine: info.medicine) || isTodoVisuallyCompleted(item),
                onCheck: canToggle ? { completeBlockedIntake(for: info, item: item) } : nil
            )
        )
    }

    @ViewBuilder
    private func purchaseWithPrescriptionRow(
        for item: TodayTodoItem,
        medicine: Medicine,
        leadingTime: String?,
        isCompleted: Bool,
        isToggleOn: Bool,
        isLast: Bool
    ) -> some View {
        let medName = medicineTitleWithDosage(for: medicine)
        let auxiliaryInfo = auxiliaryLineInfo(for: item)
        let hasRequestedPrescription = hasPrescriptionRequest(medicine)

        return TodayTodoRowView(
            iconName: actionIcon(for: item),
            actionText: nil,
            leadingTime: leadingTime,
            title: medName,
            subtitle: nil,
            auxiliaryLine: auxiliaryInfo?.text,
            auxiliaryUsesDefaultStyle: auxiliaryInfo?.usesDefaultStyle ?? true,
            isCompleted: isCompleted,
            isToggleOn: isToggleOn,
            showToggle: true,
            hideToggle: false,
            trailingBadge: prescriptionRequestBadge(for: medicine),
            trailingBadgeAction: hasRequestedPrescription ? nil : { handlePrescriptionRequestTap(for: medicine) },
            onToggle: { toggleCompletion(for: item) },
            subtitleColor: .secondary
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !hasRequestedPrescription {
                Button {
                    handlePrescriptionRequestTap(for: medicine)
                } label: {
                    Label("Chiedi ricetta", systemImage: prescriptionStateIconName)
                }
                .tint(.orange)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowSeparator(.hidden)
        .padding(.vertical, 1)
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
        "\(type)|\(medicine.id.uuidString)"
    }

    private func isBlockedSubtaskDone(type: String, medicine: Medicine) -> Bool {
        completedBlockedSubtasks.contains(blockedSubtaskKey(type, for: medicine))
    }

    private func hasPrescriptionRequest(_ medicine: Medicine) -> Bool {
        pendingPrescriptionMedIDs.contains(MedicineId(medicine.id)) || medicine.hasNewPrescritpionRequest()
    }

    private func hasPrescriptionReceived(_ medicine: Medicine) -> Bool {
        medicine.hasEffectivePrescriptionReceived()
    }

    private func sendPrescriptionRequest(for medicine: Medicine) {
        let token = viewModel.operationToken(action: .prescriptionRequest, medicine: medicine)
        let log = viewModel.actionService.requestPrescription(for: medicine, operationId: token.id)
        if log != nil {
            pendingPrescriptionMedIDs.insert(MedicineId(medicine.id))
            completedBlockedSubtasks.insert(blockedSubtaskKey("prescription", for: medicine))
            scheduleOperationClear(for: token.key)
        } else {
            viewModel.clearOperationId(for: token.key)
        }
    }

    private func completeBlockedIntake(for info: BlockedTherapyInfo, item: TodayTodoItem) {
        let med = info.medicine
        Haptics.impact(.light)
        let shouldAutoRequestPrescription =
            viewModel.state.medicineStatuses[MedicineId(med.id)]?.needsPrescription == true &&
            !hasPrescriptionRequest(med) &&
            !hasPrescriptionReceived(med)
        let key = completionKey(for: item)
        let contexts = therapyContexts(for: item, medicine: med)
        if !contexts.isEmpty {
            let multiple = contexts.count > 1
            let operationIds: [UUID] = multiple
                ? contexts.map { _ in UUID() }
                : [viewModel.intakeOperationId(for: key)]
            let operationKey = multiple ? nil : OperationKey.intake(completionKey: key, source: .today)

            for context in contexts {
                let decision = viewModel.actionService.intakeDecision(for: context.therapy)
                if let warning = decision.warning {
                    intakeGuardrailPrompt = IntakeGuardrailPrompt(
                        warning: warning,
                        item: item,
                        medicine: med,
                        therapies: contexts.map { $0.therapy },
                        operationIds: operationIds
                    )
                    return
                }
            }

            animateCompletionThenPerform(for: item) {
                if shouldAutoRequestPrescription {
                    sendPrescriptionRequest(for: med)
                }
                var recordedIds: [UUID] = []
                for (context, operationId) in zip(contexts, operationIds) {
                    let result = viewModel.recordIntake(
                        medicine: med,
                        therapy: context.therapy,
                        operationId: operationId
                    )
                    recordedIds.append(result?.operationId ?? operationId)
                }
                if !recordedIds.isEmpty {
                    completedBlockedSubtasks.insert(blockedSubtaskKey("intake", for: med))
                }
                completeItem(
                    item,
                    log: nil,
                    operationIds: recordedIds,
                    operationKey: operationKey,
                    shouldMarkCompleted: false
                )
            }
            return
        }

        let operationId = viewModel.intakeOperationId(for: key)
        let operationKey = OperationKey.intake(completionKey: key, source: .today)
        let decision: IntakeDecision
        if let info = viewModel.nextDoseTodayInfo(for: med) {
            decision = viewModel.actionService.intakeDecision(for: info.therapy)
        } else {
            decision = viewModel.actionService.intakeDecision(for: med)
        }

        if let warning = decision.warning {
            intakeGuardrailPrompt = IntakeGuardrailPrompt(
                warning: warning,
                item: item,
                medicine: med,
                therapies: decision.therapy.map { [$0] } ?? [],
                operationIds: [operationId]
            )
            return
        }

        animateCompletionThenPerform(for: item) {
            if shouldAutoRequestPrescription {
                sendPrescriptionRequest(for: med)
            }
            let result = viewModel.recordIntake(
                medicine: med,
                therapy: decision.therapy,
                operationId: operationId
            )
            if result != nil {
                completedBlockedSubtasks.insert(blockedSubtaskKey("intake", for: med))
            }
            completeItem(
                item,
                log: nil,
                operationIds: [result?.operationId ?? operationId],
                operationKey: operationKey,
                shouldMarkCompleted: false
            )
        }
    }

    private func completeBlockedPurchase(for info: BlockedTherapyInfo) {
        let key = blockedSubtaskKey("purchase", for: info.medicine)
        guard !completedBlockedSubtasks.contains(key) else { return }
        completedBlockedSubtasks.insert(key)
        let token = viewModel.operationToken(action: .purchase, medicine: info.medicine)
        let log = viewModel.actionService.markAsPurchased(for: info.medicine, operationId: token.id)
        if log != nil {
            scheduleOperationClear(for: token.key)
        } else {
            viewModel.clearOperationId(for: token.key)
        }
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
        let icon: String?
    }


    private func prescriptionButtons(for medicine: Medicine) -> [SubtaskButton] {
        var buttons: [SubtaskButton] = []
        if prescriptionDoctorEmail(for: medicine) != nil {
            buttons.append(
                SubtaskButton(label: "Email", action: { sendPrescriptionEmail(for: medicine) }, icon: "envelope.fill")
            )
        }
        if prescriptionDoctorPhoneInternational(for: medicine) != nil {
            buttons.append(
                SubtaskButton(label: "Messaggio", action: { sendPrescriptionMessage(for: medicine) }, icon: "message.fill")
            )
        }
        if buttons.isEmpty {
            buttons.append(SubtaskButton(label: "Invia richiesta", action: { sendPrescriptionRequest(for: medicine) }, icon: "paperplane.fill"))
        }
        return buttons
    }

    private func sendPrescriptionEmail(for medicine: Medicine) {
        let doctor = prescriptionDoctorContact(for: medicine)
        guard let email = doctor.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return }
        let formattedName = formattedMedicineName(medicine.nome)
        let subject = "Richiesta ricetta per \(formattedName)"
        let body = prescriptionEmailBody(for: [medicine], doctorName: doctor.name)

        if MFMailComposeViewController.canSendMail() {
            mailComposeData = MailComposeData(
                recipients: [email],
                subject: subject,
                body: body
            )
            return
        }

        guard let url = CommunicationService.makeMailtoURL(email: email, subject: subject, body: body) else {
            UIPasteboard.general.string = body
            print("Impossibile aprire Mail. Testo copiato negli appunti.")
            return
        }

        openURL(url) { success in
            if success { return }

            UIApplication.shared.open(url, options: [:]) { secondAttempt in
                if !secondAttempt {
                    UIPasteboard.general.string = body
                    print("Impossibile aprire Mail. Testo copiato negli appunti.")
                }
            }
        }
    }

    private func sendPrescriptionMessage(for medicine: Medicine) {
        guard let phone = prescriptionDoctorPhoneInternational(for: medicine)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty else { return }
        let number = phone.hasPrefix("+") ? phone : "+\(phone)"
        let doctor = prescriptionDoctorContact(for: medicine)
        let body = prescriptionEmailBody(for: [medicine], doctorName: doctor.name)

        if MFMessageComposeViewController.canSendText() {
            messageComposeData = MessageComposeData(
                recipients: [number],
                body: body
            )
            return
        }

        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let smsURL = URL(string: "sms:\(number)&body=\(encodedBody)") {
            openURL(smsURL)
        } else {
            UIPasteboard.general.string = body
            print("Impossibile aprire Messaggi. Testo copiato negli appunti.")
        }
    }

    @ViewBuilder
    private func blockedStepRow(title: String, status: String? = nil, statusIconName: String? = nil, statusColor: Color = .orange, subtitle: String? = nil, subtitleColor: Color = .secondary, subtitleAsBadge: Bool = false, iconName: String? = nil, buttons: [SubtaskButton] = [], trailingBadge: (String, Color)? = nil, leadingTime: String? = nil, showCircle: Bool = true, hideToggle: Bool = false, isDone: Bool = false, isToggleOn: Bool? = nil, isEnabled: Bool = true, onCheck: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let statusLine: Text? = {
                guard let status, !status.isEmpty else { return nil }
                if let statusIconName, !statusIconName.isEmpty {
                    return (Text(Image(systemName: statusIconName)) + Text(" \(status)"))
                        .font(.system(size: 15))
                        .foregroundColor(statusColor)
                }
                return Text(status)
                    .font(.system(size: 15))
                    .foregroundColor(statusColor)
            }()

            TodayTodoRowView(
                iconName: iconName ?? "circle",
                actionText: nil,
                leadingTime: leadingTime,
                title: title,
                subtitle: subtitle,
                auxiliaryLine: statusLine,
                auxiliaryUsesDefaultStyle: false,
                isCompleted: isDone,
                isToggleOn: isToggleOn,
                showToggle: showCircle && onCheck != nil && isEnabled,
                hideToggle: hideToggle,
                trailingBadge: trailingBadge,
                onToggle: { onCheck?() },
                subtitleAlignsWithTitle: true
            )

            if !buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { entry in
                        let button = entry.element
                        Button(action: button.action) {
                            if let icon = button.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.accentColor)
                            } else {
                                Text(button.label)
                                    .font(.callout)
                                    .foregroundColor(todayPrimaryTextColor)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, nestedRowIndent)
            }
        }
        .padding(.vertical, 6)
        .opacity(isEnabled ? 1 : 0.45)
        .allowsHitTesting(isEnabled)
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

    private func emailDoctor(_ doctor: DoctorContact?) {
        guard let email = doctor?.email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        guard let url = components.url else { return }
        openURL(url)
    }

    private func prescriptionRowContent(
        item: TodayTodoItem,
        titleColor: Color,
        prescriptionMedicine: Medicine?,
        iconName: String,
        isEnabled: Bool,
        isCompleted: Bool,
        isToggleOn: Bool,
        leadingTime: String?,
        onSend: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) -> some View {
        let toggleColor = Color.primary.opacity(0.6)
        return HStack(alignment: .center, spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isToggleOn ? toggleColor.opacity(0.2) : .clear)
                    Circle()
                        .stroke(toggleColor, lineWidth: 1.3)
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            if let leadingTime, !leadingTime.isEmpty {
                Text(leadingTime)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(todaySecondaryTextColor)
                    .monospacedDigit()
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)
                    .frame(width: timingColumnWidth, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: prescriptionStateIconName)
                    Text(prescriptionMainText(for: item, medicine: prescriptionMedicine))
                }
                .font(.title3)
                .foregroundColor(titleColor)
                .multilineTextAlignment(.leading)
                Button {
                    onSend()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("Invia richiesta")
                    }
                    .font(.callout)
                    .foregroundColor(isEnabled ? Color.accentColor : .secondary)
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
            Spacer(minLength: 8)
        }
    }

    private func actionIcon(for item: TodayTodoItem) -> String {
        switch item.category {
        case .therapy:
            return "pills"
        case .monitoring:
            return "waveform.path.ecg"
        case .missedDose:
            return "exclamationmark.triangle"
        case .purchase:
            return "cart"
        case .deadline:
            return "calendar.badge.exclamationmark"
        case .prescription:
            return prescriptionStateIconName
        case .upcoming, .pharmacy:
            return "checkmark.circle"
        }
    }

    private enum PrescriptionTaskState: Equatable {
        case needsRequest
        case waitingResponse
    }
    private func prescriptionTaskState(for medicine: Medicine?, item: TodayTodoItem) -> PrescriptionTaskState? {
        guard item.category == .prescription, let medicine else { return nil }
        return medicine.hasNewPrescritpionRequest() ? .waitingResponse : .needsRequest
    }

    private func formattedMedicineName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.lowercased().localizedCapitalized
    }

    private func medicineTitleWithDosage(for medicine: Medicine) -> String {
        let base = formattedMedicineName(medicine.nome)
        guard let dosage = medicineDosageLabel(for: medicine) else { return base }
        return "\(base) \(dosage)"
    }

    private func medicineDosageLabel(for medicine: Medicine) -> String? {
        guard let package = getPackage(for: medicine) else { return nil }
        return packageDosageLabel(package)
    }

    private func packageDosageLabel(_ package: Package) -> String? {
        let value = package.valore
        guard value > 0 else { return nil }
        let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? "\(value)" : "\(value) \(unit)"
    }

    private func actionText(for item: TodayTodoItem, isCompleted: Bool) -> String {
        let med = medicine(for: item)
        switch item.category {
        case .therapy:
            return ""
        case .monitoring:
            if isCompleted { return "Misurato" }
            let kind = monitoringKindLabel(for: item)?.lowercased()
            return kind.map { "Misura \($0)" } ?? "Misura"
        case .missedDose:
            return isCompleted ? "Letto" : "Dose mancata"
        case .purchase:
            return ""
        case .deadline:
            return isCompleted ? "Controllata" : "Scadenza"
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

    private func canToggleTodo(for item: TodayTodoItem) -> Bool {
        if item.category == .therapy {
            return manualIntakeEnabled(for: item)
        }
        return true
    }

    private func shouldHideToggle(for item: TodayTodoItem) -> Bool {
        item.category == .therapy && !manualIntakeEnabled(for: item)
    }

    private func manualIntakeEnabled(for item: TodayTodoItem) -> Bool {
        if let option = options.first {
            return option.manual_intake_registration
        }
        guard let medicine = medicine(for: item) else { return false }
        if medicine.manual_intake_registration { return true }
        if let therapies = medicine.therapies as? Set<Therapy> {
            return therapies.contains(where: { $0.manual_intake_registration })
        }
        return false
    }

    private func monitoringKindLabel(for item: TodayTodoItem) -> String? {
        guard item.category == .monitoring else { return nil }
        let parts = item.id.split(separator: "|")
        guard parts.count >= 3 else { return nil }
        let raw = String(parts[2])
        if let kind = MonitoringKind(rawValue: raw) {
            return kind.label
        }
        return raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func groupTitle(for category: TodayTodoItem.Category) -> String {
        switch category {
        case .therapy: return "Assumi"
        case .monitoring: return "Misura"
        case .missedDose: return "Dose mancata"
        case .purchase: return "Compra"
        case .deadline: return "Scadenze"
        case .prescription: return "Ricette"
        case .upcoming: return "Promemoria"
        case .pharmacy: return "Farmacia"
        }
    }

    private func isStockDepleted(_ medicine: Medicine) -> Bool {
        viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.isDepleted ?? false
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

    private func animateCompletionThenPerform(for item: TodayTodoItem, action: @escaping () -> Void) {
        let key = completionKey(for: item)
        guard !completedTodoIDs.contains(key),
              !completingTodoIDs.contains(key),
              !disappearingTodoIDs.contains(key) else { return }

        withAnimation(.easeInOut(duration: completionFillDuration)) {
            completingTodoIDs.insert(key)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + completionFillDuration + completionHoldDuration) {
            withAnimation(.easeInOut(duration: completionDisappearDuration)) {
                completingTodoIDs.remove(key)
                disappearingTodoIDs.insert(key)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + completionDisappearDuration) {
                disappearingTodoIDs.remove(key)
                completedTodoIDs.insert(key)
                action()
            }
        }
    }

    private func toggleCompletion(for item: TodayTodoItem) {
        let key = completionKey(for: item)
        if completedTodoIDs.contains(key) {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                completedTodoIDs.remove(key)
            }
            completingTodoIDs.remove(key)
            disappearingTodoIDs.remove(key)
            completedTodoCache.removeValue(forKey: key)
            if completionToastKey == key {
                completionToastWorkItem?.cancel()
                completionToastWorkItem = nil
                completionToastKey = nil
                completionUndoOperationIds = []
                completionUndoLogID = nil
                completionUndoKey = nil
                completionUndoOperationKey = nil
            }
            if let actionKey = operationKey(for: item) {
                viewModel.clearOperationId(for: actionKey)
            } else {
                viewModel.clearIntakeOperationId(for: key)
            }
            return
        }

        if completingTodoIDs.contains(key) || disappearingTodoIDs.contains(key) {
            return
        }

        if item.category == .therapy {
            Haptics.impact(.light)
        }

        if item.category == .missedDose, let medicine = medicine(for: item) {
            selectedMedicine = medicine
        }

        if item.category == .therapy, let medicine = medicine(for: item) {
            let contexts = therapyContexts(for: item, medicine: medicine)
            if !contexts.isEmpty {
                let multiple = contexts.count > 1
                let operationIds: [UUID] = multiple
                    ? contexts.map { _ in UUID() }
                    : [viewModel.intakeOperationId(for: key)]

                for context in contexts {
                    let decision = viewModel.actionService.intakeDecision(for: context.therapy)
                    if let warning = decision.warning {
                        intakeGuardrailPrompt = IntakeGuardrailPrompt(
                            warning: warning,
                            item: item,
                            medicine: medicine,
                            therapies: contexts.map { $0.therapy },
                            operationIds: operationIds
                        )
                        return
                    }
                }

                let operationKey = multiple ? nil : OperationKey.intake(completionKey: key, source: .today)
                animateCompletionThenPerform(for: item) {
                    var recordedIds: [UUID] = []
                    for (context, operationId) in zip(contexts, operationIds) {
                        let result = viewModel.recordIntake(
                            medicine: medicine,
                            therapy: context.therapy,
                            operationId: operationId
                        )
                        recordedIds.append(result?.operationId ?? operationId)
                    }
                    completeItem(
                        item,
                        log: nil,
                        operationIds: recordedIds,
                        operationKey: operationKey,
                        shouldMarkCompleted: false
                    )
                }
                return
            }

            let operationId = viewModel.intakeOperationId(for: key)
            let operationKey = OperationKey.intake(completionKey: key, source: .today)
            let decision: IntakeDecision
            if let info = viewModel.nextDoseTodayInfo(for: medicine) {
                decision = viewModel.actionService.intakeDecision(for: info.therapy)
            } else {
                decision = viewModel.actionService.intakeDecision(for: medicine)
            }

            if let warning = decision.warning {
                intakeGuardrailPrompt = IntakeGuardrailPrompt(
                    warning: warning,
                    item: item,
                    medicine: medicine,
                    therapies: decision.therapy.map { [$0] } ?? [],
                    operationIds: [operationId]
                )
                return
            }

            animateCompletionThenPerform(for: item) {
                let result = viewModel.recordIntake(
                    medicine: medicine,
                    therapy: decision.therapy,
                    operationId: operationId
                )
                completeItem(
                    item,
                    log: nil,
                    operationIds: [result?.operationId ?? operationId],
                    operationKey: operationKey,
                    shouldMarkCompleted: false
                )
            }
            return
        }

        animateCompletionThenPerform(for: item) {
            let record = recordLogCompletion(for: item)
            if record.log == nil {
                viewModel.clearOperationId(for: record.operationKey)
            }
            completeItem(
                item,
                log: record.log,
                operationIds: record.operationId.map { [$0] } ?? [],
                operationKey: record.log == nil ? nil : record.operationKey,
                shouldMarkCompleted: false
            )
        }
    }

    private func completeItem(
        _ item: TodayTodoItem,
        log: Log?,
        operationIds: [UUID] = [],
        operationKey: OperationKey? = nil,
        shouldMarkCompleted: Bool = true
    ) {
        let key = completionKey(for: item)
        cacheCompletedItem(item)
        completionUndoKey = key
        completionUndoOperationIds = operationIds
        if completionUndoOperationIds.isEmpty, let logId = log?.operation_id {
            completionUndoOperationIds = [logId]
        }
        completionUndoLogID = log?.objectID
        completionUndoOperationKey = operationKey
        if shouldMarkCompleted {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                completedTodoIDs.insert(key)
            }
        }
        showCompletionToast(for: item)
    }

    private func confirmGuardrailOverride(_ prompt: IntakeGuardrailPrompt) {
        var recordedIds: [UUID] = []
        let therapies = prompt.therapies.isEmpty
            ? [prompt.medicine.therapies?.first].compactMap { $0 }
            : prompt.therapies
        let operationIds = prompt.operationIds.isEmpty
            ? therapies.map { _ in UUID() }
            : prompt.operationIds
        for (therapy, operationId) in zip(therapies, operationIds) {
            let result = viewModel.recordIntake(
                medicine: prompt.medicine,
                therapy: therapy,
                operationId: operationId
            )
            recordedIds.append(result?.operationId ?? operationId)
        }
        intakeGuardrailPrompt = nil
        let opKey = therapies.count == 1
            ? OperationKey.intake(
                completionKey: completionKey(for: prompt.item),
                source: .today
            )
            : nil
        completeItem(
            prompt.item,
            log: nil,
            operationIds: recordedIds,
            operationKey: opKey
        )
    }

    private func showCompletionToast(for item: TodayTodoItem) {
        completionToastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            completionToastKey = completionKey(for: item)
        }
        let undoKey = completionUndoKey
        let undoOperationKey = completionUndoOperationKey
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                completionToastKey = nil
            }
            if let undoOperationKey {
                viewModel.clearOperationId(for: undoOperationKey)
            } else if let undoKey {
                viewModel.clearIntakeOperationId(for: undoKey)
            }
            completionUndoKey = nil
            completionUndoOperationIds = []
            completionUndoLogID = nil
            completionUndoOperationKey = nil
            completionToastWorkItem = nil
        }
        completionToastWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + completionToastDuration, execute: workItem)
    }

    private func undoLastCompletion() {
        guard let key = completionToastKey else { return }
        completionToastWorkItem?.cancel()
        completionToastWorkItem = nil
        completionToastKey = nil
        if let logObjectID = completionUndoLogID {
            viewModel.undoCompletion(
                operationId: nil,
                logObjectID: logObjectID
            )
        } else {
            for opId in completionUndoOperationIds {
                viewModel.undoCompletion(operationId: opId, logObjectID: nil)
            }
        }
        if let opKey = completionUndoOperationKey {
            viewModel.clearOperationId(for: opKey)
        } else if let key = completionUndoKey {
            viewModel.clearIntakeOperationId(for: key)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            completedTodoIDs.remove(key)
        }
        completingTodoIDs.remove(key)
        disappearingTodoIDs.remove(key)
        completedTodoCache.removeValue(forKey: key)
        completionUndoOperationIds = []
        completionUndoLogID = nil
        completionUndoKey = nil
        completionUndoOperationKey = nil
        refreshState()
    }

    private struct CompletionRecord {
        let log: Log?
        let operationId: UUID?
        let operationKey: OperationKey?
    }

    private func operationKey(for item: TodayTodoItem) -> OperationKey? {
        guard let medicine = medicine(for: item) else { return nil }
        switch item.category {
        case .purchase:
            return viewModel.operationKey(action: .purchase, medicine: medicine, source: .today)
        case .prescription:
            let action: OperationAction = prescriptionTaskState(for: medicine, item: item) == .waitingResponse
                ? .prescriptionReceived
                : .prescriptionRequest
            return viewModel.operationKey(action: action, medicine: medicine, source: .today)
        default:
            return nil
        }
    }

    private func scheduleOperationClear(for key: OperationKey, delay: TimeInterval = 2.4) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            viewModel.clearOperationId(for: key)
        }
    }

    private func recordLogCompletion(for item: TodayTodoItem) -> CompletionRecord {
        guard let medicine = medicine(for: item) else {
            return CompletionRecord(log: nil, operationId: nil, operationKey: nil)
        }
        let log: Log?
        let operationId: UUID?
        let operationKey: OperationKey?
        switch item.category {
        case .therapy:
            let therapy = viewModel.nextDoseTodayInfo(for: medicine)?.therapy
            _ = viewModel.recordIntake(
                medicine: medicine,
                therapy: therapy,
                operationId: viewModel.intakeOperationId(for: completionKey(for: item))
            )
            log = nil
            operationId = nil
            operationKey = nil
        case .monitoring, .missedDose:
            log = nil
            operationId = nil
            operationKey = nil
        case .purchase:
            let token = viewModel.operationToken(action: .purchase, medicine: medicine)
            log = viewModel.actionService.markAsPurchased(for: medicine, operationId: token.id)
            operationId = token.id
            operationKey = token.key
        case .deadline:
            log = nil
            operationId = nil
            operationKey = nil
        case .prescription:
            if prescriptionTaskState(for: medicine, item: item) == .waitingResponse {
                let token = viewModel.operationToken(action: .prescriptionReceived, medicine: medicine)
                log = viewModel.actionService.markPrescriptionReceived(for: medicine, operationId: token.id)
                if log != nil {
                    pendingPrescriptionMedIDs.remove(MedicineId(medicine.id))
                }
                operationId = token.id
                operationKey = token.key
            } else {
                let token = viewModel.operationToken(action: .prescriptionRequest, medicine: medicine)
                log = viewModel.actionService.requestPrescription(for: medicine, operationId: token.id)
                operationId = token.id
                operationKey = token.key
            }
        case .upcoming, .pharmacy:
            log = nil // Nessun log previsto
            operationId = nil
            operationKey = nil
        }
        if let log {
            print("✅ log creato \(log.type) per \(medicine.nome)")
        } else {
            print("⚠️ recordLogCompletion: log non creato per \(item.id)")
        }
        return CompletionRecord(log: log, operationId: operationId, operationKey: operationKey)
    }

    private func refreshState() {
        lastRefreshStateExecutionAt = Date()
        resetCompletionIfNewDay()
        viewModel.refreshState(
            medicines: Array(medicines),
            logs: Array(logs),
            option: options.first,
            completedTodoIDs: completedTodoIDs
        )
    }

    private var isPresentingModal: Bool {
        selectedMedicine != nil
            || prescriptionEmailMedicine != nil
            || prescriptionToConfirm != nil
            || pendingPrescriptionMedicine != nil
            || showDoctorPicker
            || showAddDoctorSheet
            || mailComposeData != nil
            || messageComposeData != nil
            || intakeGuardrailPrompt != nil
            || showCodiceFiscaleFullScreen
            || isProfilePresented
    }

    private func handleContextObjectsDidChange(_ notification: Notification) {
        guard hasRelevantContextChanges(notification) else { return }
        scheduleRefreshState()
    }

    private func hasRelevantContextChanges(_ notification: Notification) -> Bool {
        let keys = [
            NSInsertedObjectsKey,
            NSUpdatedObjectsKey,
            NSDeletedObjectsKey,
            NSRefreshedObjectsKey
        ]

        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject>, !objects.isEmpty else {
                continue
            }
            if objects.contains(where: { object in
                object is Medicine
                    || object is Log
                    || object is Option
                    || object is Stock
            }) {
                return true
            }
        }
        return false
    }

    private func scheduleRefreshState() {
        refreshStateWorkItem?.cancel()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefreshStateExecutionAt)
        let throttleDelay = max(0, refreshThrottleDuration - elapsed)
        let delay = max(refreshDebounceDuration, throttleDelay)
        let workItem = DispatchWorkItem {
            refreshState()
        }
        refreshStateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func resetCompletionIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastCompletionResetDay, Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        lastCompletionResetDay = today
        if !completedTodoIDs.isEmpty { completedTodoIDs.removeAll() }
        if !completingTodoIDs.isEmpty { completingTodoIDs.removeAll() }
        if !disappearingTodoIDs.isEmpty { disappearingTodoIDs.removeAll() }
        if !completedTodoCache.isEmpty { completedTodoCache.removeAll() }
        if !completedBlockedSubtasks.isEmpty { completedBlockedSubtasks.removeAll() }
        if !pendingPrescriptionMedIDs.isEmpty { pendingPrescriptionMedIDs.removeAll() }
        persistCompletionState()
    }

    private func hydrateCompletionStateIfNeeded() {
        guard !didHydrateCompletionState else { return }
        didHydrateCompletionState = true
        isHydratingCompletionState = true
        defer { isHydratingCompletionState = false }

        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())

        guard let storedDay = defaults.object(forKey: completionStateDayKey) as? Date else {
            lastCompletionResetDay = today
            return
        }

        guard Calendar.current.isDate(storedDay, inSameDayAs: today) else {
            defaults.removeObject(forKey: completionStateTodoIDsKey)
            defaults.removeObject(forKey: completionStateBlockedSubtasksKey)
            lastCompletionResetDay = today
            return
        }

        lastCompletionResetDay = storedDay
        let storedTodoIDs = Set(defaults.stringArray(forKey: completionStateTodoIDsKey) ?? [])
        let storedBlockedSubtasks = Set(defaults.stringArray(forKey: completionStateBlockedSubtasksKey) ?? [])
        if storedTodoIDs != completedTodoIDs {
            completedTodoIDs = storedTodoIDs
        }
        if storedBlockedSubtasks != completedBlockedSubtasks {
            completedBlockedSubtasks = storedBlockedSubtasks
        }
    }

    private func persistCompletionState() {
        let defaults = UserDefaults.standard
        let today = Calendar.current.startOfDay(for: Date())
        defaults.set(today, forKey: completionStateDayKey)
        defaults.set(Array(completedTodoIDs).sorted(), forKey: completionStateTodoIDsKey)
        defaults.set(Array(completedBlockedSubtasks).sorted(), forKey: completionStateBlockedSubtasksKey)
    }

    private var completionToastView: some View {
        HStack {
            Button {
                undoLastCompletion()
            } label: {
                Label("Annulla", systemImage: "arrow.uturn.left")
                    .font(.body.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.70),
                                        Color.white.opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(alignment: .top) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.45),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)
                            .frame(height: 14)
                    }
                    .shadow(color: Color.white.opacity(0.22), radius: 1, x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
            }
            .foregroundColor(Color.primary)
            .buttonStyle(.plain)
            Spacer()
        }
    }

    private struct IntakeGuardrailSheet: View {
        let title: String
        let message: String
        let onCancel: () -> Void
        let onConfirm: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Annulla") { onCancel() }
                        .buttonStyle(.bordered)
                    Button("Registra comunque") { onConfirm() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func rowTimeLabel(for item: TodayTodoItem) -> String? {
        if item.category == .purchase {
            return purchaseLeadingLabel(for: item)
        }
        if item.category == .deadline {
            return nil
        }
        guard let label = viewModel.state.timeLabel(for: item) else { return nil }
        switch label {
        case .time(let date):
            let timeText = TodayFormatters.time.string(from: date)
            return "alle \(timeText)"
        case .category:
            return nil
        }
    }

    private func purchaseLeadingLabel(for item: TodayTodoItem) -> String? {
        guard let med = medicine(for: item) else { return nil }
        let days = autonomyDays(for: med) ?? 0
        return purchaseAutonomyLabel(for: days)
    }

    private func purchaseAutonomyLabel(for days: Int) -> String {
        if days == 1 {
            return "autonomia 1 giorno"
        }
        return "autonomia \(days) giorni"
    }

    private func prescriptionRequestBadge(for medicine: Medicine) -> (String, Color) {
        if hasPrescriptionRequest(medicine) {
            return ("Ricetta richiesta", .green)
        }
        let doctorName = prescriptionDoctorName(for: medicine)
        return ("Ricetta necessaria: \(doctorName)", .orange)
    }

    private func prescriptionDoctorName(for medicine: Medicine) -> String {
        let doctor = prescriptionDoctor(for: medicine)
        let first = (doctor?.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? "Dottore" : first
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

    private func doctorFullName(_ doctor: Doctor?) -> String {
        guard let doctor else { return "Dottore" }
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? "Dottore" : first
    }

    private func prescriptionEmailBody(for medicines: [Medicine], doctorName: String) -> String {
        let medicineNames = medicines.map(\.nome)
        let customTemplate = options.first?.prescription_message_template
        return PrescriptionMessageTemplateRenderer.render(
            template: customTemplate,
            doctorName: doctorName,
            medicineNames: medicineNames
        )
    }

    private func medicine(for item: TodayTodoItem) -> Medicine? {
        guard let id = item.medicineId else { return nil }
        return medicines.first(where: { $0.id == id.rawValue })
    }

    private func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        let purchaseLogs = medicine.effectivePurchaseLogs()
        if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
            return package
        }
        if let package = medicine.packages.first {
            return package
        }
        return nil
    }

    // MARK: - Map wrapper
    @ViewBuilder
    private func mapItemWrappedView<Content: View>(_ content: Content) -> some View {
        content
    }

}

// MARK: - Mail composer helpers
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

private struct MessageComposeData: Identifiable {
    let id = UUID()
    let recipients: [String]
    let body: String
}

private struct MessageComposeView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let data: MessageComposeData
    let onFinish: (MessageComposeResult) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposeView

        init(_ parent: MessageComposeView) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                self.parent.onFinish(result)
                self.parent.dismiss()
            }
        }
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = data.recipients
        vc.body = data.body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}
}
