// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI

// MARK: - Year Stats View

struct YearStatsView: View {
    @ObservedObject var state: AppState
    var onBack: (() -> Void)?

    private static let dayColor = Color(red: 0.53, green: 0.81, blue: 0.98)
    private static let nightColor = Color(red: 0.02, green: 0.02, blue: 0.04)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Self.dayColor, Self.nightColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button("Back") { onBack?() }
                    Spacer()
                    Text(verbatim: "\(state.year)")
                        .font(.title2)
                        .fontWeight(.bold)
                    Spacer()
                    // Invisible matching button keeps the title optically centered.
                    Button("Back") { }
                        .hidden()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Text(state.locationName)
                    .font(.body)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)

                Text(verbatim: "\(formatDMS(state.latitude, isLat: true))  \(formatDMS(state.longitude, isLat: false))")
                    .font(.body)
                    .foregroundStyle(.white)
                    .shadow(color: .black, radius: 2)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)

                statsTable
                    .padding(.horizontal, 20)
            }
        }
    }

    private var statsTable: some View {
        let stats = YearStats.compute(from: state.dayLightData)
        let rows = Self.buildRows(stats)
        let font = UIFont.preferredFont(forTextStyle: .subheadline)

        let labelWidth = rows.map { ($0.0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let valueWidth = rows.map {
            $0.1.components(separatedBy: "\n")
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
                .max() ?? 0
        }.max() ?? 0
        let gap: CGFloat = 12

        return GeometryReader { geo in
            let available = geo.size.width
            let fits = labelWidth + gap + valueWidth <= available
            let lw = fits ? labelWidth : (available - gap) / 2
            let vw = fits ? valueWidth : (available - gap) / 2

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: gap) {
                            Text(row.0)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: lw, alignment: .leading)
                            Text(row.1)
                                .foregroundStyle(.white)
                                .frame(width: vw, alignment: .leading)
                        }
                        .font(.subheadline)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            }
        }
    }

    private static func buildRows(_ stats: YearStats) -> [(String, String)] {
        let locale = Locale.current

        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = TimeZone(identifier: "UTC")!
        dateFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "MMMd", options: 0, locale: locale)

        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: locale)

        func dateStr(_ date: Date?) -> String {
            guard let date else { return "—" }
            return dateFormatter.string(from: date)
        }

        func timeStr(_ minutes: Double?) -> String {
            guard let m = minutes else { return "—" }
            var wrapped = Int(m) % 1440
            if wrapped < 0 { wrapped += 1440 }
            var comps = DateComponents()
            comps.hour = wrapped / 60
            comps.minute = wrapped % 60
            guard let date = Calendar.current.date(from: comps) else { return "—" }
            return timeFormatter.string(from: date)
        }

        func durationStr(hours: Double) -> String {
            let total = Int((hours * 60).rounded())
            return String(format: String(localized: "dayLength.format"), total / 60, total % 60)
        }

        let totalHours = stats.totalDaylightHours + stats.totalNightHours
        func durationWithPercent(_ hours: Double) -> String {
            guard totalHours > 0 else { return durationStr(hours: hours) }
            let pct = Int(((hours / totalHours) * 100).rounded())
            return "\(durationStr(hours: hours)) (\(pct)%)"
        }

        func timeRangeStr(_ info: DayLightInfo) -> String? {
            guard let sr = info.sunrise, let ss = info.sunset else { return nil }
            return "\(timeStr(sr)) – \(timeStr(ss))"
        }

        func timeAndDate(_ info: DayLightInfo?, minutes keyPath: KeyPath<DayLightInfo, Double?>) -> String {
            guard let info else { return "—" }
            return "\(timeStr(info[keyPath: keyPath]))\n\(dateStr(info.date))"
        }

        func dayRowValue(_ info: DayLightInfo?, hours: Double) -> String {
            guard let info else { return "—" }
            var parts = [durationStr(hours: hours), dateStr(info.date)]
            if let range = timeRangeStr(info) { parts.append(range) }
            return parts.joined(separator: "\n")
        }

        func polarRunValue(_ run: PolarRun) -> String {
            let startMin = max(0, min(1440, run.start.sunrise ?? 0))
            let endMin = max(0, min(1440, run.end.sunset ?? 1440))
            let totalMin: Double
            if run.count == 1 {
                totalMin = max(0, endMin - startMin)
            } else {
                totalMin = (1440 - startMin) + Double(run.count - 2) * 1440 + endMin
            }
            let dcf = DateComponentsFormatter()
            dcf.allowedUnits = [.day, .hour, .minute]
            dcf.unitsStyle = .abbreviated
            let duration = dcf.string(from: totalMin * 60) ?? "\(Int(totalMin / 1440))"
            return "\(duration)\n\(dateStr(run.start.date)) – \(dateStr(run.end.date))"
        }

        func equinoxRowValue(_ info: DayLightInfo?) -> String {
            guard let info else { return "—" }
            var parts = [dateStr(info.date)]
            if let range = timeRangeStr(info) { parts.append(range) }
            return parts.joined(separator: "\n")
        }

        var rows: [(String, String)] = []
        if stats.daysWithSunrise > 0 {
            rows.append((String(localized: "Days with sunrise"), "\(stats.daysWithSunrise)"))
        }
        if stats.daysWithoutSunrise > 0 {
            rows.append((String(localized: "Days without sunrise"), "\(stats.daysWithoutSunrise)"))
        }
        if stats.daysWithoutSunset > 0 {
            rows.append((String(localized: "Days without sunset"), "\(stats.daysWithoutSunset)"))
        }
        rows.append(contentsOf: [
            (String(localized: "Total daylight"), durationWithPercent(stats.totalDaylightHours)),
            (String(localized: "Total night"), durationWithPercent(stats.totalNightHours)),
            (String(localized: "Earliest sunrise"), timeAndDate(stats.earliestSunrise, minutes: \.sunrise)),
            (String(localized: "Latest sunrise"), timeAndDate(stats.latestSunrise, minutes: \.sunrise)),
            (String(localized: "Earliest sunset"), timeAndDate(stats.earliestSunset, minutes: \.sunset)),
            (String(localized: "Latest sunset"), timeAndDate(stats.latestSunset, minutes: \.sunset)),
        ])
        if let run = stats.longestPolarDayRun {
            rows.append((String(localized: "Longest day"), polarRunValue(run)))
        } else {
            rows.append((String(localized: "Longest day"), dayRowValue(stats.longestDay, hours: stats.longestDayHours)))
        }
        if stats.daysWithoutSunrise == 0 {
            rows.append((String(localized: "Shortest day"), dayRowValue(stats.shortestDay, hours: stats.shortestDayHours)))
        }
        rows.append(contentsOf: [
            (String(localized: "Average day length"), durationStr(hours: stats.averageDayLengthHours)),
            (String(localized: "Spring equinox"), equinoxRowValue(stats.springEquinox)),
            (String(localized: "Autumn equinox"), equinoxRowValue(stats.autumnEquinox)),
        ])

        return rows
    }
}

