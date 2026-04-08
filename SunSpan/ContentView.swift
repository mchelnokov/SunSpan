// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI
import CoreLocation

// MARK: - App State

@Observable
class AppState {
    var latitude: Double = 40.7128
    var longitude: Double = -74.0060
    var year: Int = Calendar.current.component(.year, from: Date())
    var selectedTimeZone: TimeZone = TimeZone(identifier: "America/New_York")!
    var locationName: String = "New York"

    var dayLightData: [DayLightInfo] = []
    let locationManager = LocationManager()
    /// Single shared geocoder. CoreLocation rate-limits calls; we cancel any
    /// in-flight request before starting a new one.
    let geocoder = CLGeocoder()
    private var didInitFromDevice = false

    init() {
        recalculate()
        locationManager.requestLocation()
    }

    func initFromDeviceLocationIfNeeded() {
        guard !didInitFromDevice, let location = locationManager.lastLocation else { return }
        didInitFromDevice = true

        // Only update state after geocoder returns, so coordinates and timezone are always consistent
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [self] placemarks, _ in
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            if let placemark = placemarks?.first {
                self.selectedTimeZone = placemark.timeZone ?? TimeZone.current
                self.locationName = AppState.formatPlacemarkName(placemark)
                    ?? String(localized: "Current Location")
            } else {
                self.selectedTimeZone = TimeZone.current
                self.locationName = String(localized: "Current Location")
            }
            self.recalculate()
        }
    }

    /// Format a placemark as "City, Region" when both are available and distinct,
    /// otherwise fall back to city, region, or country. `administrativeArea` returns
    /// the 2-letter state for US locations and a longer region name elsewhere.
    static func formatPlacemarkName(_ placemark: CLPlacemark) -> String? {
        let city = placemark.locality
        let region = placemark.administrativeArea
        if let city, let region, city != region {
            return "\(city), \(region)"
        }
        return city ?? region ?? placemark.country
    }

    func recalculate() {
        dayLightData = SolarCalculator.calculateYear(
            year: year,
            latitude: latitude,
            longitude: longitude,
            timeZone: selectedTimeZone
        )
    }
}

// MARK: - Content View

struct ContentView: View {
    @State private var state = AppState()
    @State private var showSettings = false
    @State private var flipAngle: Double = 0
    @State private var settingsOpenCounter: Int = 0

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // Back face: Settings
                SettingsView(
                    state: state,
                    openCounter: settingsOpenCounter,
                    onDone: flipToChart,
                    onCancel: flipToChartDiscardingChanges
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipAngle > 90 ? 1 : 0)

                // Front face: Chart
                ZStack {
                    DaylightChartView(
                        data: state.dayLightData,
                        year: state.year,
                        timeZone: state.selectedTimeZone
                    )
                    .ignoresSafeArea()

                    VStack(alignment: .trailing, spacing: 6) {
                        if !isLandscape {
                            HStack(spacing: 10) {
                                yearLabel
                                gearButton
                            }
                            .padding(.top, 8)
                            locationLabel
                        }
                        Spacer()
                        if isLandscape {
                            locationLabel
                            HStack(spacing: 10) {
                                yearLabel
                                gearButton
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(flipAngle < 90 ? 1 : 0)
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .onChange(of: state.locationManager.didResolve) {
            state.initFromDeviceLocationIfNeeded()
        }
    }

    private var yearLabel: some View {
        Text(verbatim: "\(state.year)")
            .font(.title)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 3)
    }

    private var locationLabel: some View {
        Text(state.locationName)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black, radius: 2)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var gearButton: some View {
        Button {
            flipToSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title)
                .foregroundStyle(.yellow)
                .shadow(color: .black, radius: 3)
        }
    }

    private func flipToSettings() {
        // Bump the counter so SettingsView re-syncs its drafts from the
        // latest AppState before becoming visible.
        settingsOpenCounter += 1
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 180
        }
        showSettings = true
    }

    func flipToChartDiscardingChanges() {
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 0
        }
        showSettings = false
    }

    func flipToChart() {
        state.recalculate()
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 0
        }
        showSettings = false
    }
}
