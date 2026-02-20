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
    @State private var selectedRange: StatisticsRange = .days

    private enum StockLevel { case ok, low, critical, noData }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                header
                rangePicker
                overallTrendSection
                // ADERENZA
                adherenceHeatmapSection
                weekdayChart
                timeSlotChart
                therapyMonitoringCorrelationSection
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 44)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: reload)
        .onChange(of: therapies.count) { _ in reload() }
        .onChange(of: logs.count) { _ in reload() }
        .onChange(of: selectedRange) { _ in reload() }
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
        }
    }

    private var rangePicker: some View {
        Picker("Intervallo", selection: $selectedRange) {
            ForEach(StatisticsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
    }

    @available(iOS 16.0, *)
    private var overallTrendChart: some View {
        let points = viewModel.overallTrend
        let adherencePoints = points.filter { $0.adherence >= 0 }
        let punctualityPoints = points.filter { $0.punctuality >= 0 }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Andamento generale")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Aderenza generale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(adherencePoints) { point in
                        LineMark(
                            x: .value("Data", point.date),
                            y: .value("Aderenza", point.adherence)
                        )
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.catmullRom)
                    }
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
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                if selectedRange == .days {
                                    Text(date, format: .dateTime.weekday(.narrow))
                                } else {
                                    Text(date, format: .dateTime.day().month(.abbreviated))
                                }
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Puntualita generale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Chart {
                    ForEach(punctualityPoints) { point in
                        LineMark(
                            x: .value("Data", point.date),
                            y: .value("Puntualita", point.punctuality)
                        )
                        .foregroundStyle(Color.green)
                        .interpolationMethod(.catmullRom)
                    }
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
                    AxisMarks(values: .automatic) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                if selectedRange == .days {
                                    Text(date, format: .dateTime.weekday(.narrow))
                                } else {
                                    Text(date, format: .dateTime.day().month(.abbreviated))
                                }
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var overallTrendSection: some View {
        if #available(iOS 16.0, *), !viewModel.overallTrend.isEmpty {
            overallTrendChart
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
        .padding(.vertical, 12)
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
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var timeSlotChart: some View {
        if !viewModel.timeSlotPunctuality.isEmpty {
            if #available(iOS 16.0, *) {
                timeSlotBarChart
            }
        }
    }

    // MARK: - Parameter/Adherence Correlation

    @ViewBuilder
    private var therapyMonitoringCorrelationSection: some View {
        if #available(iOS 16.0, *), let series = viewModel.therapyMonitoringCorrelation {
            let xDomain = parameterXDomain(for: series.parameterPoints)
            let xSpan   = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
            let adherenceInWindow = series.adherencePoints.filter { xDomain.contains($0.date) }
            let adherenceSource = adherenceInWindow.isEmpty ? series.adherencePoints : adherenceInWindow
            let yDomain = parameterDomain(for: series.parameterPoints)
            let isSmoothed = zip(series.parameterPoints, series.smoothedParameterPoints)
                .contains { abs($0.value - $1.value) > 0.0001 }
            let therapyTitle = camelCaseName(series.therapyTitle)

            VStack(alignment: .leading, spacing: 8) {
                Text("Correlazione \(therapyTitle) · \(series.parameterTitle)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                VStack(spacing: 0) {
                    // ── Grafico aderenza ──────────────────────────────────────
                    Chart {
                        ForEach(adherenceSource) { point in
                            LineMark(
                                x: .value("Data", point.date),
                                y: .value("Aderenza", point.value)
                            )
                            .foregroundStyle(Color.blue)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: adherenceDomain(for: adherenceSource))
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 90)

                    // ── Grafico parametro ─────────────────────────────────────
                    Chart {
                        if isSmoothed {
                            ForEach(series.parameterPoints) { point in
                                LineMark(
                                    x: .value("Data", point.date),
                                    y: .value("Parametro", point.value)
                                )
                                .foregroundStyle(Color.green.opacity(0.25))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .interpolationMethod(.linear)
                            }
                        }
                        ForEach(series.smoothedParameterPoints) { point in
                            LineMark(
                                x: .value("Data", point.date),
                                y: .value("Parametro", point.value)
                            )
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                        ForEach(series.parameterPoints) { point in
                            PointMark(
                                x: .value("Data", point.date),
                                y: .value("Parametro", point.value)
                            )
                            .foregroundStyle(isSmoothed ? Color.green.opacity(0.45) : Color.green.opacity(0.85))
                            .symbolSize(isSmoothed ? 14 : 22)
                        }
                    }
                    .chartXScale(domain: xDomain)
                    .chartYScale(domain: yDomain)
                    .chartYAxis(.hidden)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    if xSpan < 86400 * 2 {
                                        Text(date, format: .dateTime.hour().minute())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(date, format: .dateTime.day().month(.abbreviated))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 90)
                }

                // ── Legenda ───────────────────────────────────────────────────
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Capsule().fill(Color.blue).frame(width: 16, height: 3)
                        Text("Aderenza \(therapyTitle)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Capsule().fill(Color.green).frame(width: 16, height: 3)
                        let paramLabel = series.parameterTitle
                        Text(isSmoothed ? "\(paramLabel) · trend" : paramLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if isSmoothed {
                        HStack(spacing: 6) {
                            Capsule().fill(Color.green.opacity(0.35)).frame(width: 16, height: 2)
                            Text("dati grezzi")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let r = series.correlationCoefficient {
                        Text(String(format: "r = %.2f", r))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(correlationColor(r))
                    }
                }
            }
            .padding(.vertical, 12)
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
                        ForEach(adherenceHeatmapScale, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
                        }
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
            .padding(.vertical, 12)
        }
    }

    private var adherenceHeatmapScale: [Color] {
        [
            Color(.systemGray5),
            Color(red: 0.82, green: 0.94, blue: 0.82),
            Color(red: 0.48, green: 0.78, blue: 0.48),
            Color(red: 0.12, green: 0.54, blue: 0.22)
        ]
    }

    private func heatmapColor(for day: DayAdherence) -> Color {
        let p = day.percentage
        if p < 0 { return adherenceHeatmapScale[0] }
        if p < 0.5 { return adherenceHeatmapScale[1] }
        if p < 0.8 { return adherenceHeatmapScale[2] }
        return adherenceHeatmapScale[3]
    }

    private var heatmapWeeks: [[DayAdherence?]] {
        let cal = Calendar.current
        guard let firstDate = viewModel.dayAdherence.first?.date,
              let lastDate = viewModel.dayAdherence.last?.date else { return [] }
        let start = cal.startOfDay(for: firstDate)
        let end = cal.startOfDay(for: lastDate)

        var lookup: [Date: DayAdherence] = [:]
        for d in viewModel.dayAdherence {
            lookup[cal.startOfDay(for: d.date)] = d
        }

        let wd = cal.component(.weekday, from: start)
        let daysBack = wd == 2 ? 0 : wd == 1 ? 6 : wd - 2
        guard let firstMonday = cal.date(byAdding: .day, value: -daysBack, to: start) else { return [] }

        var weeks: [[DayAdherence?]] = []
        var weekStart = firstMonday
        while weekStart <= end {
            var week: [DayAdherence?] = []
            for i in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: i, to: weekStart) else { week.append(nil); continue }
                if day < start || day > end {
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
                .padding(.vertical, 12)
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
            .padding(.vertical, 12)
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

    /// Y-domain for the adherence chart.
    /// Uses a dynamic range with a minimum visible span of 40 pp so the line
    /// never looks completely flat when adherence is consistently high.
    @available(iOS 16.0, *)
    private func adherenceDomain(for points: [MonitoringCorrelationPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let minV = values.min(), let maxV = values.max() else { return 0...1 }
        let span = maxV - minV
        let minSpan = 0.40  // always show at least 40 percentage points
        if span < minSpan {
            let center = (minV + maxV) / 2.0
            let lo = max(0.0, center - minSpan / 2.0)
            let hi = min(1.0, lo + minSpan)
            return lo...hi
        }
        let pad = span * 0.15
        return max(0.0, minV - pad)...min(1.0, maxV + pad)
    }

    /// Y-domain for the parameter chart.
    /// Uses the 5th–95th percentile to resist outliers, then enforces a
    /// minimum visible span of 15% of the median so tiny real-world
    /// variations (e.g. 3 mmHg) don't appear as dramatic vertical spikes.
    @available(iOS 16.0, *)
    private func parameterDomain(for points: [MonitoringCorrelationPoint]) -> ClosedRange<Double> {
        let sorted = points.map(\.value).sorted()
        guard !sorted.isEmpty else { return 0...1 }
        let loIdx = max(0, Int(Double(sorted.count) * 0.05))
        let hiIdx = min(sorted.count - 1, Int(Double(sorted.count) * 0.95))
        var lo = sorted[loIdx]
        var hi = sorted[hiIdx]
        // Minimum clinically meaningful span: 15% of the median value (at least 1 unit)
        let median = sorted[sorted.count / 2]
        let minSpan = max(1.0, abs(median) * 0.15)
        if hi - lo < minSpan {
            let center = (lo + hi) / 2.0
            lo = center - minSpan / 2.0
            hi = center + minSpan / 2.0
        }
        let pad = (hi - lo) * 0.20
        return (lo - pad)...(hi + pad)
    }

    @available(iOS 16.0, *)
    private func parameterXDomain(for points: [MonitoringCorrelationPoint]) -> ClosedRange<Date> {
        let sortedDates = points.map(\.date).sorted()
        guard let first = sortedDates.first, let last = sortedDates.last else {
            let now = Date()
            return now...now
        }
        if first == last {
            // Single point: show a ±1-hour window so it renders as a dot, not a spike.
            return first.addingTimeInterval(-3600)...last.addingTimeInterval(3600)
        }
        // Pure proportional padding – no artificial day-minimum.
        // The domain therefore mirrors the actual data window, whether
        // it spans a few hours or several months.
        let span = last.timeIntervalSince(first)
        let padding = span * 0.10
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private func formatParameterValue(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }

    private func correlationColor(_ value: Double) -> Color {
        if value >= 0.45 { return .green }
        if value <= -0.45 { return .red }
        return .secondary
    }

    private func camelCaseName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        return trimmed.lowercased().localizedCapitalized
    }

    private func earlyRefillColor(_ value: Double) -> Color {
        if value >= 0.8 { return .green }
        if value >= 0.5 { return .orange }
        return .red
    }

    private func reload() {
        viewModel.reload(therapies: Array(therapies), logs: Array(logs), range: selectedRange)
    }

    private func summaryRingKPI(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(value, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 58, height: 58)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryKPI(title: String, value: String, detail: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Gauge Card

struct GaugeCard: View {
    let title: String
    let value: Double
    let color: Color
    private let gaugeHeight: CGFloat = 74

    private var displayText: String {
        "\(Int(value * 100))%"
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if #available(iOS 17.0, *) {
                    sectorGauge
                } else {
                    ringGauge
                }
            }
            .frame(height: gaugeHeight)

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

struct CabinetStockOkCard: View {
    let summary: StockSummary

    private var color: Color {
        if summary.totalCount == 0 { return .secondary }
        if summary.okPercentage >= 0.8 { return .green }
        if summary.okPercentage >= 0.5 { return .orange }
        return .red
    }

    private var percentageText: String {
        guard summary.totalCount > 0 else { return "—" }
        return "\(Int(summary.okPercentage * 100))%"
    }

    private var detailText: String {
        guard summary.totalCount > 0 else { return "Nessun farmaco monitorato" }
        return "\(summary.okCount)/\(summary.totalCount) in armadietto"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Farmaci con scorte ok")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(percentageText)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(detailText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
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
        HStack(spacing: 14) {
            Image(systemName: "shield")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(summary.totalCount > 0 ? color : .secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("Terapie protette dalle scorte")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(
                    summary.totalCount > 0
                        ? "\(summary.okCount)/\(summary.totalCount) \(summary.totalCount == 1 ? "terapia con scorte sufficienti" : "terapie con scorte sufficienti")"
                        : "Nessuna terapia monitorata"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(summary.totalCount > 0 ? color : .secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
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
        .padding(.vertical, 12)
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
