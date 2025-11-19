import SwiftUI
import CoreData
import UIKit

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
    
    let medicine: Medicine
    let package: Package
    
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest private var therapies: FetchedResults<Therapy>
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) private var allMedicines: FetchedResults<Medicine>
    
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    @State private var showEmailSheet = false
    
    private let stockDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
    
    init(medicine: Medicine, package: Package) {
        self.medicine = medicine
        self.package = package
        _therapies = FetchRequest(
            entity: Therapy.entity(),
            sortDescriptors: [NSSortDescriptor(keyPath: \Therapy.start_date, ascending: true)],
            predicate: NSPredicate(format: "medicine == %@", medicine)
        )
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    heroCard
                    quickActionsSection
                    stockSection
                    if shouldShowPrescriptionCard {
                        prescriptionSection
                    }
                    therapiesSection
                }
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(medicine.nome.isEmpty ? "Dettagli" : medicine.nome)
                        .font(.headline)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showEmailSheet) {
            EmailRequestSheet(
                doctorName: doctorDisplayName,
                primaryMedicine: medicine,
                emailAddress: doctorEmail,
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
                    sendEmailBody(for: meds)
                    meds.forEach { med in
                        actionsViewModel.addNewPrescriptionRequest(for: med)
                        actionsViewModel.addNewPrescription(for: med)
                    }
                }
            )
            .presentationDetents([.medium, .large])
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

    private var shouldShowPrescriptionCard: Bool {
        !prescriptionStatus.isEmpty
    }

    private var detailAccentColor: Color {
        if totalLeftover <= 0 {
            return .red
        }
        return medicine.obbligo_ricetta ? .blue : .green
    }

    private var packageSummary: String? {
        var parts: [String] = []
        if package.valore > 0 {
            let unit = package.unita.trimmingCharacters(in: .whitespacesAndNewlines)
            if unit.isEmpty {
                parts.append("\(package.valore)")
            } else {
                parts.append("\(package.valore) \(unit)")
            }
        }
        let volume = package.volume.trimmingCharacters(in: .whitespacesAndNewlines)
        if !volume.isEmpty {
            parts.append(volume)
        }
        if package.numero > 0 {
            parts.append("\(package.numero) pz")
        }
        let type = package.tipologia.trimmingCharacters(in: .whitespacesAndNewlines)
        if !type.isEmpty {
            parts.append(type.capitalized)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
    
    private var currentTherapiesSet: Set<Therapy> {
        medicine.therapies ?? []
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
        if let therapies = medicine.therapies, !therapies.isEmpty {
            return therapies.reduce(0) { total, therapy in
                total + Int(therapy.leftover())
            }
        }
        return medicine.remainingUnitsWithoutTherapy() ?? 0
    }
    
    private var leftoverColor: Color {
        totalLeftover <= 0 ? .red : .primary
    }
    
    private var prescriptionStatus: String {
        guard let option = currentOption, medicine.obbligo_ricetta else { return "" }
        let inEsaurimento = medicine.isInEsaurimento(option: option, recurrenceManager: recurrenceManager)
        if inEsaurimento {
            if medicine.hasPendingNewPrescription() {
                return "Da comprare"
            } else if medicine.hasNewPrescritpionRequest() {
                return "Ricetta richiesta"
            } else {
                return "Ricetta da chiedere"
            }
        }
        return ""
    }
    
    private var doctorWithEmail: Doctor? {
        doctors.first(where: { !($0.mail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    
    private var doctorEmail: String? {
        doctorWithEmail?.mail?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var doctorDisplayName: String {
        let first = doctorWithEmail?.nome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let last = doctorWithEmail?.cognome?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let components = [first, last].filter { !$0.isEmpty }
        return components.isEmpty ? "Dottore" : components.joined(separator: " ")
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
    
    private func markAsToPurchase() {
        actionsViewModel.emptyStocks(for: medicine)
    }
    
    private func deleteMedicine() {
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
    @ViewBuilder
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(medicine.nome.isEmpty ? "Medicinale" : medicine.nome)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    let active = medicine.principio_attivo.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !active.isEmpty {
                        Text(active)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .textCase(.uppercase)
                    }
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 60, height: 60)
                    Image(systemName: medicine.obbligo_ricetta ? "cross.case.fill" : "pills.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            if let packageSummary {
                Text(packageSummary)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            HStack(spacing: 12) {
                HeroStat(icon: "cube.box.fill", title: "Unità", value: "\(max(totalLeftover, 0))")
                HeroStat(icon: "calendar.badge.clock", title: "Copertura", value: coverageSummaryText)
                HeroStat(icon: "clock.arrow.circlepath", title: "Terapie", value: "\(therapyCount)")
            }
            if medicine.obbligo_ricetta {
                Label("Richiede ricetta", systemImage: "doc.text.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.2), in: Capsule())
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    detailAccentColor.opacity(0.95),
                    detailAccentColor.opacity(0.7),
                    detailAccentColor.opacity(0.6)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: detailAccentColor.opacity(0.3), radius: 16, y: 8)
    }

    private var quickActionsSection: some View {
        DetailSectionCard(title: "Azioni rapide", icon: "bolt.fill") {
            VStack(spacing: 14) {
                if let action = primaryAction {
                    Button {
                        handlePrimaryAction(action)
                    } label: {
                        Label(action.label, systemImage: action.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: action.color, textColor: .white))
                }

                HStack(spacing: 12) {
                    Button {
                        markAsToPurchase()
                    } label: {
                        Label("Da acquistare", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: Color(.secondarySystemBackground), textColor: .primary))

                    Button(role: .destructive) {
                        deleteMedicine()
                    } label: {
                        Label("Elimina", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: Color.red.opacity(0.15), textColor: .red))
                }
            }
        }
    }

    private var stockSection: some View {
        DetailSectionCard(title: "Scorte", icon: "shippingbox") {
            NavigationInfoRow(
                icon: "square.stack.3d",
                title: "Gestione scorte",
                subtitle: stockEstimateSubtitle,
                value: stockDisplayValue,
                valueColor: leftoverColor
            ) {
                StockManagementView(medicine: medicine, package: package, viewModel: viewModel)
            }

            if totalLeftover <= 0 {
                Text("Scorte esaurite: aggiorna con un nuovo acquisto per azzerare l'allarme.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var therapiesSection: some View {
        DetailSectionCard(title: "Terapie", icon: "clock") {
            NavigationInfoRow(
                icon: "clock.arrow.circlepath",
                title: "Terapie attive",
                subtitle: therapySummarySubtitle,
                value: "\(therapyCount)",
                valueColor: .primary
            ) {
                TherapiesManagementView(medicine: medicine, package: package)
            }
        }
    }

    private var prescriptionSection: some View {
        DetailSectionCard(title: "Ricetta", icon: "doc.text.fill") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stato ricetta")
                        .font(.subheadline.weight(.semibold))
                    Text(prescriptionStatus)
                        .font(.body)
                    if let email = doctorEmail {
                        Label(email, systemImage: "envelope")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }
}
// MARK: - UI helpers
private struct HeroStat: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title.uppercased(), systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
    }
}

private struct NavigationInfoRow<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let value: String?
    let valueColor: Color
    let destination: Destination

    init(icon: String,
         title: String,
         subtitle: String?,
         value: String?,
         valueColor: Color,
         @ViewBuilder destination: () -> Destination) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.valueColor = valueColor
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(.headline)
                        .foregroundStyle(valueColor)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CapsuleActionButtonStyle: ButtonStyle {
    let fill: Color
    let textColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SettingRow: View {
    let icon: String
    let title: String
    let value: String?
    let subtitle: String?
    let valueColor: Color
    var showDisclosure: Bool = true
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let value = value {
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(valueColor)
            }
            if showDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct EmailRequestSheet: View {
    let doctorName: String
    let primaryMedicine: Medicine
    let emailAddress: String?
    let baseMedicines: [Medicine]
    let emailBuilder: ([Medicine]) -> String
    let onCopy: ([Medicine]) -> Void
    let onSend: ([Medicine]) -> Void
    
    @State private var selectedMedicines: Set<NSManagedObjectID>
    @Environment(\.dismiss) private var dismiss
    
    init(doctorName: String,
         primaryMedicine: Medicine,
         emailAddress: String?,
         baseMedicines: [Medicine],
         emailBuilder: @escaping ([Medicine]) -> String,
         onCopy: @escaping ([Medicine]) -> Void,
         onSend: @escaping ([Medicine]) -> Void) {
        self.doctorName = doctorName
        self.primaryMedicine = primaryMedicine
        self.emailAddress = emailAddress
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
                                onSend(selectedList)
                                dismiss()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.title3)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityLabel("Invia email")
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
}

private struct StockManagementView: View {
    @ObservedObject var viewModel: MedicineFormViewModel
    let medicine: Medicine
    let package: Package
    
    @FetchRequest private var logs: FetchedResults<Log>
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    init(medicine: Medicine, package: Package, viewModel: MedicineFormViewModel) {
        self.medicine = medicine
        self.package = package
        self.viewModel = viewModel
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "medicine == %@", medicine)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
        _logs = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        List {
            Section(header: Text("Disponibilità")) {
                SettingRow(
                    icon: "square.stack.3d",
                    title: "Unità residue",
                    value: stockValue,
                    subtitle: nil,
                    valueColor: stockColor,
                    showDisclosure: false
                )
                Button {
                    viewModel.saveForniture(medicine: medicine, package: package)
                } label: {
                    Label("Registra acquisto", systemImage: "cart.badge.plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            Section(header: Text("Storico movimenti")) {
                if logs.isEmpty {
                    Text("Nessun movimento registrato")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(logDescription(for: log))
                                .font(.subheadline)
                            Text(dateFormatter.string(from: log.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Gestione scorte")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var stockValue: String {
        let units = totalLeftover
        return units == 1 ? "1 unità" : "\(units) unità"
    }
    
    private var stockColor: Color {
        totalLeftover <= 0 ? .red : .primary
    }

    private var totalLeftover: Int {
        if let therapies = medicine.therapies, !therapies.isEmpty {
            return therapies.reduce(0) { total, therapy in
                total + Int(therapy.leftover())
            }
        }
        return medicine.remainingUnitsWithoutTherapy() ?? 0
    }
    
    private func logDescription(for log: Log) -> String {
        switch log.type {
        case "purchase":
            return "Acquisto"
        case "intake":
            return "Assunzione registrata"
        case "new_prescription":
            return "Nuova ricetta"
        case "new_prescription_request":
            return "Richiesta ricetta"
        default:
            return log.type.capitalized
        }
    }
}

private struct TherapiesManagementView: View {
    @Environment(\.managedObjectContext) private var context
    
    let medicine: Medicine
    let package: Package
    
    @FetchRequest private var therapies: FetchedResults<Therapy>
    
    @State private var showTherapySheet = false
    @State private var selectedTherapy: Therapy?
    
    private let recurrenceManager = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
    
    init(medicine: Medicine, package: Package) {
        self.medicine = medicine
        self.package = package
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        request.predicate = NSPredicate(format: "medicine == %@", medicine)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Therapy.start_date, ascending: true)]
        _therapies = FetchRequest(fetchRequest: request)
    }
    
    var body: some View {
        List {
            Section(header: Text("Terapie")) {
                if therapies.isEmpty {
                    Text("Nessuna terapia programmata")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(therapies, id: \.objectID) { therapy in
                        Button {
                            openTherapyForm(for: therapy)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(recurrenceDescription(for: therapy))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if let next = nextDose(for: therapy) {
                                        Text(formattedDate(next))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let personName = personName(for: therapy), !personName.isEmpty {
                                    Text(personName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Section {
                Button {
                    openTherapyForm(for: nil)
                } label: {
                    Label("Aggiungi terapia", systemImage: "plus.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Terapie attive")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTherapySheet) {
            TherapyFormView(
                medicine: medicine,
                package: package,
                context: context,
                editingTherapy: selectedTherapy
            )
            .id(selectedTherapy?.id ?? UUID())
            .presentationDetents([.medium, .large])
        }
    }
    
    private func openTherapyForm(for therapy: Therapy?) {
        selectedTherapy = therapy
        showTherapySheet = true
    }
    
    private func recurrenceDescription(for therapy: Therapy) -> String {
        let rule = recurrenceManager.parseRecurrenceString(therapy.rrule ?? "")
        let description = recurrenceManager.describeRecurrence(rule: rule)
        return description.capitalized
    }
    
    private func nextDose(for therapy: Therapy) -> Date? {
        recurrenceManager.nextOccurrence(
            rule: recurrenceManager.parseRecurrenceString(therapy.rrule ?? ""),
            startDate: therapy.start_date ?? Date(),
            after: Date(),
            doses: therapy.doses as NSSet?
        )
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
    
    private func personName(for therapy: Therapy) -> String? {
        let first = (therapy.person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (therapy.person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let components = [first, last].filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }
}
