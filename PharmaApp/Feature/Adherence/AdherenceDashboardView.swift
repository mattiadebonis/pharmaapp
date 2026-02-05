import SwiftUI
import CoreData
import Charts

struct AdherenceDashboardView: View {
    @FetchRequest(fetchRequest: Therapy.extractTherapies())
    private var therapies: FetchedResults<Therapy>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: true)],
        predicate: NSPredicate(format: "type == 'intake' OR type == 'intake_undo'")
    )
    private var logs: FetchedResults<Log>

    @StateObject private var viewModel = AdherenceDashboardViewModel()
    @State private var shareItem: ShareItem?
    @State private var showInfoSheet = false
    @State private var shareErrorMessage: String?
    @State private var showShareError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                periodSelector
                generalSection
                therapiesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: viewModel.selectedPeriod) { _ in reload() }
        .onChange(of: therapies.count) { _ in reload() }
        .onChange(of: logs.count) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: PersistenceController.shared.container.viewContext
        )) { _ in
            reload()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(isPresented: $showInfoSheet) {
            AdherenceInfoSheet()
        }
        .alert("Errore", isPresented: $showShareError) {
            Button("Ok", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "Impossibile generare il PDF.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aderenza")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Riepilogo generale e per terapia")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Condividi ↗︎") {
                shareReport()
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(viewModel.generalPlanned > 0 ? Color.accentColor : .secondary)
            .disabled(viewModel.generalPlanned == 0)

            Button {
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
            }
            .accessibilityLabel("Info")
        }
    }

    private var periodSelector: some View {
        Picker("Periodo", selection: $viewModel.selectedPeriod) {
            ForEach(AdherencePeriod.allCases) { period in
                Text(period.shortLabel).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aderenza generale")
                .font(.headline)
            GeneralAdherenceChart(series: viewModel.generalSeries)
                .frame(height: 180)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
            Text(viewModel.generalTrendLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var therapiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terapie")
                .font(.headline)
            if viewModel.therapies.isEmpty {
                emptyState
            } else {
                ForEach(viewModel.therapies) { summary in
                    TherapyCardRow(summary: summary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nessuna terapia attiva")
                .font(.subheadline.weight(.semibold))
            Text("Aggiungi una terapia per visualizzare l’aderenza.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func reload() {
        viewModel.reload(therapies: Array(therapies), logs: Array(logs))
    }

    private func shareReport() {
        let rows = viewModel.therapies.map { summary in
            ReportRow(
                name: summary.name,
                taken: summary.taken,
                planned: summary.planned,
                hasMeasurements: summary.hasMeasurements,
                note: summary.isSelfReported ? "Dati auto-registrati dall’utente" : nil
            )
        }

        let data = ReportData(
            generatedAt: Date(),
            period: viewModel.selectedPeriod,
            generalTaken: viewModel.generalTaken,
            generalPlanned: viewModel.generalPlanned,
            trendLabel: viewModel.generalTrendLabel,
            rows: rows
        )

        do {
            let url = try PdfReportBuilder().buildReport(data: data)
            shareItem = ShareItem(url: url)
        } catch {
            shareErrorMessage = error.localizedDescription
            showShareError = true
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct GeneralAdherenceChart: View {
    let series: [AdherencePoint]

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(series) { point in
                    BarMark(
                        x: .value("Periodo", point.date),
                        y: .value("Aderenza", point.value)
                    )
                    .foregroundStyle(Color.accentColor)
                    .cornerRadius(4)
                }
            }
            .chartYScale(domain: 0...1)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(Color.gray.opacity(0.2))
                    AxisValueLabel {
                        if let doubleValue = value.as(Double.self) {
                            Text("\(Int(doubleValue * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
        } else {
            Text("Grafico non disponibile")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TherapyCardRow: View {
    let summary: TherapySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(text: summary.statusLabel)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(adherenceText)
                        .font(.subheadline.weight(.semibold))
                    if summary.hasMeasurements {
                        ChipView(text: "Parametri")
                    }
                }
                Spacer()
                SparklineView(values: summary.adherenceSeries, overlayValues: summary.parameterSeries)
                    .frame(width: 110, height: 36)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }

    private var adherenceText: String {
        let planned = max(0, summary.planned)
        let taken = max(0, summary.taken)
        if planned == 0 {
            return "Aderenza —"
        }
        let percent = Int(round(Double(taken) / Double(planned) * 100))
        return "Aderenza \(taken)/\(planned) • \(percent)%"
    }
}

private struct StatusBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch text {
        case "In miglioramento": return Color.green
        case "Da supportare": return Color.orange
        default: return Color.gray
        }
    }
}

private struct ChipView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.blue)
    }
}

private struct SparklineView: View {
    let values: [Double]
    let overlayValues: [Double]?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                sparklinePath(in: proxy.size, values: values)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let overlayValues, !overlayValues.isEmpty {
                    sparklinePath(in: proxy.size, values: overlayValues)
                        .stroke(Color.pink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func sparklinePath(in size: CGSize, values: [Double]) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let clamped = values.map { min(1, max(0, $0)) }
        let step = size.width / CGFloat(max(clamped.count - 1, 1))

        for index in clamped.indices {
            let x = CGFloat(index) * step
            let y = size.height * (1 - CGFloat(clamped[index]))
            if index == clamped.startIndex {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}

private struct AdherenceInfoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aderenza")
                .font(.title2.weight(.semibold))
            Text("Questa schermata mostra l’aderenza alle terapie nel periodo selezionato. I dati provengono dalle assunzioni registrate e dai piani terapeutici attivi.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
    }
}
