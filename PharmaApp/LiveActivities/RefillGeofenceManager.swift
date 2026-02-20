import Foundation
import CoreLocation
import MapKit

struct RefillPharmacyCandidate: Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Double
    let etaMinutes: Int
    let pharmacyHoursText: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
protocol RefillGeofenceManaging: AnyObject {
    var onCandidateEntered: ((RefillPharmacyCandidate) -> Void)? { get set }
    var onCandidatesUpdated: (() -> Void)? { get set }
    func start()
    func refreshMonitoring(hasPendingPurchases: Bool)
    func candidate(for pharmacyId: String) -> RefillPharmacyCandidate?
    func nearestCandidate() -> RefillPharmacyCandidate?
}

protocol RefillPharmacySearching {
    func searchPharmacies(around location: CLLocation) async -> [MKMapItem]
}

struct MapKitRefillPharmacySearchProvider: RefillPharmacySearching {
    func searchPharmacies(around location: CLLocation) async -> [MKMapItem] {
        await withCheckedContinuation { continuation in
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = "pharmacy"
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
            )

            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }

            MKLocalSearch(request: request).start { response, _ in
                continuation.resume(returning: response?.mapItems ?? [])
            }
        }
    }
}

@MainActor
final class RefillGeofenceManager: NSObject, @preconcurrency CLLocationManagerDelegate, RefillGeofenceManaging {
    static let regionRadius: CLLocationDistance = 50_000
    static let maxMonitoredRegions = 12

    var onCandidateEntered: ((RefillPharmacyCandidate) -> Void)?
    var onCandidatesUpdated: (() -> Void)?

    private let locationManager: CLLocationManager
    private let searchProvider: RefillPharmacySearching
    private let hoursResolver: RefillPharmacyHoursResolving
    private let clock: Clock
    private var hasPendingPurchases = false
    private var monitoredById: [String: RefillPharmacyCandidate] = [:]

    init(
        locationManager: CLLocationManager = CLLocationManager(),
        searchProvider: RefillPharmacySearching = MapKitRefillPharmacySearchProvider(),
        hoursResolver: RefillPharmacyHoursResolving = RefillPharmacyHoursResolver(),
        clock: Clock = SystemClock()
    ) {
        self.locationManager = locationManager
        self.searchProvider = searchProvider
        self.hoursResolver = hoursResolver
        self.clock = clock
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager.distanceFilter = 100
    }

    func start() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined || status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
        activateMonitoringIfAllowed()
    }

    func refreshMonitoring(hasPendingPurchases: Bool) {
        self.hasPendingPurchases = hasPendingPurchases
        if !hasPendingPurchases {
            stopAllRefillRegions()
            return
        }

        activateMonitoringIfAllowed()
        locationManager.requestLocation()
    }

    func candidate(for pharmacyId: String) -> RefillPharmacyCandidate? {
        monitoredById[pharmacyId]
    }

    func nearestCandidate() -> RefillPharmacyCandidate? {
        monitoredById.values.sorted(by: { $0.distanceMeters < $1.distanceMeters }).first
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        activateMonitoringIfAllowed()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let _ = error
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard hasPendingPurchases,
              let best = locations.last else {
            return
        }

        Task { [weak self] in
            await self?.recomputeMonitoredRegions(around: best)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let id = Self.pharmacyId(fromRegionIdentifier: region.identifier),
              let candidate = monitoredById[id] else {
            return
        }
        onCandidateEntered?(candidate)
    }

    private func activateMonitoringIfAllowed() {
        let status = locationManager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        locationManager.startMonitoringSignificantLocationChanges()
        if hasPendingPurchases {
            locationManager.requestLocation()
        }
    }

    private func recomputeMonitoredRegions(around location: CLLocation) async {
        let rawItems = await searchProvider.searchPharmacies(around: location)
        let now = clock.now()

        let ranked = rawItems
            .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                guard let mapLocation = item.placemark.location else { return nil }
                return (item, mapLocation.distance(from: location))
            }
            .sorted { $0.1 < $1.1 }

        var selected: [RefillPharmacyCandidate] = []
        for (item, distance) in ranked {
            guard selected.count < Self.maxMonitoredRegions else { break }
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { continue }
            let openInfo = hoursResolver.openInfo(forPharmacyName: name, now: now)
            let pharmacyHoursText: String
            if let openText = openInfo.closingTimeText, openInfo.isOpen {
                pharmacyHoursText = openText
            } else if let slotText = openInfo.slotText?.trimmingCharacters(in: .whitespacesAndNewlines), !slotText.isEmpty {
                pharmacyHoursText = "oggi \(slotText)"
            } else {
                pharmacyHoursText = "orari non disponibili"
            }

            let coordinate = item.placemark.coordinate
            let id = Self.makeStablePharmacyId(name: name, latitude: coordinate.latitude, longitude: coordinate.longitude)
            let eta = max(1, Int(round(distance / 83.0)))

            selected.append(
                RefillPharmacyCandidate(
                    id: id,
                    name: name,
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    distanceMeters: distance,
                    etaMinutes: eta,
                    pharmacyHoursText: pharmacyHoursText
                )
            )
        }

        applyMonitoredCandidates(selected)
        onCandidatesUpdated?()
    }

    private func applyMonitoredCandidates(_ candidates: [RefillPharmacyCandidate]) {
        let desiredById = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let desiredIds = Set(desiredById.keys)

        for region in locationManager.monitoredRegions {
            guard let id = Self.pharmacyId(fromRegionIdentifier: region.identifier) else { continue }
            if !desiredIds.contains(id) {
                locationManager.stopMonitoring(for: region)
            }
        }

        for candidate in candidates {
            let identifier = Self.regionIdentifier(for: candidate.id)
            let alreadyMonitored = locationManager.monitoredRegions.contains { $0.identifier == identifier }
            if alreadyMonitored { continue }

            let region = CLCircularRegion(
                center: candidate.coordinate,
                radius: Self.regionRadius,
                identifier: identifier
            )
            region.notifyOnEntry = true
            region.notifyOnExit = true
            locationManager.startMonitoring(for: region)
        }

        monitoredById = desiredById
    }

    private func stopAllRefillRegions() {
        for region in locationManager.monitoredRegions where Self.pharmacyId(fromRegionIdentifier: region.identifier) != nil {
            locationManager.stopMonitoring(for: region)
        }
        monitoredById.removeAll()
    }

    private static func regionIdentifier(for pharmacyId: String) -> String {
        "refill-pharmacy-\(pharmacyId)"
    }

    private static func pharmacyId(fromRegionIdentifier identifier: String) -> String? {
        let prefix = "refill-pharmacy-"
        guard identifier.hasPrefix(prefix) else { return nil }
        return String(identifier.dropFirst(prefix.count))
    }

    private static func makeStablePharmacyId(name: String, latitude: Double, longitude: Double) -> String {
        let roundedLatitude = (latitude * 10_000).rounded() / 10_000
        let roundedLongitude = (longitude * 10_000).rounded() / 10_000
        let base = "\(normalize(name))|\(roundedLatitude)|\(roundedLongitude)"

        var hash: UInt64 = 5381
        for byte in base.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}
