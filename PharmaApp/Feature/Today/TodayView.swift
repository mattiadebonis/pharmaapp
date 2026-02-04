import SwiftUI
import CoreData
import MapKit
import UIKit
import MessageUI

/// Vista dedicata al tab "Oggi" (ex insights) con logica locale
struct TodayView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.openURL) private var openURL

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    @FetchRequest(fetchRequest: Doctor.extractDoctors())
    private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Todo.extractTodos())
    private var storedTodos: FetchedResults<Todo>
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "updated_at", ascending: false)])
    private var stocks: FetchedResults<Stock>

    @StateObject private var viewModel = TodayViewModel()
    @StateObject private var locationVM = LocationSearchViewModel()

    @State private var selectedMedicine: Medicine?
    @State private var detailSheetDetent: PresentationDetent = .fraction(0.66)
    @State private var prescriptionEmailMedicine: Medicine?
    @State private var prescriptionToConfirm: Medicine?
    @State private var completionToastItemID: String?
    @State private var completionToastWorkItem: DispatchWorkItem?
    @State private var completionUndoOperationId: UUID?
    @State private var completionUndoLogID: NSManagedObjectID?
    @State private var completionUndoKey: String?
    @State private var completionUndoOperationKey: OperationKey?
    @State private var completedTodoIDs: Set<String> = []
    @State private var completedBlockedSubtasks: Set<String> = []
    @State private var pendingPrescriptionMedIDs: Set<MedicineId> = []
    @State private var lastCompletionResetDay: Date?
    @State private var mailComposeData: MailComposeData?
    @State private var messageComposeData: MessageComposeData?
    @State private var intakeGuardrailPrompt: IntakeGuardrailPrompt?

    var body: some View {
        let state = viewModel.state
        let pendingItems = state.pendingItems
        let purchaseItems = state.purchaseItems
        let therapyItems = state.therapyItems
        let otherItems = state.otherItems
        let showPharmacyCard = state.showPharmacyCard

        let content = List {
            if !therapyItems.isEmpty {
                Section {
                    ForEach(Array(therapyItems.enumerated()), id: \.element.id) { entry in
                        let item = entry.element
                        let isLast = entry.offset == therapyItems.count - 1
                        todoListRow(
                            for: item,
                            isCompleted: completedTodoIDs.contains(viewModel.completionKey(for: item)),
                            isLast: isLast
                        )
                    }
                } header: {
                    HStack {
                        Text("Assunzioni")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .textCase(nil)
                        Spacer()
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                }
            }
            if !purchaseItems.isEmpty {
                Section {
                    if showPharmacyCard {
                        pharmacySuggestionCard()
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(Array(purchaseItems.enumerated()), id: \.element.id) { entry in
                        let item = entry.element
                        let isLast = entry.offset == purchaseItems.count - 1
                        todoListRow(
                            for: item,
                            isCompleted: completedTodoIDs.contains(viewModel.completionKey(for: item)),
                            isLast: isLast
                        )
                    }
                } header: {
                    HStack {
                        Text("Da comprare")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .textCase(nil)
                        Spacer()
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 6)
                }
            }
            ForEach(Array(otherItems.enumerated()), id: \.element.id) { entry in
                let item = entry.element
                let isLast = entry.offset == otherItems.count - 1
                todoListRow(
                    for: item,
                    isCompleted: completedTodoIDs.contains(viewModel.completionKey(for: item)),
                    isLast: isLast
                )
            }
        }
        .overlay {
            if pendingItems.isEmpty {
                insightsPlaceholder
            }
        }
        .listStyle(.plain)
        .listSectionSeparator(.hidden)
        .listSectionSpacing(4)
        .listRowSpacing(2)
        .safeAreaInset(edge: .bottom) {
            if completionToastItemID != nil {
                completionToastView
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .scrollIndicators(.hidden)
        .task(id: state.syncToken) {
            viewModel.syncTodos(from: state.computedTodos, medicines: Array(medicines), option: options.first)
        }
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
        .navigationTitle("Oggi")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            locationVM.ensureStarted()
            resetCompletionIfNewDay()
            refreshState()
        }
        .onChange(of: completedTodoIDs) { _ in
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: PersistenceController.shared.container.viewContext
        )) { _ in
            refreshState()
        }

        mapItemWrappedView(content)
    }

    // MARK: - Helpers insights
    @ViewBuilder
    private func pharmacySuggestionCard() -> some View {
        let primaryLine = pharmacyPrimaryText()
        let statusLine = pharmacyStatusText()
        VStack(alignment: .leading, spacing: 12) {
            pharmacyHeader(primaryLine: primaryLine, statusLine: statusLine)
            pharmacyRouteButtons()
        }
        .padding(.vertical, 12)
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    private func pharmacyPrimaryText() -> String {
        guard let pin = locationVM.pinItem else {
            return "Attiva la posizione per la farmacia consigliata"
        }
        return pin.title
    }

    @ViewBuilder
    private func pharmacyHeader(primaryLine: String, statusLine: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(primaryLine)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let statusLine {
                    Text("·")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(statusLine)
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func pharmacyRouteButtons() -> some View {
        HStack(spacing: 10) {
            pharmacyRouteButton(for: .walking)
            pharmacyRouteButton(for: .driving)
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

        var tint: Color {
            switch self {
            case .walking: return .blue
            case .driving: return .green
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
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mode.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(minutesText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mode.tint.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(mode.tint.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.55)
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
            return max(1, Int(round(distance / 83.0)))
        case .driving:
            return max(1, Int(round(distance / 750.0)))
        }
    }

    private func openDirections(_ mode: PharmacyRouteMode) {
        guard let item = pharmacyMapItem() else { return }
        let launchOptions = [MKLaunchOptionsDirectionsModeKey: mode.launchOption]
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), item], launchOptions: launchOptions)
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

    // MARK: - Todo rows
    private var nestedRowIndent: CGFloat { 38 }

    @ViewBuilder
    private func todoCard<Content: View>(_ content: Content) -> some View {
        content
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
            .listRowSeparator(.hidden)
    }

    private var condensedSubtitleFont: Font {
        Font.custom("SFProDisplay-CondensedLight", size: 15)
    }

    private var condensedSubtitleColor: Color {
        Color.primary.opacity(0.45)
    }

    @ViewBuilder
    private func todoListRow(for item: TodayTodoItem, isCompleted: Bool, isLast: Bool) -> some View {
        let med = medicine(for: item)
        let leadingTime = rowTimeLabel(for: item)
        let canToggle = canToggleTodo(for: item)

        if let blocked = blockedTherapyInfo(for: item) {
            blockedTherapyCard(for: item, info: blocked, leadingTime: leadingTime, isLast: isLast)
        } else if item.category == .purchase,
                  let med,
                  med.obbligo_ricetta,
                  isStockDepleted(med) {
            purchaseWithPrescriptionRow(for: item, medicine: med, leadingTime: leadingTime, isCompleted: isCompleted, isLast: isLast)
        } else {
            let rowOpacity: Double = isCompleted ? 0.55 : 1
            let title = mainLineText(for: item)
            let medSummary = med.map { medicineSubtitle(for: $0) }
            let subtitle = subtitleLine(for: item, medicine: med, summary: medSummary)
            let auxiliaryInfo = auxiliaryLineInfo(for: item)
            let actionText = actionText(for: item, isCompleted: isCompleted)
            let titleColor: Color = isCompleted ? .secondary : .primary
            let prescriptionMedicine = med
            let usesCondensedSubtitleStyle = item.category == .therapy
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
                            leadingTime: leadingTime,
                            title: title,
                            subtitle: subtitle,
                            auxiliaryLine: auxiliaryInfo?.text,
                            auxiliaryUsesDefaultStyle: auxiliaryInfo?.usesDefaultStyle ?? true,
                            isCompleted: isCompleted,
                            showToggle: canToggle,
                            onToggle: { if canToggle { toggleCompletion(for: item) } },
                            subtitleFont: usesCondensedSubtitleStyle ? condensedSubtitleFont : nil,
                            subtitleColor: usesCondensedSubtitleStyle ? condensedSubtitleColor : nil,
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
                .padding(.vertical, 4)
                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
            let medName = medicineTitleWithDosage(for: medicine)
            if let person = personNameForTherapy(medicine) {
                return "Dose di \(medName) per \(person)"
            }
            return "Dose di \(medName)"
        }
        if let medicine = medicine(for: item) {
            return medicineTitleWithDosage(for: medicine)
        }
        return formattedMedicineName(item.title)
    }

    private func prescriptionMainText(for item: TodayTodoItem, medicine: Medicine?) -> String {
        let medName = medicine.map { medicineTitleWithDosage(for: $0) } ?? formattedMedicineName(item.title)
        let doctorName = medicine.map { prescriptionDoctorName(for: $0) } ?? "medico"
        return "Chiedi ricetta per \(medName) al medico \(doctorName)"
    }

    private func subtitleLine(
        for item: TodayTodoItem,
        medicine: Medicine?,
        summary: MedicineAggregateSubtitle?
    ) -> String? {
        if item.category == .therapy {
            if let route = therapyRouteSubtitle(for: medicine) {
                return route
            }
            return nil
        }
        if item.category == .monitoring {
            return item.detail
        }
        if item.category == .deadline {
            return item.detail
        }
        return nil
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

    private func purchaseAuxiliaryLineText(for item: TodayTodoItem, medicine: Medicine) -> Text? {
        var lines: [Text] = []
        var metaParts: [String] = []
        let suppressRequestLine = medicine.obbligo_ricetta && isStockDepleted(medicine)

        if item.id.hasPrefix("purchase|deadline|"), let detail = item.detail, !detail.isEmpty {
            metaParts.append(detail)
        }
        if hasPrescriptionRequest(medicine), !suppressRequestLine {
            let doctor = prescriptionDoctor(for: medicine)
            let docName = doctor.map(doctorFullName) ?? "medico"
            metaParts.append("Richiesta ricetta inviata a \(docName)")
        }
        if !metaParts.isEmpty {
            lines.append(Text(metaParts.joined(separator: " • ")).foregroundStyle(.secondary))
        }

        if let stockLine = purchaseStockStatusLine(for: medicine) {
            lines.append(stockLine)
        }

        if let therapyLine = upcomingTherapyLine(for: medicine) {
            lines.append(therapyLine)
        }

        guard !lines.isEmpty else { return nil }
        return joinTextLines(lines).font(.system(size: 15))
    }

    private func purchaseStockStatusLine(for medicine: Medicine) -> Text? {
        guard let status = purchaseStockStatusLabel(for: medicine) else { return nil }
        let statusColor: Color
        if viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.isDepleted == true {
            statusColor = .red
        } else if viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.isOutOfStock == true {
            statusColor = .orange
        } else {
            statusColor = .secondary
        }
        return Text(status).foregroundStyle(statusColor)
    }

    private func upcomingTherapyLine(for medicine: Medicine) -> Text? {
        guard let next = viewModel.nextUpcomingDoseDate(for: medicine) else { return nil }
        let (label, color) = formattedUpcomingTherapyLabel(for: next)
        return Text(label).foregroundStyle(color)
    }

    private func formattedUpcomingTherapyLabel(for date: Date) -> (String, Color) {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let targetDay = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: today, to: targetDay).day ?? 0
        let timeText = TodayFormatters.time.string(from: date)

        if calendar.isDateInToday(date) {
            return ("Terapia imminente: oggi alle \(timeText)", .red)
        }
        if calendar.isDateInTomorrow(date) {
            return ("Terapia imminente: domani alle \(timeText)", .red)
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let label = "Terapia imminente: \(formatter.string(from: date))"

        if dayDelta <= 7 {
            return (label, .orange)
        }
        return (label, .secondary)
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
        let therapy: Therapy?
        let operationId: UUID
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
    private func blockedTherapyCard(for item: TodayTodoItem, info: BlockedTherapyInfo, leadingTime: String?, isLast: Bool) -> some View {
        let medName = medicineTitleWithDosage(for: info.medicine)
        let canToggle = canToggleTodo(for: item)
        todoCard(
            blockedStepRow(
                title: medName,
                status: nil,
                subtitle: info.personName,
                subtitleColor: .secondary,
                subtitleAsBadge: false,
                iconName: "pills",
                trailingBadge: (info.isOutOfStock && info.isDepleted) ? ("Da rifornire", .orange) : nil,
                leadingTime: leadingTime,
                showCircle: canToggle,
                isDone: isBlockedSubtaskDone(type: "intake", medicine: info.medicine),
                onCheck: canToggle ? { completeBlockedIntake(for: info, item: item) } : nil
            )
        )
    }

    @ViewBuilder
    private func purchaseWithPrescriptionRow(for item: TodayTodoItem, medicine: Medicine, leadingTime: String?, isCompleted: Bool, isLast: Bool) -> some View {
        let medName = medicineTitleWithDosage(for: medicine)
        let requestDone = hasPrescriptionRequest(medicine) || hasPrescriptionReceived(medicine)
        let purchaseDone = isCompleted
        let refillDone = requestDone && purchaseDone
        let purchaseLocked = !hasPrescriptionReceived(medicine)
        let doctorName = prescriptionDoctor(for: medicine).map(doctorFullName) ?? "medico"
        let auxiliaryInfo = auxiliaryLineInfo(for: item)

        VStack(spacing: 10) {
            TodayTodoRowView(
                iconName: "cart.badge.plus",
                actionText: nil,
                leadingTime: leadingTime,
                title: medName,
                subtitle: nil,
                auxiliaryLine: auxiliaryInfo?.text,
                auxiliaryUsesDefaultStyle: auxiliaryInfo?.usesDefaultStyle ?? true,
                isCompleted: refillDone,
                showToggle: false,
                onToggle: {}
            )
            .padding(.vertical, 4)

            VStack(spacing: 10) {
                blockedStepRow(
                    title: "Chiedi ricetta al medico \(doctorName)",
                    status: nil,
                    iconName: "heart.text.square",
                    showCircle: true,
                    isDone: requestDone,
                    onCheck: requestDone ? nil : { sendPrescriptionRequest(for: medicine) }
                )
                .padding(.leading, nestedRowIndent)

                blockedStepRow(
                    title: medName,
                    status: purchaseLocked ? "Bloccato finche non chiedi la ricetta" : nil,
                    subtitle: purchaseSubtitle(for: medicine, awaitingRx: requestDone, doctorName: doctorName),
                    subtitleColor: .secondary,
                    subtitleAsBadge: false,
                    iconName: "cart",
                    showCircle: true,
                    isDone: purchaseDone,
                    isEnabled: !purchaseLocked,
                    onCheck: purchaseLocked ? nil : { toggleCompletion(for: item) }
                )
                .padding(.leading, nestedRowIndent)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .padding(.vertical, 4)
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
        if viewModel.state.medicineStatuses[MedicineId(med.id)]?.needsPrescription == true,
           !hasPrescriptionRequest(med) && !hasPrescriptionReceived(med) {
            sendPrescriptionRequest(for: med)
        }
        let key = viewModel.completionKey(for: item)
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
                therapy: decision.therapy,
                operationId: operationId
            )
            return
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
            operationId: result?.operationId ?? operationId,
            operationKey: operationKey
        )
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
    private func blockedStepRow(title: String, status: String? = nil, subtitle: String? = nil, subtitleColor: Color = .secondary, subtitleAsBadge: Bool = false, iconName: String? = nil, buttons: [SubtaskButton] = [], trailingBadge: (String, Color)? = nil, leadingTime: String? = nil, showCircle: Bool = true, isDone: Bool = false, isEnabled: Bool = true, onCheck: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TodayTodoRowView(
                iconName: iconName ?? "circle",
                actionText: title,
                leadingTime: leadingTime,
                title: "",
                subtitle: subtitle,
                auxiliaryLine: status.map { Text($0).foregroundStyle(.orange) },
                auxiliaryUsesDefaultStyle: false,
                isCompleted: isDone,
                showToggle: showCircle && onCheck != nil && isEnabled,
                trailingBadge: trailingBadge,
                onToggle: { onCheck?() }
            )

            if !buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { entry in
                        let button = entry.element
                        Button(action: button.action) {
                            if let icon = button.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Text(button.label)
                                    .font(.callout)
                                    .foregroundStyle(Color.primary)
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
        isCompleted: Bool,
        leadingTime: String?,
        onSend: @escaping () -> Void,
        onToggle: @escaping () -> Void
    ) -> some View {
        let toggleColor = Color.primary.opacity(0.6)
        return HStack(alignment: .center, spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(isCompleted ? toggleColor.opacity(0.2) : .clear)
                    Circle()
                        .stroke(toggleColor, lineWidth: 1.3)
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            if let leadingTime, !leadingTime.isEmpty {
                Text(leadingTime)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 46, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(prescriptionMainText(for: item, medicine: prescriptionMedicine))
                    .font(.title3)
                    .foregroundStyle(titleColor)
                    .multilineTextAlignment(.leading)
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
            return "heart.text.square"
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
        item.category != .therapy
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

    private func medicineSubtitle(for medicine: Medicine) -> MedicineAggregateSubtitle {
        makeMedicineSubtitle(medicine: medicine)
    }

    private func purchaseSubtitle(for medicine: Medicine, awaitingRx: Bool, doctorName: String) -> String? {
        var parts: [String] = []
        if awaitingRx {
            parts.append("Richiesta ricetta inviata a \(doctorName)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func isStockDepleted(_ medicine: Medicine) -> Bool {
        viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.isDepleted ?? false
    }

    private func purchaseStockStatusLabel(for medicine: Medicine) -> String? {
        viewModel.state.medicineStatuses[MedicineId(medicine.id)]?.purchaseStockStatus
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
            if viewModel.state.medicineStatuses[MedicineId(med.id)]?.needsPrescription == true,
               !hasPrescriptionReceived(med) {
                return
            }
        }

        let key = viewModel.completionKey(for: item)
        if completedTodoIDs.contains(key) {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                completedTodoIDs.remove(key)
            }
            if let actionKey = operationKey(for: item) {
                viewModel.clearOperationId(for: actionKey)
            } else {
                viewModel.clearIntakeOperationId(for: key)
            }
            return
        }

        if item.category == .missedDose, let medicine = medicine(for: item) {
            selectedMedicine = medicine
        }

        if item.category == .therapy, let medicine = medicine(for: item) {
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
                    therapy: decision.therapy,
                    operationId: operationId
                )
                return
            }

            let result = viewModel.recordIntake(
                medicine: medicine,
                therapy: decision.therapy,
                operationId: operationId
            )
            completeItem(item, log: nil, operationId: result?.operationId ?? operationId, operationKey: operationKey)
            return
        }

        let record = recordLogCompletion(for: item)
        if record.log == nil {
            viewModel.clearOperationId(for: record.operationKey)
        }
        completeItem(
            item,
            log: record.log,
            operationId: record.operationId,
            operationKey: record.log == nil ? nil : record.operationKey
        )
    }

    private func completeItem(
        _ item: TodayTodoItem,
        log: Log?,
        operationId: UUID? = nil,
        operationKey: OperationKey? = nil
    ) {
        let key = viewModel.completionKey(for: item)
        completionUndoKey = key
        completionUndoOperationId = operationId ?? log?.operation_id
        completionUndoLogID = log?.objectID
        completionUndoOperationKey = operationKey
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            completedTodoIDs.insert(viewModel.completionKey(for: item))
        }
        showCompletionToast(for: item)
    }

    private func confirmGuardrailOverride(_ prompt: IntakeGuardrailPrompt) {
        let result = viewModel.recordIntake(
            medicine: prompt.medicine,
            therapy: prompt.therapy,
            operationId: prompt.operationId
        )
        intakeGuardrailPrompt = nil
        let opKey = OperationKey.intake(
            completionKey: viewModel.completionKey(for: prompt.item),
            source: .today
        )
        completeItem(
            prompt.item,
            log: nil,
            operationId: result?.operationId ?? prompt.operationId,
            operationKey: opKey
        )
    }

    private func showCompletionToast(for item: TodayTodoItem) {
        completionToastWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            completionToastItemID = item.id
        }
        let undoKey = completionUndoKey
        let undoOperationKey = completionUndoOperationKey
        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                completionToastItemID = nil
            }
            if let undoOperationKey {
                viewModel.clearOperationId(for: undoOperationKey)
            } else if let undoKey {
                viewModel.clearIntakeOperationId(for: undoKey)
            }
            completionUndoKey = nil
            completionUndoOperationId = nil
            completionUndoLogID = nil
            completionUndoOperationKey = nil
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
        viewModel.undoCompletion(
            operationId: completionUndoOperationId,
            logObjectID: completionUndoLogID
        )
        if let opKey = completionUndoOperationKey {
            viewModel.clearOperationId(for: opKey)
        } else if let key = completionUndoKey {
            viewModel.clearIntakeOperationId(for: key)
        }
        completionUndoOperationId = nil
        completionUndoLogID = nil
        completionUndoKey = nil
        completionUndoOperationKey = nil
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
                operationId: viewModel.intakeOperationId(for: viewModel.completionKey(for: item))
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
        resetCompletionIfNewDay()
        viewModel.refreshState(
            medicines: Array(medicines),
            logs: Array(logs),
            todos: Array(storedTodos),
            option: options.first,
            completedTodoIDs: completedTodoIDs
        )
    }

    private func resetCompletionIfNewDay() {
        let today = Calendar.current.startOfDay(for: Date())
        if let last = lastCompletionResetDay, Calendar.current.isDate(last, inSameDayAs: today) {
            return
        }
        lastCompletionResetDay = today
        if !completedTodoIDs.isEmpty { completedTodoIDs.removeAll() }
        if !completedBlockedSubtasks.isEmpty { completedBlockedSubtasks.removeAll() }
        if !pendingPrescriptionMedIDs.isEmpty { pendingPrescriptionMedIDs.removeAll() }
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
                    .foregroundStyle(.secondary)
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
        guard item.category != .purchase, item.category != .deadline else { return nil }
        guard let label = viewModel.state.timeLabel(for: item) else { return nil }
        switch label {
        case .time(let date):
            return TodayFormatters.time.string(from: date)
        case .category:
            return nil
        }
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
        let list = medicines.map { "- \($0.nome)" }.joined(separator: "\n")
        return """
        Gentile \(doctorName),

        avrei bisogno della ricetta per:
        \(list)

        Potresti inviarla appena possibile? Grazie!

        """
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
