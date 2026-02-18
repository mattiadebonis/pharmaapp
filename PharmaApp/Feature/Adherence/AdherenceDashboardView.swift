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

    private enum StockLevel { case ok, low, critical, noData }

    // Shared per la heatmap grid
    private struct WeekPoint: Identifiable {
        let index: Int
        let label: String
        let taken: Int
        let planned: Int
        var adherence: Double { planned > 0 ? min(1, Double(taken) / Double(planned)) : -1 }
        var id: Int { index }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                widgetsRow

                // ADERENZA
                adherenceHeatmapSection
                routineStabilitySection
                weekdayChart
                timeSlotChart

                // SCORTE
                stockHeatmapSection
                EarlyRefillCard(count: viewModel.earlyRefillCount, total: viewModel.earlyRefillTotal, ratio: viewModel.earlyRefillRatio)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: therapies.count) { _ in reload() }
        .onChange(of: logs.count) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(
            for: .NSManagedObjectContextObjectsDidChange,
            object: PersistenceController.shared.container.viewContext
        )) { _ in
            reload()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Statistiche")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Panoramica delle tue terapie")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var widgetsRow: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                GaugeCard(
                    title: "Aderenza",
                    value: viewModel.adherencePercentage,
                    color: adherenceColor(viewModel.adherencePercentage)
                )
                GaugeCard(
                    title: "Puntualità",
                    value: viewModel.punctualityPercentage,
                    color: adherenceColor(viewModel.punctualityPercentage)
                )
            }
            RefillReadinessCard(summary: viewModel.stockSummary)
        }
    }

    // MARK: - Weekday Chart

    @available(iOS 16.0, *)
    private var weekdayBarChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aderenza per giorno")
                .font(.subheadline.weight(.semibold))

            Chart(viewModel.weekdayAdherence) { item in
                LineMark(
                    x: .value("Giorno", item.label),
                    y: .value("Aderenza", item.percentage)
                )
                .foregroundStyle(Color.blue.gradient)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Giorno", item.label),
                    y: .value("Aderenza", item.percentage)
                )
                .foregroundStyle(adherenceColor(item.percentage))
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var weekdayChart: some View {
        if !viewModel.weekdayAdherence.isEmpty {
            if #available(iOS 16.0, *) {
                weekdayBarChart
            }
        }
    }

    // MARK: - Time Slot Chart

    @available(iOS 16.0, *)
    private var timeSlotBarChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Puntualità per fascia oraria")
                .font(.subheadline.weight(.semibold))

            Chart(viewModel.timeSlotPunctuality) { item in
                LineMark(
                    x: .value("Fascia", item.label),
                    y: .value("Puntualità", item.percentage)
                )
                .foregroundStyle(Color.blue.gradient)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Fascia", item.label),
                    y: .value("Puntualità", item.percentage)
                )
                .foregroundStyle(item.percentage >= 0.8 ? Color.blue : item.percentage >= 0.5 ? Color.orange : Color.red)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel()
                        .font(.caption2)
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var timeSlotChart: some View {
        if !viewModel.timeSlotPunctuality.isEmpty {
            if #available(iOS 16.0, *) {
                timeSlotBarChart
            }
        }
    }

    // MARK: - Heatmap

    @ViewBuilder
    private var adherenceHeatmapSection: some View {
        if !viewModel.dayAdherence.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Calendario aderenza")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach([Color(.systemFill), Color.red.opacity(0.5), Color.orange, Color.green], id: \.self) { c in
                            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
                        }
                        Text("100%").font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }

                let weeks = heatmapWeeks
                HStack(alignment: .top, spacing: 3) {
                    VStack(spacing: 3) {
                        ForEach(["L", "M", "M", "G", "V", "S", "D"], id: \.self) { d in
                            Text(d)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 10, height: 10)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(weeks.indices, id: \.self) { wi in
                                VStack(spacing: 3) {
                                    ForEach(0..<7, id: \.self) { di in
                                        if let entry = weeks[wi][di] {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(heatmapColor(for: entry))
                                                .frame(width: 10, height: 10)
                                        } else {
                                            Color.clear.frame(width: 10, height: 10)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    private func heatmapColor(for day: DayAdherence) -> Color {
        let p = day.percentage
        if p < 0 { return Color(.systemFill) }
        if p == 0 { return Color.red.opacity(0.25) }
        if p < 0.5 { return Color.red.opacity(0.6) }
        if p < 0.8 { return Color.orange }
        return Color.green
    }

    private var heatmapWeeks: [[DayAdherence?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -90, to: today) else { return [] }

        var lookup: [Date: DayAdherence] = [:]
        for d in viewModel.dayAdherence {
            lookup[cal.startOfDay(for: d.date)] = d
        }

        let wd = cal.component(.weekday, from: start)
        let daysBack = wd == 2 ? 0 : wd == 1 ? 6 : wd - 2
        guard let firstMonday = cal.date(byAdding: .day, value: -daysBack, to: start) else { return [] }

        var weeks: [[DayAdherence?]] = []
        var weekStart = firstMonday
        while weekStart <= today {
            var week: [DayAdherence?] = []
            for i in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: i, to: weekStart) else { week.append(nil); continue }
                if day < start || day > today {
                    week.append(nil)
                } else {
                    week.append(lookup[day] ?? DayAdherence(date: day, taken: 0, planned: 0))
                }
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    // MARK: - Routine Stability

    @ViewBuilder
    private var routineStabilitySection: some View {
        let points = weeklyAdherencePoints
        if points.count >= 3 {
            if #available(iOS 16.0, *) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Stabilità della routine")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        let trend = routineTrendLabel(points)
                        Text(trend.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trend.color)
                    }
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Settimana", point.index),
                            y: .value("Aderenza", point.adherence)
                        )
                        .foregroundStyle(Color.blue.opacity(0.10).gradient)
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Settimana", point.index),
                            y: .value("Aderenza", point.adherence)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Settimana", point.index),
                            y: .value("Aderenza", point.adherence)
                        )
                        .foregroundStyle(adherenceColor(point.adherence >= 0 ? point.adherence : 0))
                        .symbolSize(30)
                    }
                    .chartYScale(domain: 0...1)
                    .chartYAxis {
                        AxisMarks(values: [0, 0.5, 1]) { value in
                            AxisGridLine().foregroundStyle(Color.primary.opacity(0.08))
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(Int(v * 100))%").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let i = value.as(Int.self), i < points.count {
                                    Text(points[i].label).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(height: 140)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }

    private var weeklyAdherencePoints: [WeekPoint] {
        let cal = Calendar.current
        var weekly: [String: (taken: Int, planned: Int, date: Date)] = [:]
        for d in viewModel.dayAdherence {
            let comps = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: d.date)
            let key = "\(comps.yearForWeekOfYear ?? 0)-\(String(format: "%02d", comps.weekOfYear ?? 0))"
            var prev = weekly[key] ?? (taken: 0, planned: 0, date: d.date)
            prev = (taken: prev.taken + d.taken, planned: prev.planned + d.planned, date: min(prev.date, d.date))
            weekly[key] = prev
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "d/M"
        return weekly.sorted { $0.key < $1.key }.suffix(12).enumerated().map { idx, pair in
            let label = formatter.string(from: pair.value.date)
            return WeekPoint(index: idx, label: label, taken: pair.value.taken, planned: pair.value.planned)
        }
    }

    private func routineTrendLabel(_ points: [WeekPoint]) -> (label: String, color: Color) {
        guard points.count >= 2 else { return ("—", .secondary) }
        let first = points.prefix(points.count / 2).compactMap { $0.adherence >= 0 ? $0.adherence : nil }
        let last  = points.suffix(points.count / 2).compactMap { $0.adherence >= 0 ? $0.adherence : nil }
        guard !first.isEmpty, !last.isEmpty else { return ("Stabile", .secondary) }
        let avgFirst = first.reduce(0, +) / Double(first.count)
        let avgLast  = last.reduce(0, +) / Double(last.count)
        let delta = avgLast - avgFirst
        if delta > 0.05  { return ("↑ In miglioramento", .green) }
        if delta < -0.05 { return ("↓ In calo", .red) }
        return ("→ Stabile", .blue)
    }

    // MARK: - Stock Heatmap (proiezione)

    @ViewBuilder
    private var stockHeatmapSection: some View {
        if !viewModel.medicineCoverages.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Proiezione scorte")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    let greenCount = stockGreenDaysThisMonth
                    Text("\(greenCount) giorni ok questo mese")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(greenCount > 20 ? Color.green : greenCount > 10 ? Color.orange : Color.red)
                }

                let grid = stockProjectionGrid
                HStack(alignment: .top, spacing: 3) {
                    VStack(spacing: 3) {
                        ForEach(["L", "M", "M", "G", "V", "S", "D"], id: \.self) { d in
                            Text(d)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 10, height: 10)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 3) {
                            ForEach(grid.indices, id: \.self) { wi in
                                VStack(spacing: 3) {
                                    ForEach(0..<7, id: \.self) { di in
                                        if let level = grid[wi][di] {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(stockLevelColor(level))
                                                .frame(width: 10, height: 10)
                                        } else {
                                            Color.clear.frame(width: 10, height: 10)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: 8, height: 8)
                        Text("Ok").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: 8, height: 8)
                        Text("Basse").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: 8, height: 8)
                        Text("Critiche").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 1))
        }
    }

    private var stockProjectionGrid: [[StockLevel?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = cal.component(.weekday, from: today)
        let daysBack = wd == 2 ? 0 : wd == 1 ? 6 : wd - 2
        guard let firstMonday = cal.date(byAdding: .day, value: -daysBack, to: today),
              let endDate = cal.date(byAdding: .day, value: 30, to: today) else { return [] }

        var weeks: [[StockLevel?]] = []
        var weekStart = firstMonday
        while weekStart <= endDate {
            var week: [StockLevel?] = []
            for i in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: i, to: weekStart) else {
                    week.append(nil); continue
                }
                if day < today || day > endDate {
                    week.append(nil)
                } else {
                    let d = cal.dateComponents([.day], from: today, to: day).day ?? 0
                    week.append(projectedStockLevel(daysFromNow: d))
                }
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .day, value: 7, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    private var stockGreenDaysThisMonth: Int {
        let cal = Calendar.current
        let today = Date()
        guard let range = cal.range(of: .day, in: .month, for: today) else { return 0 }
        let currentDay = cal.component(.day, from: today)
        let daysLeft = range.count - currentDay + 1
        return (0..<daysLeft).filter { projectedStockLevel(daysFromNow: $0) == .ok }.count
    }

    private func projectedStockLevel(daysFromNow: Int) -> StockLevel {
        let coverages = viewModel.medicineCoverages
        guard !coverages.isEmpty else { return .noData }
        var hasCritical = false
        var hasLow = false
        for cov in coverages {
            let remaining = cov.days - daysFromNow
            if remaining <= 0 { hasCritical = true }
            else if remaining <= cov.threshold { hasLow = true }
        }
        if hasCritical { return .critical }
        if hasLow { return .low }
        return .ok
    }

    private func stockLevelColor(_ level: StockLevel) -> Color {
        switch level {
        case .ok:       return .green
        case .low:      return .orange
        case .critical: return .red
        case .noData:   return Color(.systemFill)
        }
    }

    private func adherenceColor(_ value: Double) -> Color {
        if value >= 0.8 { return .green }
        if value >= 0.5 { return .orange }
        return .red
    }

    private func reload() {
        viewModel.reload(therapies: Array(therapies), logs: Array(logs))
    }
}

// MARK: - Gauge Card

struct GaugeCard: View {
    let title: String
    let value: Double
    let color: Color

    private var displayText: String {
        "\(Int(value * 100))%"
    }

    var body: some View {
        VStack(spacing: 6) {
            if #available(iOS 17.0, *) {
                sectorGauge
            } else {
                ringGauge
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    @available(iOS 17.0, *)
    private var sectorGauge: some View {
        ZStack {
            Chart {
                SectorMark(
                    angle: .value("Valore", min(value, 1.0)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(color)
                .cornerRadius(4)

                SectorMark(
                    angle: .value("Rimanente", max(1.0 - value, 0)),
                    innerRadius: .ratio(0.7),
                    angularInset: 2
                )
                .foregroundStyle(color.opacity(0.12))
                .cornerRadius(4)
            }
            .chartLegend(.hidden)

            Text(displayText)
                .font(.callout.bold())
                .foregroundStyle(.primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 10)
    }

    private var ringGauge: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 14)

            Circle()
                .trim(from: 0, to: CGFloat(min(value, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(displayText)
                .font(.callout.bold())
                .foregroundStyle(.primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 10)
    }
}

// MARK: - Stock Card

struct StockCard: View {
    let summary: StockSummary

    init(summary: StockSummary) {
        self.summary = summary
    }

    // Legacy init — call sites still passing old args compile without changes
    init(days: Int, hasData: Bool, color: Color) {
        self.summary = .empty
    }

    private var allOk: Bool { summary.notOkCount == 0 && summary.totalCount > 0 }
    private var noData: Bool { summary.totalCount == 0 }

    private var mainColor: Color {
        if noData { return .secondary }
        if allOk { return .green }
        if summary.minNotOkDays <= 0 { return .red }
        return .orange
    }

    private var icon: String {
        if noData || allOk { return "shippingbox.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var topText: String {
        if noData { return "—" }
        return "\(Int(summary.okPercentage * 100))%"
    }

    private var bottomLine: String? {
        guard !noData, summary.notOkCount > 0 else { return nil }
        let d = summary.minNotOkDays
        if d <= 0 { return "\(summary.notOkCount) esaurit\(summary.notOkCount == 1 ? "o" : "i")" }
        return "\(summary.notOkCount) < \(d)g"
    }

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(mainColor)

            Text(topText)
                .font(.callout.bold())
                .foregroundStyle(mainColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let line = bottomLine {
                Text(line)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 0)

            Text("Scorte")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Stock Wide Card

struct StockWideCard: View {
    let summary: StockSummary
    let medicineName: String
    let coverageDays: Int
    let threshold: Int

    private var noData: Bool { summary.totalCount == 0 }
    private var allOk: Bool { summary.notOkCount == 0 && summary.totalCount > 0 }

    private var accentColor: Color {
        if noData { return .secondary }
        if allOk { return .green }
        if coverageDays <= 0 { return .red }
        return .orange
    }

    private var icon: String {
        if noData || allOk { return "shippingbox.fill" }
        if coverageDays <= 0 { return "exclamationmark.triangle.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var headline: String {
        if noData { return "Nessun farmaco monitorato" }
        if allOk { return "Scorte sufficienti" }
        if coverageDays <= 0 { return medicineName.isEmpty ? "Farmaco esaurito" : medicineName }
        return medicineName.isEmpty ? "Scorte in esaurimento" : medicineName
    }

    private var detail: String? {
        if noData || allOk { return nil }
        if coverageDays <= 0 { return "Esaurito · \(summary.notOkCount) farmac\(summary.notOkCount == 1 ? "o" : "i") da riordinare" }
        return "\(coverageDays) giorni rimasti · \(summary.notOkCount) farmac\(summary.notOkCount == 1 ? "o" : "i") sotto soglia"
    }

    private var badge: String {
        if noData { return "—" }
        return "\(Int(summary.okPercentage * 100))% ok"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("Scorte farmaci")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(badge)
                .font(.callout.bold())
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Refill Readiness Card

struct RefillReadinessCard: View {
    let summary: StockSummary

    private var percentage: Double { summary.okPercentage }
    private var color: Color {
        if summary.totalCount == 0 { return .secondary }
        if percentage >= 0.8 { return .green }
        if percentage >= 0.5 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(min(percentage, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(summary.totalCount > 0 ? "\(Int(percentage * 100))%" : "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(summary.totalCount > 0 ? color : .secondary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Refill readiness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Label(
                    summary.totalCount > 0
                        ? "\(summary.okCount)/\(summary.totalCount) terapie protette"
                        : "Nessuna terapia monitorata",
                    systemImage: "shield.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.totalCount > 0 ? color : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                Text("Scorte sopra la soglia di sicurezza")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Early Refill Card

struct EarlyRefillCard: View {
    let count: Int
    let total: Int
    let ratio: Double

    private var color: Color {
        if total == 0 { return .secondary }
        if ratio >= 0.8 { return .green }
        if ratio >= 0.5 { return .orange }
        return .red
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: CGFloat(min(ratio, 1.0)))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(total > 0 ? "\(Int(ratio * 100))%" : "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(total > 0 ? color : .secondary)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text("Rifornimento anticipato")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(total > 0
                     ? "\(count) su \(total) riforniment\(total == 1 ? "o" : "i") anticipat\(total == 1 ? "o" : "i")"
                     : "Nessun rifornimento negli ultimi 30 giorni")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(total > 0 ? color : .secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Ultimi 30 giorni · stima")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Therapy Count Card

struct TherapyCountCard: View {
    let count: Int

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)

            Image(systemName: "shield.fill")
                .font(.system(size: 22))
                .foregroundStyle(count > 0 ? Color.blue : .secondary)

            Text("\(count)")
                .font(.callout.bold())
                .foregroundStyle(count > 0 ? Color.blue : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)

            Text("Terapie attive")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}
