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
                ForEach(pharmacies) { pharmacy in
                    HStack {
                        Text(pharmacy.name)
                        Text("Aperta")
                            .foregroundColor(.green)
                        Spacer()
                        Button(action: {
                            openInMaps(pharmacy: pharmacy)
                        }) {
                            Text("5 min")
                                .foregroundColor(pastelBlue)
                        }
                    }
                }
            }
            .padding(30)
        }
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
