// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Location Manager

@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var lastLocation: CLLocation?
    var didResolve = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func requestLocation() {
        guard !didResolve else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            // The actual location request will be issued from
            // locationManagerDidChangeAuthorization once the user responds.
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !didResolve else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        lastLocation = location
        didResolve = true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silently fall back to default location
    }
}

// MARK: - Settings View

struct SettingsView: View {
    var state: AppState
    /// Incremented by the parent each time settings becomes visible, so
    /// drafts re-sync from the latest AppState (e.g. after a device-location
    /// resolution that happened while settings was closed).
    var openCounter: Int
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    // Draft state — edits stay local until the user taps Done.
    @State private var draftLatitude: Double = 0
    @State private var draftLongitude: Double = 0
    @State private var draftTimeZone: TimeZone = .current
    @State private var draftLocationName: String = ""
    @State private var draftYear: Int = 2025

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var pinCoordinate: CLLocationCoordinate2D?
    @State private var isResolving = false

    private static let dayColor = Color(red: 0.53, green: 0.81, blue: 0.98)
    private static let nightColor = Color(red: 0.02, green: 0.02, blue: 0.04)
    private static let cardBackground = Color.white.opacity(0.15)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.dayColor, Self.nightColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button("Cancel") { cancel() }
                    Spacer()
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    if isResolving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Button("Done") { commit() }
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                VStack(spacing: 16) {
                    locationCard
                        .frame(maxHeight: .infinity)
                    yearCard
                    infoFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear { syncDraftsFromState() }
        .onChange(of: openCounter) { syncDraftsFromState() }
    }

    private func syncDraftsFromState() {
        draftLatitude = state.latitude
        draftLongitude = state.longitude
        draftTimeZone = state.selectedTimeZone
        draftLocationName = state.locationName
        draftYear = state.year

        let coord = CLLocationCoordinate2D(latitude: draftLatitude, longitude: draftLongitude)
        pinCoordinate = coord
        mapPosition = .region(MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
        ))
    }

    private func commit() {
        state.latitude = draftLatitude
        state.longitude = draftLongitude
        state.selectedTimeZone = draftTimeZone
        state.locationName = draftLocationName
        state.year = draftYear
        onDone?()
    }

    private func cancel() {
        // Drop any in-flight geocoder so a late completion doesn't touch drafts.
        state.geocoder.cancelGeocode()
        isResolving = false
        // Reset drafts immediately so no stale edits linger in memory.
        syncDraftsFromState()
        onCancel?()
    }

    // MARK: - Location Card (Map)

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Location", systemImage: "location.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if isResolving {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                }
                Text(draftLocationName)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            TappableMapView(
                position: $mapPosition,
                pinCoordinate: pinCoordinate,
                pinTitle: draftLocationName,
                onCoordinateSelected: { coord in
                    applyCoordinate(coord)
                    withAnimation {
                        mapPosition = .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
                        ))
                    }
                }
            )
            .frame(minHeight: 220, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                Text("Tap the map to set location")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(.bottom, 8)
            }
        }
        .padding(16)
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func applyCoordinate(_ coordinate: CLLocationCoordinate2D) {
        pinCoordinate = coordinate
        draftLatitude = coordinate.latitude
        draftLongitude = coordinate.longitude
        // Clear the old name immediately so the pin/label don't briefly show
        // the previous location while geocoding is in flight.
        draftLocationName = ""

        isResolving = true
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        // Cancel any in-flight geocode so rapid taps don't pile up calls.
        state.geocoder.cancelGeocode()
        state.geocoder.reverseGeocodeLocation(location) { placemarks, _ in
            isResolving = false
            if let placemark = placemarks?.first {
                draftTimeZone = placemark.timeZone ?? TimeZone(secondsFromGMT: Int(round(coordinate.longitude / 15)) * 3600)!
                draftLocationName = AppState.formatPlacemarkName(placemark) ?? String(localized: "Custom")
            } else {
                draftTimeZone = TimeZone(secondsFromGMT: Int(round(coordinate.longitude / 15)) * 3600)!
                draftLocationName = String(localized: "Custom")
            }
        }
    }

    // MARK: - Year Card (Wheel)

    private var yearCard: some View {
        VStack(spacing: 8) {
            Label("Year", systemImage: "calendar")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Year", selection: $draftYear) {
                ForEach(1900...2100, id: \.self) { year in
                    Text(verbatim: "\(year)")
                        .foregroundStyle(.white)
                        .tag(year)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 120)
            .clipped()
        }
        .padding(16)
        .background(Self.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Info Footer

    private var infoFooter: some View {
        HStack(spacing: 12) {
            infoItem(formatDMS(draftLatitude, isLat: true))
            infoItem(formatDMS(draftLongitude, isLat: false))
            infoItem(utcOffsetString)
            infoItem(draftTimeZone.identifier.replacingOccurrences(of: "_", with: " "))
        }
        .frame(maxWidth: .infinity)
    }

    private func infoItem(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
    }

    private var utcOffsetString: String {
        let seconds = draftTimeZone.secondsFromGMT()
        let h = seconds / 3600
        let m = abs(seconds % 3600) / 60
        return String(format: "UTC%+d:%02d", h, m)
    }

    // MARK: - Helpers

    private func formatDMS(_ value: Double, isLat: Bool) -> String {
        let abs = abs(value)
        let deg = Int(abs)
        let minFull = (abs - Double(deg)) * 60
        let min = Int(minFull)
        let sec = Int((minFull - Double(min)) * 60)
        let dir = isLat ? (value >= 0 ? "N" : "S") : (value >= 0 ? "E" : "W")
        return "\(deg)\u{00B0}\(min)\u{2032}\(sec)\u{2033} \(dir)"
    }
}

// MARK: - Map with tap-to-place-pin

struct TappableMapView: UIViewRepresentable {
    @Binding var position: MapCameraPosition
    var pinCoordinate: CLLocationCoordinate2D?
    var pinTitle: String
    var onCoordinateSelected: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.mapType = .satellite
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tap)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        guard let pin = pinCoordinate else { return }

        let last = context.coordinator.lastAppliedCoordinate
        let coordChanged = last == nil
            || abs(last!.latitude - pin.latitude) > 0.0001
            || abs(last!.longitude - pin.longitude) > 0.0001
        let titleChanged = context.coordinator.lastAppliedTitle != pinTitle

        // Only touch annotations when something actually changed — avoids
        // churn (and associated MapKit/CoreLocation traffic) on each SwiftUI
        // re-render driven by @Observable state.
        if coordChanged || titleChanged {
            mapView.removeAnnotations(mapView.annotations)
            let annotation = MKPointAnnotation()
            annotation.coordinate = pin
            annotation.title = pinTitle
            mapView.addAnnotation(annotation)
            context.coordinator.lastAppliedTitle = pinTitle
        }

        if coordChanged {
            let region = MKCoordinateRegion(
                center: pin,
                span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
            )
            mapView.setRegion(region, animated: last != nil)
            context.coordinator.lastAppliedCoordinate = pin
        }
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TappableMapView
        var lastAppliedCoordinate: CLLocationCoordinate2D?
        var lastAppliedTitle: String?

        init(_ parent: TappableMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onCoordinateSelected(coordinate)
        }
    }
}