// MARK: - Year Stats Model

private struct DayStat {
    let info: DayLightInfo
    let clampedHours: Double
    /// True when the sun both rises and sets on this calendar day in local time.
    let isNormal: Bool
}

private struct PolarRun {
    let count: Int
    let start: DayLightInfo
    let end: DayLightInfo
}

private struct YearStats {
    let daysWithSunrise: Int
    let daysWithoutSunrise: Int
    let daysWithoutSunset: Int
    let totalDaylightHours: Double
    let totalNightHours: Double
    let earliestSunrise: DayLightInfo?
    let latestSunrise: DayLightInfo?
    let earliestSunset: DayLightInfo?
    let latestSunset: DayLightInfo?
    let longestDay: DayLightInfo?
    let longestDayHours: Double
    let shortestDay: DayLightInfo?
    let shortestDayHours: Double
    let averageDayLengthHours: Double
    let longestPolarDayRun: PolarRun?
    let springEquinox: DayLightInfo?
    let autumnEquinox: DayLightInfo?

    static func compute(from data: [DayLightInfo]) -> YearStats {
        // SolarCalculator extrapolates sunrise/sunset past 180° hour angle for
        // polar-day rendering, producing sunrise < 0, sunset > 1440, and
        // dayLength > 24 h. It also has a fallback that occasionally reports
        // dayLength == 24 on edge days when both events are nil. Normalise
        // everything here so the stats don't pick up those artefacts.
        let stats: [DayStat] = data.map { info in
            if let sr = info.sunrise, let ss = info.sunset, sr >= 0, ss <= 1440, ss > sr {
                // Sun rises and sets on this calendar day in local time.
                return DayStat(info: info, clampedHours: (ss - sr) / 60.0, isNormal: true)
            }
            if info.sunrise != nil || info.sunset != nil || info.dayLengthHours >= 24 {
                // Both events extrapolated past the day boundary → polar day.
                // Also covers the rare fallback case where both are nil but
                // dayLengthHours was set to 24 by SolarCalculator.
                return DayStat(info: info, clampedHours: 24, isNormal: false)
            }
            // Otherwise: polar night (sun never rises).
            return DayStat(info: info, clampedHours: 0, isNormal: false)
        }

        let dayCount = stats.count
        let polarDay = stats.filter { !$0.isNormal && $0.clampedHours >= 24 }.count
        let polarNight = stats.filter { !$0.isNormal && $0.clampedHours <= 0 }.count
        let normalDays = stats.filter { $0.isNormal }.count

        let totalDaylight = stats.reduce(0.0) { $0 + $1.clampedHours }
        let totalNight = Double(dayCount) * 24.0 - totalDaylight
        let average = dayCount > 0 ? totalDaylight / Double(dayCount) : 0

        // Earliest/latest sunrise and sunset only make sense on normal days,
        // where the time is an in-range wall-clock minute-of-day value.
        let normalInfos = stats.filter { $0.isNormal }.map { $0.info }
        let earliestRise = normalInfos.min { $0.sunrise! < $1.sunrise! }
        let latestRise = normalInfos.max { $0.sunrise! < $1.sunrise! }
        let earliestSet = normalInfos.min { $0.sunset! < $1.sunset! }
        let latestSet = normalInfos.max { $0.sunset! < $1.sunset! }

        let longest = stats.max { $0.clampedHours < $1.clampedHours }
        let shortest = stats.min { $0.clampedHours < $1.clampedHours }

        // Longest contiguous run of polar day within the year. Doesn't bridge
        // the year boundary, so southern-hemisphere polar day shows whichever
        // half (Jan–Feb or Nov–Dec) is longer.
        var bestStart = -1, bestLen = 0, curStart = -1, curLen = 0
        for (i, s) in stats.enumerated() {
            if !s.isNormal && s.clampedHours >= 24 {
                if curLen == 0 { curStart = i }
                curLen += 1
                if curLen > bestLen { bestLen = curLen; bestStart = curStart }
            } else {
                curLen = 0
            }
        }
        let polarRun: PolarRun? = bestLen > 0
            ? PolarRun(count: bestLen, start: stats[bestStart].info, end: stats[bestStart + bestLen - 1].info)
            : nil

        // Equinoxes: day closest to 12 h (clamped) in each half of the year.
        // Works in either hemisphere and doesn't require astronomical ephemeris.
        let mid = dayCount / 2
        let firstHalf = dayCount > 0 ? Array(stats[..<mid]) : []
        let secondHalf = dayCount > 0 ? Array(stats[mid...]) : []
        let spring = firstHalf.min { abs($0.clampedHours - 12) < abs($1.clampedHours - 12) }
        let autumn = secondHalf.min { abs($0.clampedHours - 12) < abs($1.clampedHours - 12) }

        return YearStats(
            daysWithSunrise: normalDays,
            daysWithoutSunrise: polarNight,
            daysWithoutSunset: polarDay,
            totalDaylightHours: totalDaylight,
            totalNightHours: totalNight,
            earliestSunrise: earliestRise,
            latestSunrise: latestRise,
            earliestSunset: earliestSet,
            latestSunset: latestSet,
            longestDay: longest?.info,
            longestDayHours: longest?.clampedHours ?? 0,
            shortestDay: shortest?.info,
            shortestDayHours: shortest?.clampedHours ?? 0,
            averageDayLengthHours: average,
            longestPolarDayRun: polarRun,
            springEquinox: spring?.info,
            autumnEquinox: autumn?.info
        )
    }
}
