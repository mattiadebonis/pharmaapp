//
//  PharmaciesIndex.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 12/12/24.
//


import SwiftUI
import MapKit

struct PharmaciesIndex: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1900), // Centro (es. Milano)
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05) // Zoom iniziale
    )
    // Aggiungi un array di farmacie con coordinate
    let pharmacies = [
        Pharmacy(name: "Farmacia Centrale", latitude: 45.4654, longitude: 9.1895),
        Pharmacy(name: "Farmacia Salus", latitude: 45.4665, longitude: 9.1918),
        Pharmacy(name: "Farmacia Esselunga", latitude: 45.4621, longitude: 9.1872)
    ]
    
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 0.2)
    let pastelBlueOpaco = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 0.2)
    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    
    var body: some View {
        VStack {
            Map(coordinateRegion: $region, annotationItems: pharmacies) { pharmacy in
                MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: pharmacy.latitude, longitude: pharmacy.longitude)) {
                    VStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title)
                        Text(pharmacy.name)
                            .font(.caption)
                            .padding(4)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
            }
            .frame(height: 200)
            

            VStack(spacing:10) {
                HStack{
                    Image(systemName: "cross")
                        .foregroundColor(pastelBlue)
                    Text("Farmacie").bold()
                    Spacer()
                }
                
                ForEach(pharmacies) { pharmacy in
                    HStack {
                        Text(pharmacy.name)
                        Spacer()
                        Button(action: {
                            openInMaps(pharmacy: pharmacy)
                        }) {
                            Image(systemName: "map")
                                .foregroundColor(pastelBlue)
                        }
                    }
                }
            }
            .padding(30)
        }
        .background(LinearGradient(gradient: Gradient(colors: [pastelBlueOpaco, .white]), startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: .gray.opacity(0.1), radius: 3, x: 0, y: 2)
    }

    // Funzione per aprire la posizione in Apple Maps
    private func openInMaps(pharmacy: Pharmacy) {
        let coordinate = CLLocationCoordinate2D(latitude: pharmacy.latitude, longitude: pharmacy.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = pharmacy.name
        mapItem.openInMaps()
    }
    }

    // Modello per rappresentare le farmacie
    struct Pharmacy: Identifiable {
        let id = UUID()
        let name: String
        let latitude: Double
        let longitude: Double
    }

    // Anteprima
    #Preview {
        PharmaciesIndex()
    }
/*
import SwiftUI
import MapKit

struct PharmaciesIndex: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: Pharmacie.extractPharmacies(), animation: .default)
    private var pharmacies: FetchedResults<Pharmacie>

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.0703, longitude: 7.6869),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )

    @State private var mapAnnotations: [PharmacyAnnotation] = []
    
    let pastelGreen = Color(red: 179/255, green: 207/255, blue: 190/255, opacity: 0.2)
    let pastelBlueOpaco = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 0.2)
    let pastelBlue = Color(red: 110/255, green: 153/255, blue: 184/255, opacity: 1.0)
    
    var body: some View {
        VStack {

            Map(coordinateRegion: $region, annotationItems: mapAnnotations) { pharmacy in
                MapAnnotation(coordinate: pharmacy.coordinate) {
                    VStack {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title)
                        Text(pharmacy.name)
                            .font(.caption)
                            .padding(4)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
            }.frame(height: 200)

            

            VStack(spacing:10) {
                HStack{
                    Image(systemName: "cross")
                        .foregroundColor(pastelBlue)
                    Text("Farmacie").bold()
                    Spacer()
                }
                
                ForEach(pharmacies) { pharmacy in
                    HStack {
                        Text(pharmacy.name)
                        Spacer()
                        Button(action: {
                            print("Ciao")
                        }) {
                            Image(systemName: "map")
                                .foregroundColor(pastelBlue)
                        }
                    }

                }
            }
            .padding(30)
        }
        .background(LinearGradient(gradient: Gradient(colors: [pastelBlueOpaco, .white]), startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 220/255, green: 220/255, blue: 220/255), lineWidth: 1)
        )
        .cornerRadius(16)
        .shadow(color: .gray.opacity(0.1), radius: 3, x: 0, y: 2)
    }

    private func updateMapRegion(annotations: [PharmacyAnnotation]) {
        guard !annotations.isEmpty else { return }
        let coordinates = annotations.map { $0.coordinate }
        let region = self.region(for: coordinates)
        self.region = region
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = 90.0
        var maxLat = -90.0
        var minLon = 180.0
        var maxLon = -180.0

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.1, longitudeDelta: (maxLon - minLon) * 1.1) // 10% più grande per un margine

        return MKCoordinateRegion(center: center, span: span)
    }
    
    private func loadAnnotations() {
        let geocoder = CLGeocoder()
        var newAnnotations: [PharmacyAnnotation] = []

        pharmacies.forEach { pharmacy in
            let address = pharmacy.address ?? "Unknown Address"
            geocoder.geocodeAddressString(address) { (placemarks, error) in
                if let coordinate = placemarks?.first?.location?.coordinate {
                    let annotation = PharmacyAnnotation(id: pharmacy.id, name: pharmacy.name ?? "Unknown", coordinate: coordinate)
                    newAnnotations.append(annotation)

                    // Una volta che tutte le farmacie sono state geocodate
                    if newAnnotations.count == pharmacies.count {
                        DispatchQueue.main.async {
                            self.mapAnnotations = newAnnotations
                            self.updateMapRegion(annotations: newAnnotations)
                        }
                    }
                }
            }
        }
    }
}

struct Pharmacy: Identifiable {
    let id: UUID
    let name: String
    let address: String
}

struct PharmacyAnnotation: Identifiable {
    let id: Int16
    let name: String
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    PharmaciesIndex()
}

*/