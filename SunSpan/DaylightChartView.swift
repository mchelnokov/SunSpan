// Copyright (c) 2026 SunSpan Contributors. MIT License — see LICENSE file.

import SwiftUI

// MARK: - Chart Layout (orientation-aware coordinate mapping)

struct ChartLayout {
    let isLandscape: Bool
    let size: CGSize
    let dayCount: Int

    init(size: CGSize, dayCount: Int) {
        self.size = size
        self.dayCount = max(dayCount, 1)
        self.isLandscape = size.width > size.height
    }

    var origin: CGPoint { .zero }
    var chartSize: CGSize { size }

    var dayAxisLength: CGFloat { isLandscape ? chartSize.width : chartSize.height }
    var timeAxisLength: CGFloat { isLandscape ? chartSize.height : chartSize.width }
    var dayStride: CGFloat { dayAxisLength / CGFloat(dayCount) }

    func dayPos(_ index: Int) -> CGFloat {
        let base = isLandscape ? origin.x : origin.y
        return base + CGFloat(index) * dayStride
    }

    func dayEndPos(_ index: Int) -> CGFloat {
        let base = isLandscape ? origin.x : origin.y
        return base + CGFloat(index + 1) * dayAxisLength / CGFloat(dayCount)
    }

    func timePos(_ minutes: Double) -> CGFloat {
        let base = isLandscape ? origin.y : origin.x
        return base + CGFloat(minutes / 1440.0) * timeAxisLength
    }

    func fullDayRect(_ day: Int) -> CGRect {
        let dStart = dayPos(day)
        let dSize = dayEndPos(day) - dStart + 1
        if isLandscape {
            return CGRect(x: dStart, y: 0, width: dSize, height: size.height)
        } else {
            return CGRect(x: 0, y: dStart, width: size.width, height: dSize)
        }
    }

    /// Start and end points of a linear gradient along the time axis, centered on a day rect.
    func gradientPoints(for rect: CGRect) -> (CGPoint, CGPoint) {
        if isLandscape {
            return (CGPoint(x: rect.midX, y: 0), CGPoint(x: rect.midX, y: size.height))
        } else {
            return (CGPoint(x: 0, y: rect.midY), CGPoint(x: size.width, y: rect.midY))
        }
    }

    func dayIndex(at point: CGPoint) -> Int {
        let base = isLandscape ? origin.x : origin.y
        let coord = isLandscape ? point.x : point.y
        return Int((coord - base) / dayStride)
    }

    func dayLine(at dayIndex: Int) -> (CGPoint, CGPoint) {
        let d = dayPos(dayIndex) + dayStride / 2
        if isLandscape {
            return (CGPoint(x: d, y: 0), CGPoint(x: d, y: size.height))
        } else {
            return (CGPoint(x: 0, y: d), CGPoint(x: size.width, y: d))
        }
    }

    func timeLine(at minutes: Double) -> (CGPoint, CGPoint) {
        let t = timePos(minutes)
        if isLandscape {
            return (CGPoint(x: 0, y: t), CGPoint(x: size.width, y: t))
        } else {
            return (CGPoint(x: t, y: 0), CGPoint(x: t, y: size.height))
        }
    }
}

// MARK: - Daylight Chart View

struct DaylightChartView: View {
    let data: [DayLightInfo]
    let year: Int
    let timeZone: TimeZone
    var onDaySelected: ((DayLightInfo) -> Void)?

    @State private var selectedIndex: Int?
    @State private var dragLocation: CGPoint = .zero

    static let nightColor = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let nauticalColor = Color(red: 0.15, green: 0.25, blue: 0.42)
    static let civilColor = Color(red: 0.32, green: 0.52, blue: 0.74)
    static let dayColor = Color(red: 0.53, green: 0.81, blue: 0.98)

    private static let noAA = FillStyle(antialiased: false)

