import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// Ricerca la farmacia più vicina e prova a stimarne lo stato di apertura usando sia MapKit che gli orari locali.
final class LocationSearchViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var region: MKCoordinateRegion?
    struct Pin: Identifiable {
        let id = UUID()
        let title: String
        let coordinate: CLLocationCoordinate2D
        let phone: String?
        let mapItem: MKMapItem?
    }
    @Published var pinItem: Pin?
    @Published var distanceString: String?
    @Published var distanceMeters: CLLocationDistance?
    @Published var todayOpeningText: String?
    @Published var closingTimeText: String?
    @Published var isLikelyOpen: Bool?

    private let manager = CLLocationManager()
    private let maxSearchSpanDelta: CLLocationDegrees = 5.0
    private var userLocation: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
    }

    func ensureStarted() {
        if CLLocationManager.authorizationStatus() == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if CLLocationManager.authorizationStatus() == .authorizedWhenInUse || CLLocationManager.authorizationStatus() == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        userLocation = loc
        manager.stopUpdatingLocation()
        searchNearestPharmacy(around: loc)
    }

    private func searchNearestPharmacy(
        around location: CLLocation,
        spanDelta: CLLocationDegrees = 0.05,
        fallback: MKMapItem? = nil,
        query: String = "pharmacy open now"
    ) {
        let isOpenQuery = query.lowercased().contains("open now")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self else { return }
            let rawItems = response?.mapItems ?? []
            let items = self.filtered(items: rawItems)
            guard !items.isEmpty else {
                let nextSpan = spanDelta * 1.8
                if nextSpan <= self.maxSearchSpanDelta {
                    self.searchNearestPharmacy(around: location, spanDelta: nextSpan, fallback: fallback, query: query)
                } else if let fallback {
                    self.applySelection(for: fallback, userLocation: location, assumedOpen: isOpenQuery)
                }
                return
            }

            let sorted = self.sorted(items, from: location)
            let updatedFallback = fallback ?? sorted.first
            if let nearest = sorted.first {
                let status = self.openingStatus(forName: nearest.name)
                let assumedOpen: Bool? = {
                    switch status {
                    case .open: return true
                    case .closed: return false
                    case .unknown: return isOpenQuery ? true : nil
                    }
                }()
                self.applySelection(for: nearest, userLocation: location, assumedOpen: assumedOpen)
                return
            }

            let nextSpan = spanDelta * 1.8
            if nextSpan <= self.maxSearchSpanDelta {
                self.searchNearestPharmacy(around: location, spanDelta: nextSpan, fallback: updatedFallback, query: query)
                return
            }

            if let bestFallback = updatedFallback {
                self.applySelection(for: bestFallback, userLocation: location, assumedOpen: isOpenQuery)
            }
        }
    }

    private func filtered(items: [MKMapItem]) -> [MKMapItem] {
        items.filter { item in
            if let category = item.pointOfInterestCategory, category != .pharmacy { return false }
            let name = (item.name ?? "")
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
            let banned = ["erboristeria", "parafarmacia", "vitamine", "vitamin", "tartarello"]
            guard !banned.contains(where: { name.contains($0) }) else { return false }
            return !name.contains("erboristeria")
                && !name.contains("parafarmacia")
                && !name.contains("vitamine")
                && !name.contains("vitamin")
        }
    }

    private func sorted(_ items: [MKMapItem], from location: CLLocation) -> [MKMapItem] {
        items.sorted { lhs, rhs in
            let lDistance = lhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
            let rDistance = rhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
            return lDistance < rDistance
        }
    }

    private func applySelection(for chosen: MKMapItem, userLocation location: CLLocation, assumedOpen: Bool?) {
        let coord = chosen.placemark.coordinate
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let effectiveOpen = assumedOpen ?? true
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(center: coord, span: span)
            let phone = chosen.phoneNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.pinItem = Pin(
                title: chosen.name ?? "Farmacia",
                coordinate: coord,
                phone: (phone?.isEmpty == true) ? nil : phone,
                mapItem: chosen
            )
            if let dist = chosen.placemark.location?.distance(from: location) {
                self.distanceMeters = dist
                self.distanceString = Self.format(distance: dist)
            }
            self.isLikelyOpen = effectiveOpen
            if let pharmacy = self.matchPharmacy(named: chosen.name ?? "") {
                self.applyOpeningInfo(for: pharmacy)
            } else {
                self.todayOpeningText = nil
                self.closingTimeText = nil
                self.isLikelyOpen = effectiveOpen
            }

            // Se la query era "open now" o non abbiamo dati, preferiamo mostrare aperta per evitare falsi negativi.
            if effectiveOpen, self.isLikelyOpen != true {
                self.isLikelyOpen = true
                self.closingTimeText = self.closingTimeText ?? "Aperta"
            }
        }
    }

    private func applyOpeningInfo(for pharmacy: PharmacyJSON) {
        let slot = rawTodaySlot(for: pharmacy)
        todayOpeningText = slot

        guard let slot else {
            closingTimeText = nil
            isLikelyOpen = isLikelyOpen
            return
        }
        let status = openingStatus(for: pharmacy, slot: slot)
        switch status {
        case .open:
            closingTimeText = "Aperta"
            isLikelyOpen = true
        case .closed:
            closingTimeText = nil
            isLikelyOpen = false
        case .unknown:
            closingTimeText = nil
            isLikelyOpen = isLikelyOpen
        }
    }

    func openInMaps() {
        guard let pin = pinItem else { return }
        if let item = pin.mapItem {
            item.openInMaps()
            return
        }
        let placemark = MKPlacemark(coordinate: pin.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = pin.title
        item.openInMaps()
    }

    func callPharmacy() {
        guard let raw = pinItem?.phone ?? pinItem?.mapItem?.phoneNumber else { return }
        let digits = raw.filter { "0123456789+".contains($0) }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        UIApplication.shared.open(url)
    }

    private static func format(distance: CLLocationDistance) -> String {
        // Stima semplice: 5 km/h a piedi (~83 m/min), 45 km/h in auto (~750 m/min)
        let walkingMinutes = max(1, Int(round(distance / 83.0)))
        let drivingMinutes = max(1, Int(round(distance / 750.0)))
        return "∼\(walkingMinutes) min a piedi · ∼\(drivingMinutes) min in auto"
    }

    // MARK: - Orari farmacia (da JSON locale)
    private struct PharmacyJSON: Decodable {
        let Nome: String
        let Orari: [DayJSON]?
    }
    private struct DayJSON: Decodable {
        let data: String
        let orario_apertura: String
    }

    private lazy var pharmacies: [PharmacyJSON] = {
        guard let url = Bundle.main.url(forResource: "farmacie", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([PharmacyJSON].self, from: data) else {
            return []
        }
        return list
    }()

    private func matchPharmacy(named name: String) -> PharmacyJSON? {
        let normalizedTarget = normalize(name)
        let targetTokens = tokenize(normalizedTarget)
        let scored = pharmacies.map { pharmacy -> (PharmacyJSON, Int) in
            let tokens = tokenize(normalize(pharmacy.Nome))
            return (pharmacy, scoreTokens(targetTokens, tokens))
        }
        let best = scored.max { $0.1 < $1.1 }
        if let best, best.1 > 0 { return best.0 }

        // Fallback: substring containment to catch slight naming differences.
        if let direct = pharmacies.first(where: { candidate in
            let norm = normalize(candidate.Nome)
            return norm.contains(normalizedTarget) || normalizedTarget.contains(norm)
        }) {
            return direct
        }
        return nil
    }

    private func rawTodaySlot(for pharmacy: PharmacyJSON) -> String? {
        let df = DateFormatter(); df.locale = Locale(identifier: "it_IT"); df.dateFormat = "EEEE"
        let weekday = df.string(from: Date()).lowercased()
        let dayOrari = pharmacy.Orari?.first(where: { day in
            normalize(day.data).hasPrefix(weekday)
        }) ?? pharmacy.Orari?.first
        return dayOrari?.orario_apertura
    }

    private func openingIntervalForString(_ text: String) -> (start: Date, end: Date)? {
        OpeningHoursParser.activeInterval(from: text)
    }

    private enum OpeningStatus {
        case open, closed, unknown
    }

    private func openingStatus(forName name: String?) -> OpeningStatus {
        guard let pharmacy = matchPharmacy(named: name ?? "") else { return .unknown }
        let slot = rawTodaySlot(for: pharmacy)
        return openingStatus(for: pharmacy, slot: slot ?? "")
    }

    private func openingStatus(for pharmacy: PharmacyJSON, slot: String) -> OpeningStatus {
        let intervals = OpeningHoursParser.intervals(from: slot)
        guard !intervals.isEmpty else { return .unknown }
        let now = Date()
        if intervals.contains(where: { now >= $0.start && now <= $0.end }) {
            return .open
        }
        return .closed
    }

    private func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let folded = lowered.folding(options: .diacriticInsensitive, locale: .current)
        let cleaned = folded
            .replacingOccurrences(of: "farmacia", with: "")
            .replacingOccurrences(of: "parafarmacia", with: "")
            .replacingOccurrences(of: "srl", with: "")
            .replacingOccurrences(of: "sas", with: "")
            .replacingOccurrences(of: "snc", with: "")
            .replacingOccurrences(of: "&", with: " ")
        let allowed = cleaned.filter { $0.isLetter || $0.isNumber || $0 == " " }
        return allowed.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenize(_ s: String) -> [String] {
        s.split(separator: " ").map { String($0) }.filter { $0.count >= 2 }
    }

    private func scoreTokens(_ target: [String], _ candidate: [String]) -> Int {
        let targetSet = Set(target)
        let candSet = Set(candidate)
        return targetSet.intersection(candSet).count
    }
}

// Parser per fasce orarie in formato "9:00-13:00 / 15:30-19:30" o separato da "e".
enum OpeningHoursParser {
    private static let separators: [Character] = ["-", "–", "—"]
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func segments(from text: String) -> [String] {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
            .replacingOccurrences(of: " e ", with: "/")
            .replacingOccurrences(of: " / ", with: "/")
        return cleaned
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func intervals(from text: String) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return segments(from: text)
            .compactMap { segment -> (Date, Date)? in
                guard let sep = separators.first(where: { segment.contains($0) }) else { return nil }
                let parts = segment
                    .split(separator: sep, maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard parts.count == 2,
                      let startTime = timeFormatter.date(from: parts[0]),
                      let endTime = timeFormatter.date(from: parts[1]) else { return nil }
                guard
                    let start = calendar.date(bySettingHour: calendar.component(.hour, from: startTime),
                                              minute: calendar.component(.minute, from: startTime),
                                              second: 0,
                                              of: today),
                    let end = calendar.date(bySettingHour: calendar.component(.hour, from: endTime),
                                            minute: calendar.component(.minute, from: endTime),
                                            second: 0,
                                            of: today)
                else { return nil }
                return (start, end)
            }
    }

    static func activeInterval(from text: String, now: Date = Date()) -> (start: Date, end: Date)? {
        intervals(from: text).first(where: { now >= $0.start && now <= $0.end })
    }

    static func nextInterval(from text: String, after now: Date = Date()) -> (start: Date, end: Date)? {
        intervals(from: text)
            .filter { now < $0.start }
            .sorted { $0.start < $1.start }
            .first
    }

    static func timeString(from date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func closingTimeString(from interval: (start: Date, end: Date)) -> String {
        timeFormatter.string(from: interval.end)
    }
}

@available(iOS 17.0, *)
struct MapItemDetailInlineView: View {
    let mapItem: MKMapItem

    var body: some View {
        MapItemDetailViewControllerRepresentable(mapItem: mapItem)
    }

    private struct MapItemDetailViewControllerRepresentable: UIViewControllerRepresentable {
        let mapItem: MKMapItem

        func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
            MKMapItemDetailViewController(mapItem: mapItem)
        }

        func updateUIViewController(_ uiViewController: MKMapItemDetailViewController, context: Context) {
            uiViewController.mapItem = mapItem
        }
    }
}
