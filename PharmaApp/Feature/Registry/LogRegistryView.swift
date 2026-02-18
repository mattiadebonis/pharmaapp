import SwiftUI
import CoreData

struct LogRegistryView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
        predicate: NSPredicate(format: "type == 'intake' OR type == 'purchase'")
    )
    private var allLogs: FetchedResults<Log>

    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    private var medicines: FetchedResults<Medicine>

    @FetchRequest(fetchRequest: Person.extractPersons())
    private var persons: FetchedResults<Person>

    @State private var filterMedicine: Medicine?
    @State private var filterPerson: Person?
    @State private var filterPeriod: FilterPeriod = .last30
    @State private var showFilters = false
    @State private var isExporting = false
    @State private var pdfURL: URL?
    @State private var showShareSheet = false

    enum FilterPeriod: String, CaseIterable, Identifiable {
        case last7 = "7 giorni"
        case last30 = "30 giorni"
        case last90 = "90 giorni"
        case all = "Tutto"

        var id: String { rawValue }

        var cutoffDate: Date? {
            switch self {
            case .last7: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .last30: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .last90: return Calendar.current.date(byAdding: .day, value: -90, to: Date())
            case .all: return nil
            }
        }
    }

    private var filteredLogs: [Log] {
        var result = Array(allLogs)

        if let medicine = filterMedicine {
            result = result.filter { $0.medicine == medicine }
        }

        if let person = filterPerson {
            result = result.filter { log in
                guard let therapy = log.therapy else { return false }
                return therapy.person == person
            }
        }

        if let cutoff = filterPeriod.cutoffDate {
            result = result.filter { $0.timestamp >= cutoff }
        }

        return result
    }

    private var groupedLogs: [(String, [Log])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .long
        formatter.timeStyle = .none

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredLogs) { log in
            calendar.startOfDay(for: log.timestamp)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (date, logs) in
                let label: String
                if calendar.isDateInToday(date) {
                    label = "Oggi"
                } else if calendar.isDateInYesterday(date) {
                    label = "Ieri"
                } else {
                    label = formatter.string(from: date)
                }
                let sorted = logs.sorted { $0.timestamp > $1.timestamp }
                return (label, sorted)
            }
    }

    private var hasActiveFilters: Bool {
        filterMedicine != nil || filterPerson != nil || filterPeriod != .last30
    }

    var body: some View {
        List {
            // MARK: Filtri
            if showFilters {
                filtersSection
            }

            // MARK: Log
            if filteredLogs.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Nessun registro")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(groupedLogs, id: \.0) { label, dayLogs in
                    Section(header: Text(label)) {
                        ForEach(dayLogs) { log in
                            logRow(log)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Registro")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { showFilters.toggle() }
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }

                    Button {
                        exportPDF()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = pdfURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Filters

    private var filtersSection: some View {
        Section(header: Text("Filtri")) {
            Picker("Farmaco", selection: $filterMedicine) {
                Text("Tutti").tag(nil as Medicine?)
                ForEach(medicines) { medicine in
                    Text(medicine.nome).tag(medicine as Medicine?)
                }
            }

            Picker("Persona", selection: $filterPerson) {
                Text("Tutte").tag(nil as Person?)
                ForEach(persons) { person in
                    Text(personDisplayName(for: person)).tag(person as Person?)
                }
            }

            Picker("Periodo", selection: $filterPeriod) {
                ForEach(FilterPeriod.allCases) { period in
                    Text(period.rawValue).tag(period)
                }
            }

            if hasActiveFilters {
                Button("Rimuovi filtri") {
                    filterMedicine = nil
                    filterPerson = nil
                    filterPeriod = .last30
                }
                .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Log Row

    private func logRow(_ log: Log) -> some View {
        HStack(spacing: 12) {
            Image(systemName: logIcon(for: log.type))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(logColor(for: log.type))
                .frame(width: 28, height: 28)
                .background(logColor(for: log.type).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(log.medicine.nome)
                    .font(.subheadline.weight(.medium))
                Text(logTypeLabel(for: log.type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(log.timestamp, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func logIcon(for type: String) -> String {
        switch type {
        case "intake": return "pill.fill"
        case "purchase": return "cart.fill"
        case "stock_adjustment": return "arrow.up.arrow.down"
        default: return "doc.text"
        }
    }

    private func logColor(for type: String) -> Color {
        switch type {
        case "intake": return .blue
        case "purchase": return .green
        case "stock_adjustment": return .orange
        default: return .secondary
        }
    }

    private func logTypeLabel(for type: String) -> String {
        switch type {
        case "intake": return "Assunzione"
        case "purchase": return "Acquisto"
        case "stock_adjustment": return "Aggiustamento scorte"
        default: return type.capitalized
        }
    }

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }

    // MARK: - PDF Export

    private func exportPDF() {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "it_IT")
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "it_IT")
        dayFormatter.dateStyle = .long
        dayFormatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "it_IT")
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short

        let data = renderer.pdfData { context in
            var yPos: CGFloat = 40
            let pageWidth: CGFloat = 595
            let leftMargin: CGFloat = 40
            let rightMargin: CGFloat = 40
            let usableWidth = pageWidth - leftMargin - rightMargin

            func newPageIfNeeded() {
                if yPos > 780 {
                    context.beginPage()
                    yPos = 40
                }
            }

            context.beginPage()

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black
            ]
            let title = "Registro Farmaci"
            (title as NSString).draw(at: CGPoint(x: leftMargin, y: yPos), withAttributes: titleAttrs)
            yPos += 32

            // Subtitle with date
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            let subtitle = "Esportato il \(dayFormatter.string(from: Date()))"
            (subtitle as NSString).draw(at: CGPoint(x: leftMargin, y: yPos), withAttributes: subtitleAttrs)
            yPos += 24

            // Filter info
            var filterParts: [String] = []
            if let med = filterMedicine { filterParts.append("Farmaco: \(med.nome)") }
            if let per = filterPerson { filterParts.append("Persona: \(personDisplayName(for: per))") }
            filterParts.append("Periodo: \(filterPeriod.rawValue)")
            let filterText = filterParts.joined(separator: " · ")
            (filterText as NSString).draw(at: CGPoint(x: leftMargin, y: yPos), withAttributes: subtitleAttrs)
            yPos += 20

            // Separator
            let separatorPath = UIBezierPath()
            separatorPath.move(to: CGPoint(x: leftMargin, y: yPos))
            separatorPath.addLine(to: CGPoint(x: leftMargin + usableWidth, y: yPos))
            UIColor.lightGray.setStroke()
            separatorPath.lineWidth = 0.5
            separatorPath.stroke()
            yPos += 16

            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]
            let rowAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray
            ]
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.gray
            ]

            for (label, dayLogs) in groupedLogs {
                newPageIfNeeded()

                (label as NSString).draw(at: CGPoint(x: leftMargin, y: yPos), withAttributes: headerAttrs)
                yPos += 22

                for log in dayLogs {
                    newPageIfNeeded()

                    let typeLabel = logTypeLabel(for: log.type)
                    let medicineName = log.medicine.nome
                    let text = "\(typeLabel) – \(medicineName)"
                    (text as NSString).draw(at: CGPoint(x: leftMargin + 12, y: yPos), withAttributes: rowAttrs)

                    let time = timeFormatter.string(from: log.timestamp)
                    let timeSize = (time as NSString).size(withAttributes: timeAttrs)
                    (time as NSString).draw(at: CGPoint(x: leftMargin + usableWidth - timeSize.width, y: yPos), withAttributes: timeAttrs)

                    yPos += 18
                }

                yPos += 8
            }
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Registro_\(dayFormatter.string(from: Date()).replacingOccurrences(of: " ", with: "_")).pdf"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            pdfURL = fileURL
            showShareSheet = true
        } catch {
            print("Errore esportazione PDF: \(error.localizedDescription)")
        }
    }
}