    var body: some View {
        GeometryReader { geo in
            let layout = ChartLayout(size: geo.size, dayCount: data.count)

            Canvas { context, size in
                guard !data.isEmpty else { return }

                // Night background
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Self.nightColor), style: Self.noAA
                )

                // Day stripes with gradient
                for (index, day) in data.enumerated() {
                    drawDay(context: &context, day: day, index: index, layout: layout)
                }

                let avgMonthSpan = layout.dayAxisLength / 12
                let labelFontSize = max(9, min(avgMonthSpan * 0.4, 20))

                // Hour grid lines and labels (6 AM, noon, 6 PM)
                let hourColor = Color(red: 1, green: 1, blue: 0.5)
                let hourFormatter = DateFormatter()
                hourFormatter.locale = Locale.current
                hourFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current)
                let hourFontSize = labelFontSize
                for hour in [6, 12, 18] {
                    let (p1, p2) = layout.timeLine(at: Double(hour) * 60)
                    var gridPath = Path()
                    gridPath.move(to: p1)
                    gridPath.addLine(to: p2)
                    context.stroke(gridPath, with: .color(hourColor), lineWidth: 1)

                    // Label
                    var comps = DateComponents()
                    comps.hour = hour
                    comps.minute = 0
                    let refDate = Calendar.current.date(from: comps) ?? Date()
                    let label = hourFormatter.string(from: refDate)
                    let hourText = Text(label)
                        .font(.system(size: hourFontSize))
                        .foregroundColor(hourColor)
                    let resolved = context.resolve(hourText)
                    let textSize = resolved.measure(in: size)
                    let t = layout.timePos(Double(hour) * 60)
                    let point: CGPoint
                    if layout.isLandscape {
                        point = CGPoint(x: 2, y: t + 2)
                    } else {
                        point = CGPoint(x: t + 2, y: size.height - textSize.height - 2)
                    }
                    context.draw(resolved, at: point, anchor: .topLeading)
                }

                // DST-offset dashed hour lines
                // Shows where 6/12/18 standard time falls during DST periods
                if !data.isEmpty {
                    let standardOffset = timeZone.secondsFromGMT(for: data[0].date)
                    var dstRangeStart: Int?
                    var dstOffsetSeconds: Int = 0

                    for (i, day) in data.enumerated() {
                        let currentOffset = timeZone.secondsFromGMT(for: day.date)
                        let dstDelta = currentOffset - standardOffset
                        let isDST = dstDelta != 0

                        if isDST && dstRangeStart == nil {
                            dstRangeStart = i
                            dstOffsetSeconds = dstDelta
                        } else if !isDST && dstRangeStart != nil {
                            drawDSTLines(context: &context, layout: layout, from: dstRangeStart!, to: i - 1, dstOffsetSeconds: dstOffsetSeconds, hourColor: hourColor)
                            dstRangeStart = nil
                        }
                    }
                    if let start = dstRangeStart {
                        drawDSTLines(context: &context, layout: layout, from: start, to: data.count - 1, dstOffsetSeconds: dstOffsetSeconds, hourColor: hourColor)
                    }
                }

                // Month grid lines and labels
                let calendar = Calendar(identifier: .gregorian)
                let formatter = DateFormatter()
                formatter.locale = Locale.current
                let monthNames = formatter.shortMonthSymbols!
                var monthOffsets: [Int] = [] // day offset for 1st of each month
                var dayOffset = 0
                for month in 1...12 {
                    monthOffsets.append(dayOffset)
                    if month > 1 {
                        let d = layout.dayPos(dayOffset)
                        let lineRect: CGRect
                        if layout.isLandscape {
                            lineRect = CGRect(x: round(d), y: 0, width: 1, height: size.height)
                        } else {
                            lineRect = CGRect(x: 0, y: round(d), width: size.width, height: 1)
                        }
                        context.fill(Path(lineRect), with: .color(.white.opacity(0.6)), style: Self.noAA)
                    }
                    let dc = DateComponents(year: year, month: month)
                    if let date = calendar.date(from: dc),
                       let range = calendar.range(of: .day, in: .month, for: date) {
                        dayOffset += range.count
                    } else {
                        dayOffset += 30
                    }
                }
                monthOffsets.append(dayOffset) // end of last month

