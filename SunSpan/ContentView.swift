// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI
import CoreLocation
import Combine

// MARK: - App State

class AppState: ObservableObject {
    private static let defaults = UserDefaults.standard
    private var cancellable: AnyCancellable?

    @Published var latitude: Double = defaults.object(forKey: "latitude") as? Double ?? 40.7128 {
        didSet { Self.defaults.set(latitude, forKey: "latitude") }
    }
    @Published var longitude: Double = defaults.object(forKey: "longitude") as? Double ?? -74.0060 {
        didSet { Self.defaults.set(longitude, forKey: "longitude") }
    }
    @Published var year: Int = Calendar.current.component(.year, from: Date())
    @Published var selectedTimeZone: TimeZone = {
        if let id = defaults.string(forKey: "timeZoneId"), let tz = TimeZone(identifier: id) { return tz }
        return TimeZone(identifier: "America/New_York")!
    }() {
        didSet { Self.defaults.set(selectedTimeZone.identifier, forKey: "timeZoneId") }
    }
    @Published var locationName: String = defaults.string(forKey: "locationName") ?? String(localized: "New York", comment: "Default location name shown before device location resolves") {
        didSet { Self.defaults.set(locationName, forKey: "locationName") }
    }
    @Published var dstEnabled: Bool = defaults.object(forKey: "dstEnabled") as? Bool ?? true {
        didSet { Self.defaults.set(dstEnabled, forKey: "dstEnabled") }
    }

    @Published var dayLightData: [DayLightInfo] = []
    let locationManager = LocationManager()
    /// Single shared geocoder. CoreLocation rate-limits calls; we cancel any
    /// in-flight request before starting a new one.
    let geocoder = CLGeocoder()
    private var didInitFromDevice = false

    init() {
        // Forward nested ObservableObject changes so SwiftUI sees them.
        cancellable = locationManager.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // If no saved location exists, resolve from device on first launch.
        // Otherwise use persisted values and skip device location.
        let hasSavedLocation = Self.defaults.object(forKey: "latitude") != nil
        if hasSavedLocation {
            didInitFromDevice = true
        } else {
            locationManager.requestLocation()
        }
        recalculate()
    }

    func initFromDeviceLocationIfNeeded() {
        guard !didInitFromDevice, let location = locationManager.lastLocation else { return }
        didInitFromDevice = true

        // Only update state after geocoder returns, so coordinates and timezone are always consistent
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [self] placemarks, _ in
            DispatchQueue.main.async {
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

    /// The timezone used for calculation: the real timezone when DST is on,
    /// or a fixed-offset clone (standard time) when DST is off.
    var effectiveTimeZone: TimeZone {
        if dstEnabled {
            return selectedTimeZone
        }
        // Use Jan 1 of the selected year to get the standard (non-DST) offset.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let standardOffset = selectedTimeZone.secondsFromGMT(for: jan1)
        return TimeZone(secondsFromGMT: standardOffset) ?? selectedTimeZone
    }

    func recalculate() {
        dayLightData = SolarCalculator.calculateYear(
            year: year,
            latitude: latitude,
            longitude: longitude,
            timeZone: effectiveTimeZone
        )
    }
}

// MARK: - Content View

enum BackFace {
    case settings
    case stats
}

func formatDMS(_ value: Double, isLat: Bool) -> String {
    let abs = abs(value)
    let deg = Int(abs)
    let minFull = (abs - Double(deg)) * 60
    let min = Int(minFull)
    let sec = Int((minFull - Double(min)) * 60)
    let dir: String
    if isLat {
        dir = value >= 0 ? String(localized: "N", comment: "Cardinal direction North") : String(localized: "S", comment: "Cardinal direction South")
    } else {
        dir = value >= 0 ? String(localized: "E", comment: "Cardinal direction East") : String(localized: "W", comment: "Cardinal direction West")
    }
    return "\(deg)\u{00B0}\(min)\u{2032}\(sec)\u{2033} \(dir)"
}

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var flipAngle: Double = 0
    @State private var settingsOpenCounter: Int = 0
    @State private var backFace: BackFace = .settings

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            ZStack {
                // Back face: Settings or Year Stats
                Group {
                    if backFace == .stats {
                        YearStatsView(state: state, onBack: flipToChartDiscardingChanges)
                    } else {
                        SettingsView(
                            state: state,
                            openCounter: settingsOpenCounter,
                            onDone: flipToChart,
                            onCancel: flipToChartDiscardingChanges
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(flipAngle > 90 ? 1 : 0)
                .allowsHitTesting(flipAngle > 90)

                // Front face: Chart
                ZStack {
                    DaylightChartView(
                        data: state.dayLightData,
                        year: state.year,
                        timeZone: state.effectiveTimeZone,
                        dstEnabled: state.dstEnabled
                    )

                    VStack(alignment: .trailing, spacing: 6) {
                        if !isLandscape {
                            gearButton
                                .padding(.top, 8)
                            yearControl
                            locationLabel
                            coordinatesLabel
                        }
                        Spacer()
                        if isLandscape {
                            coordinatesLabel
                            locationLabel
                            yearControl
                            gearButton
                                .padding(.bottom, 8)
                        }
                    }
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    statsButton
                        .padding(isLandscape ? .leading : .trailing, 14)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: isLandscape ? .bottomLeading : .bottomTrailing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .opacity(flipAngle < 90 ? 1 : 0)
                .allowsHitTesting(flipAngle < 90)
            }
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .onChange(of: state.locationManager.didResolve) { _ in
            state.initFromDeviceLocationIfNeeded()
        }
    }

    private var yearControl: some View {
        HStack(spacing: 2) {
            yearStepButton(systemName: "chevron.left") { state.year -= 1; state.recalculate() }
            Text(verbatim: "\(state.year)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
            yearStepButton(systemName: "chevron.right") { state.year += 1; state.recalculate() }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.6), radius: 3)
    }

    private func yearStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.yellow)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
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

    private var coordinatesLabel: some View {
        Text(verbatim: "\(formatDMS(state.latitude, isLat: true))  \(formatDMS(state.longitude, isLat: false))")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black, radius: 2)
            .lineLimit(1)
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

    private var statsButton: some View {
        Button {
            flipToStats()
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
                .shadow(color: .black, radius: 3)
        }
    }

    private func flipToSettings() {
        // Bump the counter so SettingsView re-syncs its drafts from the
        // latest AppState before becoming visible.
        settingsOpenCounter += 1
        backFace = .settings
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 180
        }
    }

    private func flipToStats() {
        backFace = .stats
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 180
        }
    }

    func flipToChartDiscardingChanges() {
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 0
        }
    }

    func flipToChart() {
        state.recalculate()
        withAnimation(.easeInOut(duration: 0.6)) {
            flipAngle = 0
        }
    }
}
