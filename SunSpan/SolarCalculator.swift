// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import Foundation

// MARK: - Models

struct DayLightInfo: Identifiable {
    let id: Int // day of year (1-366)
    let date: Date
    /// All times in minutes from midnight (local time). nil if event doesn't occur.
    let astronomicalDawn: Double?
    let nauticalDawn: Double?
    let civilDawn: Double?
    let sunrise: Double?
    let sunset: Double?
    let civilDusk: Double?
    let nauticalDusk: Double?
    let astronomicalDusk: Double?
    let solarNoon: Double?
    let dayLengthHours: Double
}

// MARK: - Solar Calculator (NOAA algorithm)

enum SolarCalculator {

    // MARK: - Public API

    static func calculateYear(year: Int, latitude: Double, longitude: Double, timeZone: TimeZone) -> [DayLightInfo] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        guard let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return []
        }

        let daysInYear = calendar.dateComponents([.day], from: startOfYear, to: startOfNextYear).day ?? 365

        return (0..<daysInYear).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startOfYear)!
            return calculateDay(date: date, dayOfYear: offset + 1, latitude: latitude, longitude: longitude, timeZone: timeZone)
        }
    }

    static func calculateDay(date: Date, dayOfYear: Int, latitude: Double, longitude: Double, timeZone: TimeZone) -> DayLightInfo {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let jd = julianDay(year: comps.year!, month: comps.month!, day: comps.day!)
        let tzOffset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0

        let sunrise = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 90.833, rising: true, tzOffset: tzOffset)
        let sunset = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 90.833, rising: false, tzOffset: tzOffset)
        let civilDawn = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 96.0, rising: true, tzOffset: tzOffset)
        let civilDusk = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 96.0, rising: false, tzOffset: tzOffset)
        let nautDawn = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 102.0, rising: true, tzOffset: tzOffset)
        let nautDusk = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 102.0, rising: false, tzOffset: tzOffset)
        let astroDawn = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 108.0, rising: true, tzOffset: tzOffset)
        let astroDusk = eventTime(jd: jd, latitude: latitude, longitude: longitude, zenith: 108.0, rising: false, tzOffset: tzOffset)
        let noon = solarNoon(jd: jd, longitude: longitude, tzOffset: tzOffset)

        let dayLength: Double
        if let sr = sunrise, let ss = sunset {
            dayLength = (ss - sr) / 60.0
        } else {
            // Polar day or polar night — use the same cosHA formulation as
            // hourAngle() so this decision agrees with the sunrise/sunset
            // pass. cosHA < −1 means the sun never descends to −0.833°
            // (true polar day); anything else, including boundary days
            // where the sun grazes the horizon at noon, is treated as
            // night so we don't paint a full daylight stripe on a day
            // with no event times.
            let noonUTC = noon - tzOffset * 60
            let jcNoon = julianCentury(jd: jd + noonUTC / 1440.0)
            let decl = sunDeclination(jc: jcNoon)
            let latRad = latitude * .pi / 180
            let declRad = decl * .pi / 180
            let zenRad = 90.833 * .pi / 180
            let cosHA = (cos(zenRad) / (cos(latRad) * cos(declRad))) - tan(latRad) * tan(declRad)
            dayLength = cosHA < -1 ? 24.0 : 0.0
        }

        return DayLightInfo(
            id: dayOfYear,
            date: date,
            astronomicalDawn: astroDawn,
            nauticalDawn: nautDawn,
            civilDawn: civilDawn,
            sunrise: sunrise,
            sunset: sunset,
            civilDusk: civilDusk,
            nauticalDusk: nautDusk,
            astronomicalDusk: astroDusk,
            solarNoon: noon,
            dayLengthHours: dayLength
        )
    }

    // MARK: - Core Astronomical Calculations

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year)
        var m = Double(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = floor(y / 100)
        let b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    private static func julianCentury(jd: Double) -> Double {
        (jd - 2451545.0) / 36525.0
    }

    private static func sunGeomMeanLong(jc: Double) -> Double {
        var l0 = 280.46646 + jc * (36000.76983 + 0.0003032 * jc)
        l0 = l0.truncatingRemainder(dividingBy: 360)
        if l0 < 0 { l0 += 360 }
        return l0
    }

    private static func sunGeomMeanAnomaly(jc: Double) -> Double {
        357.52911 + jc * (35999.05029 - 0.0001537 * jc)
    }

    private static func earthOrbitEccentricity(jc: Double) -> Double {
        0.016708634 - jc * (0.000042037 + 0.0000001267 * jc)
    }

    private static func sunEquationOfCenter(jc: Double) -> Double {
        let m = sunGeomMeanAnomaly(jc: jc) * .pi / 180
        return sin(m) * (1.914602 - jc * (0.004817 + 0.000014 * jc))
            + sin(2 * m) * (0.019993 - 0.000101 * jc)
            + sin(3 * m) * 0.000289
    }

    private static func sunApparentLong(jc: Double) -> Double {
        let trueLong = sunGeomMeanLong(jc: jc) + sunEquationOfCenter(jc: jc)
        let omega = 125.04 - 1934.136 * jc
        return trueLong - 0.00569 - 0.00478 * sin(omega * .pi / 180)
    }

    private static func obliquityCorrection(jc: Double) -> Double {
        let e0 = 23 + (26 + (21.448 - jc * (46.815 + jc * (0.00059 - jc * 0.001813))) / 60) / 60
        let omega = 125.04 - 1934.136 * jc
        return e0 + 0.00256 * cos(omega * .pi / 180)
    }

    private static func sunDeclination(jc: Double) -> Double {
        let e = obliquityCorrection(jc: jc) * .pi / 180
        let lambda = sunApparentLong(jc: jc) * .pi / 180
        return asin(sin(e) * sin(lambda)) * 180 / .pi
    }

    private static func equationOfTime(jc: Double) -> Double {
        let e = obliquityCorrection(jc: jc) * .pi / 180
        let l0 = sunGeomMeanLong(jc: jc) * .pi / 180
        let m = sunGeomMeanAnomaly(jc: jc) * .pi / 180
        let ecc = earthOrbitEccentricity(jc: jc)
        let y = tan(e / 2) * tan(e / 2)

        let eqTime = y * sin(2 * l0)
            - 2 * ecc * sin(m)
            + 4 * ecc * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * ecc * ecc * sin(2 * m)

        return eqTime * 4 * 180 / .pi
    }

    private static func hourAngle(latitude: Double, declination: Double, zenith: Double) -> Double? {
        let latRad = latitude * .pi / 180
        let declRad = declination * .pi / 180
        let zenRad = zenith * .pi / 180
        let cosHA = (cos(zenRad) / (cos(latRad) * cos(declRad))) - tan(latRad) * tan(declRad)
        if cosHA > 1 { return nil } // sun never reaches this zenith (polar night for this level)
        if cosHA < -1 {
            // Sun never goes below this zenith — smoothly extrapolate past 180°.
            // Near cosHA = -1, acos(x) ≈ π - √(2(1+x)), so extend as π + √(2(-1-x)).
            return (Double.pi + sqrt(2.0 * (-1.0 - cosHA))) * 180 / .pi
        }
        return acos(cosHA) * 180 / .pi
    }

    // MARK: - Event Time Computation (two-pass refinement)

    private static func eventTimeUTC(jd: Double, latitude: Double, longitude: Double, zenith: Double, rising: Bool) -> Double? {
        let jc = julianCentury(jd: jd)
        let eqTime = equationOfTime(jc: jc)
        let decl = sunDeclination(jc: jc)
        guard let ha = hourAngle(latitude: latitude, declination: decl, zenith: zenith) else { return nil }

        if rising {
            return 720 - 4 * (longitude + ha) - eqTime
        } else {
            return 720 - 4 * (longitude - ha) - eqTime
        }
    }

    private static func eventTime(jd: Double, latitude: Double, longitude: Double, zenith: Double, rising: Bool, tzOffset: Double) -> Double? {
        guard let utc1 = eventTimeUTC(jd: jd, latitude: latitude, longitude: longitude, zenith: zenith, rising: rising) else {
            return nil
        }
        // Second pass for improved accuracy
        let refinedJD = jd + utc1 / 1440.0
        guard let utc2 = eventTimeUTC(jd: refinedJD, latitude: latitude, longitude: longitude, zenith: zenith, rising: rising) else {
            return nil
        }
        return utc2 + tzOffset * 60
    }

    private static func solarNoon(jd: Double, longitude: Double, tzOffset: Double) -> Double {
        let jc = julianCentury(jd: jd)
        let eqTime = equationOfTime(jc: jc)
        var noon = 720 - 4 * longitude - eqTime + tzOffset * 60
        while noon < 0 { noon += 1440 }
        while noon >= 1440 { noon -= 1440 }
        return noon
    }
}