                // Month labels
                for month in 0..<12 {
                    let midDay = (monthOffsets[month] + monthOffsets[month + 1]) / 2
                    let midPos = layout.dayPos(midDay) + layout.dayStride / 2
                    let text = Text(monthNames[month])
                        .font(.system(size: labelFontSize))
                        .foregroundColor(.white)
                    let resolved = context.resolve(text)
                    let textSize = resolved.measure(in: size)
                    let point: CGPoint
                    if layout.isLandscape {
                        point = CGPoint(x: midPos - textSize.width / 2, y: 2)
                    } else {
                        point = CGPoint(x: 4, y: midPos - textSize.height / 2)
                    }
                    context.draw(resolved, at: point, anchor: .topLeading)
                }

                // Selection highlight
                if let idx = selectedIndex, idx >= 0, idx < data.count {
                    let (p1, p2) = layout.dayLine(at: idx)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    context.stroke(path, with: .color(.yellow), lineWidth: 3)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let idx = layout.dayIndex(at: value.location)
                        if idx >= 0 && idx < data.count {
                            selectedIndex = idx
                            dragLocation = value.location
                        }
                    }
                    .onEnded { _ in
                        if let idx = selectedIndex, idx >= 0, idx < data.count {
                            onDaySelected?(data[idx])
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            selectedIndex = nil
                        }
                    }
            )
            .overlay {
                if let idx = selectedIndex, idx >= 0, idx < data.count {
                    dayInfoBubble(day: data[idx], layout: layout, in: geo.size)
                }
            }
        }
    }

    // MARK: - Info Bubble

    private func dayInfoBubble(day: DayLightInfo, layout: ChartLayout, in size: CGSize) -> some View {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: Locale.current)

        let dateStr = formatter.string(from: day.date)

        func timeString(_ minutes: Double?) -> String {
            guard let m = minutes else { return "—" }
            var wrapped = Int(m) % 1440
            if wrapped < 0 { wrapped += 1440 }
            let h = wrapped / 60
            let min = wrapped % 60
            var comps = DateComponents()
            comps.hour = h
            comps.minute = min
            guard let date = Calendar.current.date(from: comps) else { return "—" }
            return timeFormatter.string(from: date)
        }

        let sunriseStr = timeString(day.sunrise)
        let sunsetStr = timeString(day.sunset)
        let dayLength = String(format: String(localized: "dayLength.format"), Int(day.dayLengthHours), Int(day.dayLengthHours.truncatingRemainder(dividingBy: 1) * 60))

        // Position the bubble near the selected day, offset above the finger
        let dayMid = layout.dayPos(day.id - 1) + layout.dayStride / 2
        let bubbleWidth: CGFloat = 160
        let bubbleHeight: CGFloat = 80
        let fingerOffset: CGFloat = 60
        let margin: CGFloat = 4

        let x: CGFloat
        let y: CGFloat
        if layout.isLandscape {
            // Finger is along X axis; offset bubble to the left of finger, flip to right if near leading edge
            if dayMid - bubbleWidth - fingerOffset > margin {
                x = dayMid - bubbleWidth - fingerOffset
            } else {
                x = dayMid + fingerOffset
            }
            y = min(max(size.height / 2 - bubbleHeight / 2, margin), size.height - bubbleHeight - margin)
        } else {
            // Finger is along Y axis; offset bubble above finger, flip below if near top edge
            x = size.width / 2 - bubbleWidth / 2
            if dayMid - bubbleHeight - fingerOffset > margin {
                y = dayMid - bubbleHeight - fingerOffset
            } else {
                y = dayMid + fingerOffset
            }
        }

        return VStack(alignment: .leading, spacing: 4) {
            Text(dateStr)
                .fontWeight(.semibold)
            HStack {
                Image(systemName: "sunrise")
                Text(sunriseStr)
                Spacer()
                Image(systemName: "sunset")
                Text(sunsetStr)
            }
            HStack {
                Image(systemName: "sun.max")
                Text(dayLength)
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: bubbleWidth)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .position(x: x + bubbleWidth / 2, y: y + bubbleHeight / 2)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: selectedIndex)
    }

    // MARK: - Day Stripe Rendering

    private func drawDay(context: inout GraphicsContext, day: DayLightInfo, index: Int, layout: ChartLayout) {
        let rect = layout.fullDayRect(index)

        // Polar day — sun never sets, fill with full day color.
        if day.dayLengthHours >= 24 {
            context.fill(Path(rect), with: .color(Self.dayColor), style: Self.noAA)
            return
        }

        // Build gradient stops only for twilight levels the sun actually
        // reaches. In polar regions inner events (sunrise, civil dawn, …)
        // drop out from the inside as the sun stays lower, and dawn/dusk
        // pairs always disappear together (same hour-angle calculation),
        // so the remaining stops are naturally symmetric. The brightest
        // color in the resulting gradient never exceeds what the sky
        // actually achieves on this day — e.g. when sunrise is nil but
        // civil dawn exists, the two civilColor stops form a flat plateau
        // through midday instead of a false dayColor band.
        //
        // Stop locations stay in minutes-from-midnight space normalized
        // by 1440. They may fall outside [0, 1] when twilight extends
        // past midnight at high latitudes; Core Graphics interpolates
        // the chart-edge color correctly in that case.

        func loc(_ v: Double) -> CGFloat { CGFloat(v / 1440.0) }

        var stops: [Gradient.Stop] = []
        if let v = day.astronomicalDawn { stops.append(.init(color: Self.nightColor,    location: loc(v))) }
        if let v = day.nauticalDawn     { stops.append(.init(color: Self.nauticalColor, location: loc(v))) }
        if let v = day.civilDawn        { stops.append(.init(color: Self.civilColor,    location: loc(v))) }
        if let v = day.sunrise          { stops.append(.init(color: Self.dayColor,      location: loc(v))) }
        if let v = day.sunset           { stops.append(.init(color: Self.dayColor,      location: loc(v))) }
        if let v = day.civilDusk        { stops.append(.init(color: Self.civilColor,    location: loc(v))) }
        if let v = day.nauticalDusk     { stops.append(.init(color: Self.nauticalColor, location: loc(v))) }
        if let v = day.astronomicalDusk { stops.append(.init(color: Self.nightColor,    location: loc(v))) }

        // No events at all — deep polar night — leave the black background.
        guard !stops.isEmpty else { return }

        let gradient = Gradient(stops: stops)
        let (startPt, endPt) = layout.gradientPoints(for: rect)

        context.fill(
            Path(rect),
            with: .linearGradient(gradient, startPoint: startPt, endPoint: endPt),
            style: Self.noAA
        )
    }

    // MARK: - DST Dashed Lines

    private func drawDSTLines(context: inout GraphicsContext, layout: ChartLayout, from: Int, to: Int, dstOffsetSeconds: Int, hourColor: Color) {
        let dstOffsetMinutes = Double(dstOffsetSeconds) / 60.0
        let dashStyle = StrokeStyle(lineWidth: 0.5, dash: [4, 4])

        for hour in [6, 12, 18] {
            let minutes = Double(hour) * 60.0 + dstOffsetMinutes
            guard minutes >= 0 && minutes <= 1440 else { continue }
            let t = layout.timePos(minutes)

            let dayStart = layout.dayPos(from)
            let dayEnd = layout.dayEndPos(to)

            var path = Path()
            if layout.isLandscape {
                path.move(to: CGPoint(x: dayStart, y: t))
                path.addLine(to: CGPoint(x: dayEnd, y: t))
            } else {
                path.move(to: CGPoint(x: t, y: dayStart))
                path.addLine(to: CGPoint(x: t, y: dayEnd))
            }
            context.stroke(path, with: .color(hourColor.opacity(0.5)), style: dashStyle)
        }
    }
}
