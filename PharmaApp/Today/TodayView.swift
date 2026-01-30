import SwiftUI
import CoreData
import MapKit
import UIKit
import MessageUI

/// Vista dedicata al tab "Oggi" (ex insights) con logica locale
struct TodayView: View {
    @EnvironmentObject private var appVM: AppViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.managedObjectContext) var managedObjectContext

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
    @State private var selectedMapItem: MKMapItem?
    @State private var completionToastItemID: String?
    @State private var completionToastWorkItem: DispatchWorkItem?
    @State private var completionUndoLogID: NSManagedObjectID?
    @State private var completedTodoIDs: Set<String> = []
    @State private var completedBlockedSubtasks: Set<String> = []
    @State private var pendingPrescriptionMedIDs: Set<NSManagedObjectID> = []
    @State private var mailComposeData: MailComposeData?
    @State private var messageComposeData: MessageComposeData?
    @State private var intakeGuardrailPrompt: IntakeGuardrailPrompt?

    var body: some View {
        let sections = computeSections(for: Array(medicines), logs: Array(logs), option: options.first)
        let insightsContext = viewModel.buildInsightsContext(for: sections, medicines: Array(medicines), option: options.first)
        let urgentIDs = viewModel.urgentMedicineIDs(for: sections)
        let computedTodos = viewModel.buildTodoItems(from: insightsContext, medicines: Array(medicines), urgentIDs: urgentIDs, option: options.first)
        let todoItems = storedTodos.compactMap { TodayTodoItem(todo: $0) }
        let sorted = viewModel.sortTodos(todoItems)
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let filtered = sorted.filter { item in
            if item.category == .therapy, let med = medicine(for: item) {
                return med.hasIntakeToday(recurrenceManager: rec) && !med.hasIntakeLoggedToday()
            }
            return true
        }
        let pendingItems = filtered.filter { !completedTodoIDs.contains(completionKey(for: $0)) }
        let purchaseItems = pendingItems.filter { $0.category == .purchase }
        let nonPurchaseItems = pendingItems.filter { $0.category != .purchase }
        let therapyItems = nonPurchaseItems.filter { $0.category == .therapy }
        let otherItems = nonPurchaseItems.filter { $0.category != .therapy }
        let showPharmacyCard = !purchaseItems.isEmpty

        let content = List {
            ForEach(Array(therapyItems.enumerated()), id: \.element.id) { entry in
                let item = entry.element
                let isLast = entry.offset == therapyItems.count - 1
                todoListRow(
                    for: item,
                    isCompleted: completedTodoIDs.contains(completionKey(for: item)),
                    isLast: isLast
                )
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
                            isCompleted: completedTodoIDs.contains(completionKey(for: item)),
                            isLast: isLast
                        )
                    }
                } header: {
                    HStack {
                        Text("Rifornimenti")
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
                    isCompleted: completedTodoIDs.contains(completionKey(for: item)),
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
        .task(id: syncToken(for: computedTodos)) {
            viewModel.syncTodos(from: computedTodos, medicines: Array(medicines), option: options.first)
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
                onDidSend: { viewModel.actionService.requestPrescription(for: medicine) }
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
                onDidSend: { viewModel.actionService.requestPrescription(for: medicine) }
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
        .onAppear { locationVM.ensureStarted() }

        mapItemWrappedView(content)
    }

    // MARK: - Helpers insights
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
            VStack(alignment: .leading, spacing: 10) {
                pharmacyHeader(primaryLine: primaryLine, statusLine: statusLine)
                pharmacyMiniMap()
            }
            .padding(12)
            
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
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(primaryLine)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let statusLine {
                    Text("·")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(statusLine)
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    private struct PharmacyMapPin: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    @ViewBuilder
    private func pharmacyMiniMap() -> some View {
        if let coordinate = locationVM.pinItem?.mapItem?.placemark.coordinate {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
            )
            Map(
                coordinateRegion: .constant(region),
                interactionModes: [],
                annotationItems: [PharmacyMapPin(coordinate: coordinate)]
            ) { pin in
                MapMarker(coordinate: pin.coordinate, tint: .red)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .allowsHitTesting(false)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemGray6))
                .frame(height: 180)
                .overlay(
                    Text("Attiva la posizione")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
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

    // MARK: - Todo rows
    private var nestedRowIndent: CGFloat { 38 }

    @ViewBuilder
    private func todoCard<Content: View>(_ content: Content) -> some View {
        content
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 14))
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
            let auxiliaryLine = auxiliaryLineText(for: item)
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
                            auxiliaryLine: auxiliaryLine,
                            isCompleted: isCompleted,
                            onToggle: { toggleCompletion(for: item) },
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
            .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 14))
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
            if let med = medicine {
                return personNameForTherapy(med)
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

    private func auxiliaryLineText(for item: TodayTodoItem) -> Text? {
        if item.category == .therapy {
            let med = medicine(for: item)
            let isShowingRoute = therapyRouteSubtitle(for: med) != nil
            if isShowingRoute, let person = med.flatMap(personNameForTherapy) {
                return Text(person)
            }
            return nil
        }
        if item.category == .purchase, let med = medicine(for: item) {
            var parts: [String] = []
            if item.id.hasPrefix("purchase|deadline|"), let detail = item.detail, !detail.isEmpty {
                parts.append(detail)
            }
            if isAwaitingPrescription(med) {
                let doctor = prescriptionDoctor(for: med)
                let docName = doctor.map(doctorFullName) ?? "medico"
                parts.append("Richiesta ricetta inviata a \(docName)")
            }
            if let status = purchaseStockStatusLabel(for: med) {
                parts.append(status)
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
        if let therapies = medicine.therapies,
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
    }

    private func blockedTherapyInfo(for item: TodayTodoItem) -> BlockedTherapyInfo? {
        guard item.category == .therapy, let medicine = medicine(for: item) else { return nil }
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let needsRx = viewModel.needsPrescriptionBeforePurchase(medicine, option: options.first, recurrenceManager: rec)
        let outOfStock = viewModel.isOutOfStock(medicine, option: options.first, recurrenceManager: rec)
        let depleted = isStockDepleted(medicine)
        guard needsRx || outOfStock else { return nil }
        let contact = prescriptionDoctorContact(for: medicine)
        let personName = personNameForTherapy(medicine)
        return BlockedTherapyInfo(
            medicine: medicine,
            needsPrescription: needsRx,
            isOutOfStock: outOfStock,
            isDepleted: depleted,
            doctor: contact,
            personName: personName
        )
    }

    @ViewBuilder
    private func blockedTherapyCard(for item: TodayTodoItem, info: BlockedTherapyInfo, leadingTime: String?, isLast: Bool) -> some View {
        let medName = medicineTitleWithDosage(for: info.medicine)
        todoCard(
            blockedStepRow(
                title: "Assumi \(medName)",
                status: nil,
                subtitle: info.personName,
                subtitleColor: .secondary,
                subtitleAsBadge: false,
                iconName: "pills",
                trailingBadge: (info.isOutOfStock && info.isDepleted) ? ("Da rifornire", .orange) : nil,
                leadingTime: leadingTime,
                showCircle: true,
                isDone: isBlockedSubtaskDone(type: "intake", medicine: info.medicine),
                onCheck: { completeBlockedIntake(for: info) }
            )
        )
    }

    @ViewBuilder
    private func purchaseWithPrescriptionRow(for item: TodayTodoItem, medicine: Medicine, leadingTime: String?, isCompleted: Bool, isLast: Bool) -> some View {
        let medName = medicineTitleWithDosage(for: medicine)
        let prescriptionDone = isAwaitingPrescription(medicine)
        let purchaseDone = isCompleted
        let refillDone = prescriptionDone && purchaseDone
        let purchaseLocked = !prescriptionDone
        let doctorName = prescriptionDoctor(for: medicine).map(doctorFullName) ?? "medico"

        VStack(spacing: 10) {
            TodayTodoRowView(
                iconName: "cart.badge.plus",
                actionText: nil,
                leadingTime: leadingTime,
                title: medName,
                subtitle: nil,
                auxiliaryLine: nil,
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
                    isDone: prescriptionDone,
                    onCheck: prescriptionDone ? nil : { sendPrescriptionRequest(for: medicine) }
                )
                .padding(.leading, nestedRowIndent)

                blockedStepRow(
                    title: medName,
                    status: purchaseLocked ? "Bloccato finche non chiedi la ricetta" : nil,
                    subtitle: purchaseSubtitle(for: medicine, awaitingRx: prescriptionDone, doctorName: doctorName),
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
        "\(type)|\(medicine.objectID.uriRepresentation().absoluteString)"
    }

    private func isBlockedSubtaskDone(type: String, medicine: Medicine) -> Bool {
        completedBlockedSubtasks.contains(blockedSubtaskKey(type, for: medicine))
    }

    private func isAwaitingPrescription(_ medicine: Medicine) -> Bool {
        pendingPrescriptionMedIDs.contains(medicine.objectID) || medicine.hasNewPrescritpionRequest()
    }

    private func sendPrescriptionRequest(for medicine: Medicine) {
        _ = viewModel.actionService.requestPrescription(for: medicine)
        pendingPrescriptionMedIDs.insert(medicine.objectID)
        completedBlockedSubtasks.insert(blockedSubtaskKey("prescription", for: medicine))
    }

    private func completeBlockedIntake(for info: BlockedTherapyInfo) {
        let med = info.medicine
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        if needsPrescriptionBeforePurchase(med, recurrenceManager: rec),
           !isAwaitingPrescription(med) {
            sendPrescriptionRequest(for: med)
        }
        completedBlockedSubtasks.insert(blockedSubtaskKey("purchase", for: med))
        _ = viewModel.actionService.markAsPurchased(for: med)
        completedBlockedSubtasks.insert(blockedSubtaskKey("intake", for: med))
    }

    private func completeBlockedPurchase(for info: BlockedTherapyInfo) {
        let key = blockedSubtaskKey("purchase", for: info.medicine)
        guard !completedBlockedSubtasks.contains(key) else { return }
        completedBlockedSubtasks.insert(key)
        _ = viewModel.actionService.markAsPurchased(for: info.medicine)
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
                auxiliaryLine: status.map { Text($0).foregroundColor(.orange) },
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

    private func allowedEvents(on day: Date, for therapy: Therapy, recurrenceManager: RecurrenceManager) -> Int {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let start = therapy.start_date ?? day
        let perDay = max(1, therapy.doses?.count ?? 0)
        return recurrenceManager.allowedEvents(on: day, rule: rule, startDate: start, dosesPerDay: perDay)
    }

    private func occursToday(_ therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> Bool {
        return allowedEvents(on: now, for: therapy, recurrenceManager: recurrenceManager) > 0
    }

    private func scheduledTimesToday(for therapy: Therapy, now: Date, recurrenceManager: RecurrenceManager) -> [Date] {
        let today = Calendar.current.startOfDay(for: now)
        let allowed = allowedEvents(on: today, for: therapy, recurrenceManager: recurrenceManager)
        guard allowed > 0 else { return [] }
        guard let doseSet = therapy.doses, !doseSet.isEmpty else { return [] }
        let sortedDoses = doseSet.sorted { $0.time < $1.time }
        let limitedDoses = sortedDoses.prefix(min(allowed, sortedDoses.count))
        return limitedDoses.compactMap { dose in
            combine(day: today, withTime: dose.time)
        }
    }

    private func intakeCountToday(for therapy: Therapy, medicine: Medicine, now: Date) -> Int {
        let calendar = Calendar.current
        let logsToday = (medicine.logs ?? []).filter { $0.type == "intake" && calendar.isDate($0.timestamp, inSameDayAs: now) }
        let assigned = logsToday.filter { $0.therapy == therapy }.count
        if assigned > 0 { return assigned }

        let unassigned = logsToday.filter { $0.therapy == nil }
        let therapyCount = medicine.therapies?.count ?? 0
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
            if let firstPending = pending.first {
                return firstPending
            }
        }

        return recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: therapy.doses as NSSet?)
    }

    private func nextDoseTodayInfo(for medicine: Medicine) -> TodayDoseInfo? {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
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
        return first.isEmpty ? nil : first
    }

    private func therapyVerb(for medicine: Medicine) -> String {
        let now = Date()
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return "continuare" }
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
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
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
            return isCompleted ? "Assunto" : "Assumi"
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
        let unitForm = medicineUnitForm(for: medicine)
        var lines: [String] = []

        if let therapies = medicine.therapies, !therapies.isEmpty {
            let totalLeft = therapies.reduce(0.0) { $0 + Double($1.leftover()) }
            lines.append(stockLine(count: Int(max(0, totalLeft)), unitForm: unitForm))
            if totalLeft <= 0, let nextDose = earliestDoseToday(for: medicine) {
                lines.append("Prossima dose scoperta: \(TodayFormatters.time.string(from: nextDose))")
            }
            return lines.joined(separator: "\n")
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            lines.append(stockLine(count: max(0, remaining), unitForm: unitForm))
            if remaining <= 0, let nextDose = earliestDoseToday(for: medicine) {
                lines.append("Prossima dose scoperta: \(TodayFormatters.time.string(from: nextDose))")
            }
            return lines.joined(separator: "\n")
        }
        return nil
    }

    private func stockLine(count: Int, unitForm: UnitForm) -> String {
        let isSingular = count == 1
        let unitText = isSingular ? unitForm.singular : unitForm.plural
        let verb = isSingular ? "rimasta" : "rimaste"
        return "\(count) \(unitText) \(verb)"
    }

    private struct UnitForm {
        let singular: String
        let plural: String
        let aliases: [String]
    }

    private static let unitForms: [UnitForm] = [
        UnitForm(singular: "compressa", plural: "compresse", aliases: ["compressa", "compresse"]),
        UnitForm(singular: "capsula", plural: "capsule", aliases: ["capsula", "capsule"]),
        UnitForm(singular: "fiala", plural: "fiale", aliases: ["fiala", "fiale"]),
        UnitForm(singular: "bustina", plural: "bustine", aliases: ["bustina", "bustine"]),
        UnitForm(singular: "goccia", plural: "gocce", aliases: ["goccia", "gocce"]),
        UnitForm(singular: "cerotto", plural: "cerotti", aliases: ["cerotto", "cerotti"]),
        UnitForm(singular: "ovulo", plural: "ovuli", aliases: ["ovulo", "ovuli"]),
        UnitForm(singular: "supposta", plural: "supposte", aliases: ["supposta", "supposte"]),
        UnitForm(singular: "flaconcino", plural: "flaconcini", aliases: ["flaconcino", "flaconcini"]),
        UnitForm(singular: "flacone", plural: "flaconi", aliases: ["flacone", "flaconi"]),
        UnitForm(singular: "siringa", plural: "siringhe", aliases: ["siringa", "siringhe"]),
        UnitForm(singular: "pipetta", plural: "pipette", aliases: ["pipetta", "pipette"]),
        UnitForm(singular: "boccetta", plural: "boccette", aliases: ["boccetta", "boccette"]),
        UnitForm(singular: "sacca", plural: "sacche", aliases: ["sacca", "sacche"]),
        UnitForm(singular: "garza", plural: "garze", aliases: ["garza", "garze"]),
        UnitForm(singular: "pastiglia", plural: "pastiglie", aliases: ["pastiglia", "pastiglie"]),
        UnitForm(singular: "pillola", plural: "pillole", aliases: ["pillola", "pillole"]),
        UnitForm(singular: "spray", plural: "spray", aliases: ["spray"]),
        UnitForm(singular: "pezzo", plural: "pezzi", aliases: ["pezzo", "pezzi", "pz"]),
        UnitForm(singular: "unità", plural: "unità", aliases: ["unità"])
    ]

    private static let fallbackUnitForm = UnitForm(
        singular: "unità",
        plural: "unità",
        aliases: []
    )

    private func medicineUnitForm(for medicine: Medicine) -> UnitForm {
        let package = medicine.therapies?.first?.package ?? medicine.packages.first
        if let form = unitForm(from: package?.tipologia) { return form }
        if let form = unitForm(from: package?.unita) { return form }
        return Self.fallbackUnitForm
    }

    private func unitForm(from raw: String?) -> UnitForm? {
        guard let raw else { return nil }
        let normalized = raw.lowercased().replacingOccurrences(
            of: #"[^\p{L}]+"#,
            with: " ",
            options: .regularExpression
        )
        let tokens = normalized.split(separator: " ").map(String.init)
        for token in tokens {
            if let match = Self.unitForms.first(where: { form in
                form.aliases.contains(where: { token.hasPrefix($0) })
            }) {
                return match
            }
        }
        return nil
    }

    private func medicineSubtitle(for medicine: Medicine) -> MedicineAggregateSubtitle {
        makeMedicineSubtitle(medicine: medicine)
    }

    private func purchaseSubtitle(for medicine: Medicine, awaitingRx: Bool, doctorName: String) -> String? {
        var parts: [String] = []
        if awaitingRx {
            parts.append("Richiesta ricetta inviata a \(doctorName)")
        }
        if let status = purchaseStockStatusLabel(for: medicine) {
            parts.append(status)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func isStockDepleted(_ medicine: Medicine) -> Bool {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            let totalLeft = therapies.reduce(0.0) { $0 + Double($1.leftover()) }
            return totalLeft <= 0
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            return remaining <= 0
        }
        return false
    }

    private func purchaseStockStatusLabel(for medicine: Medicine) -> String? {
        let threshold = medicine.stockThreshold(option: options.first)
        if let therapies = medicine.therapies, !therapies.isEmpty {
            var totalLeft: Double = 0
            var dailyUsage: Double = 0
            for therapy in therapies {
                totalLeft += Double(therapy.leftover())
                dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: RecurrenceManager(context: PersistenceController.shared.container.viewContext))
            }
            if totalLeft <= 0 {
                return "Scorte finite"
            }
            guard dailyUsage > 0 else { return nil }
            let days = totalLeft / dailyUsage
            return days < Double(threshold) ? "Scorte in esaurimento" : nil
        }
        if let remaining = medicine.remainingUnitsWithoutTherapy() {
            if remaining <= 0 {
                return "Scorte finite"
            }
            return remaining < threshold ? "Scorte in esaurimento" : nil
        }
        return nil
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
                return
            }
        }

        let key = completionKey(for: item)
        if completedTodoIDs.contains(key) {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
                completedTodoIDs.remove(key)
            }
            return
        }

        if item.category == .missedDose, let medicine = medicine(for: item) {
            selectedMedicine = medicine
        }

        if item.category == .therapy, let medicine = medicine(for: item) {
            let result: IntakeGuardrailResult
            if let info = nextDoseTodayInfo(for: medicine) {
                result = viewModel.actionService.guardedMarkAsTaken(for: info.therapy)
            } else {
                result = viewModel.actionService.guardedMarkAsTaken(for: medicine)
            }
            switch result {
            case .allowed(let log):
                completeItem(item, log: log)
            case .requiresConfirmation(let warning, let therapy):
                intakeGuardrailPrompt = IntakeGuardrailPrompt(
                    warning: warning,
                    item: item,
                    medicine: medicine,
                    therapy: therapy
                )
            }
            return
        }

        let log = recordLogCompletion(for: item)
        completeItem(item, log: log)
    }

    private func completeItem(_ item: TodayTodoItem, log: Log?) {
        completionUndoLogID = log?.objectID
        _ = withAnimation(.easeInOut(duration: 0.2)) {
            completedTodoIDs.insert(completionKey(for: item))
        }
        showCompletionToast(for: item)
    }

    private func confirmGuardrailOverride(_ prompt: IntakeGuardrailPrompt) {
        let log: Log?
        if let therapy = prompt.therapy {
            log = viewModel.actionService.markAsTaken(for: therapy)
        } else {
            log = viewModel.actionService.markAsTaken(for: prompt.medicine)
        }
        intakeGuardrailPrompt = nil
        completeItem(prompt.item, log: log)
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

    private func recordLogCompletion(for item: TodayTodoItem) -> Log? {
        guard let medicine = medicine(for: item) else {
            return nil // Nessun log richiesto (es. task generico)
        }
        let log: Log?
        switch item.category {
        case .therapy:
            if let info = nextDoseTodayInfo(for: medicine) {
                log = viewModel.actionService.markAsTaken(for: info.therapy)
            } else {
                log = viewModel.actionService.markAsTaken(for: medicine)
            }
        case .monitoring, .missedDose:
            log = nil
        case .purchase:
            log = viewModel.actionService.markAsPurchased(for: medicine)
        case .deadline:
            log = nil
        case .prescription:
            if prescriptionTaskState(for: medicine, item: item) == .waitingResponse {
                log = viewModel.actionService.markPrescriptionReceived(for: medicine)
            } else {
                log = viewModel.actionService.requestPrescription(for: medicine)
            }
        case .upcoming, .pharmacy:
            log = nil // Nessun log previsto
        }
        if let log {
            print("✅ log creato \(log.type) per \(medicine.nome)")
        } else {
            print("⚠️ recordLogCompletion: log non creato per \(item.id)")
        }
        return log
    }

    private func completionKey(for item: TodayTodoItem) -> String {
        if item.category == .monitoring || item.category == .missedDose {
            return item.id
        }
        if let medID = item.medicineID {
            return "\(item.category.rawValue)|\(medID)"
        }
        return item.id
    }

    private func syncToken(for items: [TodayTodoItem]) -> String {
        items.map { item in
            let detail = item.detail ?? ""
            let medID = item.medicineID?.uriRepresentation().absoluteString ?? ""
            return "\(item.id)|\(item.category.rawValue)|\(item.title)|\(detail)|\(medID)"
        }.joined(separator: "||")
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

    // MARK: - Build insights data
    private func buildInsightsContext(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> AIInsightsContext? {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let purchaseCandidates = sections.purchase.filter { !needsPrescriptionBeforePurchase($0, recurrenceManager: rec) }
        let purchaseLines = purchaseCandidates.prefix(5).map { medicine in
            "\(medicine.nome): \(purchaseHighlight(for: medicine, recurrenceManager: rec))"
        }
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
            return "\(medicine.nome): \(TodayFormatters.time.string(from: next))"
        } else if calendar.isDateInTomorrow(next) {
            return "\(medicine.nome): domani"
        }
        let fmt = DateFormatter(); fmt.dateStyle = .short; fmt.timeStyle = .short
        return "\(medicine.nome): \(fmt.string(from: next))"
    }

    private func nextDoseTodayHighlight(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> String? {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return nil }
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var timesToday: [Date] = []
        for therapy in therapies {
            let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
            let startDate = therapy.start_date ?? now
            let next = recurrenceManager.nextOccurrence(rule: rule, startDate: startDate, after: today, doses: therapy.doses as NSSet?)
            if let next, calendar.isDateInToday(next) {
                timesToday.append(next)
            }
        }
        guard let nextToday = timesToday.sorted().first else { return nil }
        let timeText = TodayFormatters.time.string(from: nextToday)
        return "\(medicine.nome): \(timeText)"
    }

    private var pharmacyHighlightLine: String {
        if let distance = shortDistanceText() ?? distanceMetersText() {
            return "Farmacia consigliata a \(distance)"
        }
        return "Farmacia consigliata nelle vicinanze"
    }

    // MARK: - Todo building
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

    private func timeSortValue(for item: TodayTodoItem) -> Int? {
        guard let date = todoTimeDate(for: item) else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func todoTimeDate(for item: TodayTodoItem) -> Date? {
        if let medicine = medicine(for: item), let date = earliestDoseToday(for: medicine) {
            return date
        }
        guard let detail = item.detail, let match = timeComponents(from: detail) else { return nil }
        let now = Date()
        return Calendar.current.date(bySettingHour: match.hour, minute: match.minute, second: 0, of: now)
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

    private func rowTimeLabel(for item: TodayTodoItem) -> String? {
        guard item.category != .purchase, item.category != .deadline else { return nil }
        guard let date = todoTimeDate(for: item) else { return nil }
        return TodayFormatters.time.string(from: date)
    }

    private func categoryRank(_ category: TodayTodoItem.Category) -> Int {
        viewModel.categoryRank(category)
    }

    private func urgentMedicineIDs(for sections: (purchase: [Medicine], oggi: [Medicine], ok: [Medicine])) -> Set<NSManagedObjectID> {
        viewModel.urgentMedicineIDs(for: sections)
    }

    private func hasUpcomingTherapyInNextWeek(for medicine: Medicine, recurrenceManager: RecurrenceManager) -> Bool {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return false }
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

    // MARK: - Helpers reused from FeedView
    private func earliestDoseToday(for medicine: Medicine) -> Date? {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        return viewModel.earliestDoseToday(for: medicine, recurrenceManager: rec)
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
        guard let id = item.medicineID else { return nil }
        return medicines.first(where: { $0.objectID == id })
    }

    private func getPackage(for medicine: Medicine) -> Package? {
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

    // MARK: - Map wrapper
    @ViewBuilder
    private func mapItemWrappedView<Content: View>(_ content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .mapItemDetailSheet(item: $selectedMapItem, displaysMap: true)
        } else {
            content
        }
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
