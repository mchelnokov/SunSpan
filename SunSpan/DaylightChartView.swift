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
    var dstEnabled: Bool = true

    // Selection is tracked as month+day so it survives year changes.
    // Feb 29 in a leap year renders as Mar 1 in non-leap via Calendar normalization.
    @State private var selectedMonth: Int = 1
    @State private var selectedDay: Int = 1
    @State private var didInitSelection = false
    @State private var bubbleSize: CGSize = CGSize(width: 180, height: 120)

    private var selectedIndex: Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = DateComponents(year: year, month: selectedMonth, day: selectedDay)
        guard let date = cal.date(from: comps),
              let doy = cal.ordinality(of: .day, in: .year, for: date) else {
            return 0
        }
        return doy - 1
    }

    private func setSelection(toDayIndex index: Int) {
        let cal = Calendar(identifier: .gregorian)
        guard let jan1 = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let target = cal.date(byAdding: .day, value: index, to: jan1) else {
            return
        }
        let md = cal.dateComponents([.month, .day], from: target)
        selectedMonth = md.month ?? 1
        selectedDay = md.day ?? 1
    }

    static let nightColor = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let nauticalColor = Color(red: 0.15, green: 0.25, blue: 0.42)
    static let civilColor = Color(red: 0.32, green: 0.52, blue: 0.74)
    static let dayColor = Color(red: 0.53, green: 0.81, blue: 0.98)

    private static let noAA = FillStyle(antialiased: false)

    var body: some View {
        GeometryReader { geo in
            let layout = ChartLayout(size: geo.size, dayCount: data.count)
            let shortEdge = min(geo.size.width, geo.size.height)
            let fontSize = max(13, min(shortEdge * 0.028, 26))
            let sizeKey = "\(year)|\(data.count)|\(Int(fontSize.rounded()))|\(Locale.current.identifier)|\(timeZone.identifier)|\(dstEnabled)"

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
                if dstEnabled, !data.isEmpty {
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

                // Selection highlight — thick anti-aliased bar, always visible.
                if selectedIndex >= 0, selectedIndex < data.count {
                    let (p1, p2) = layout.dayLine(at: selectedIndex)
                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)
                    let barWidth = max(5, min(fontSize * 0.4, 9))
                    context.stroke(path, with: .color(.yellow), lineWidth: barWidth)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = layout.dayIndex(at: value.location)
                        setSelection(toDayIndex: min(max(raw, 0), data.count - 1))
                    }
            )
            .overlay {
                if selectedIndex >= 0, selectedIndex < data.count {
                    dayInfoBubble(day: data[selectedIndex], layout: layout, in: geo.size, safeAreaInsets: geo.safeAreaInsets, fontSize: fontSize)
                }
            }
            .task(id: sizeKey) {
                bubbleSize = computeBubbleSize(fontSize: fontSize)
            }
            .onAppear {
                guard !didInitSelection else { return }
                let today = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: Date())
                selectedMonth = today.month ?? 1
                selectedDay = today.day ?? 1
                didInitSelection = true
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Info Bubble

    private func dayInfoBubble(day: DayLightInfo, layout: ChartLayout, in size: CGSize, safeAreaInsets: EdgeInsets, fontSize: CGFloat) -> some View {
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

        // Bubble dimensions are precomputed once from the widest possible content for this year
        // (see computeBubbleSize). Stable across days, balanced padding left and right.
        var bubbleWidth = bubbleSize.width
        var bubbleHeight = bubbleSize.height

        // Mirror the chart's label sizing so we can reserve space for the month/hour strips.
        let avgMonthSpan = layout.dayAxisLength / 12
        let labelFontSize = max(9, min(avgMonthSpan * 0.4, 20))
        let labelStrip = labelFontSize + 8

        // Usable region: inside safe area, and off the label strips so the bubble never
        // hides under the camera/notch or overlaps month/hour labels.
        var minX = safeAreaInsets.leading + 4
        var maxX = size.width - safeAreaInsets.trailing - 4
        var minY = safeAreaInsets.top + 4
        var maxY = size.height - safeAreaInsets.bottom - 4
        if layout.isLandscape {
            minY += labelStrip  // month labels along the top
            minX += labelStrip  // hour labels along the left
        } else {
            minX += labelStrip  // month labels along the left
            maxY -= labelStrip  // hour labels along the bottom
        }

        bubbleWidth = min(bubbleWidth, max(0, maxX - minX))
        bubbleHeight = min(bubbleHeight, max(0, maxY - minY))

        let dayMid = layout.dayPos(day.id - 1) + layout.dayStride / 2
        let fingerOffset: CGFloat = 30

        var x: CGFloat
        var y: CGFloat
        if layout.isLandscape {
            // Finger is along X axis. Put the bubble to the left of the finger only when the
            // selected day is past the horizontal midpoint; otherwise put it to the right.
            // Keeps the bubble well clear of whichever short edge holds the camera.
            if dayMid >= size.width / 2 {
                x = dayMid - bubbleWidth - fingerOffset
            } else {
                x = dayMid + fingerOffset
            }
            // Horizontal center axis at the center of the top half of the screen.
            y = size.height / 4 - bubbleHeight / 2
        } else {
            // Finger is along Y axis. Put the bubble above the finger only when the selected
            // day is past the vertical midpoint; otherwise put it below. This keeps the
            // bubble well clear of the top edge / camera even if clamping would technically
            // allow the "above" placement.
            // Vertical center axis at the center of the left half of the screen.
            x = size.width / 4 - bubbleWidth / 2
            if dayMid >= size.height / 2 {
                y = dayMid - bubbleHeight - fingerOffset
            } else {
                y = dayMid + fingerOffset
            }
        }

        x = min(max(x, minX), maxX - bubbleWidth)
        y = min(max(y, minY), maxY - bubbleHeight)

        return VStack(alignment: .leading, spacing: 6) {
            Text(dateStr)
                .fontWeight(.semibold)
            HStack(spacing: 6) {
                Image(systemName: "sunrise")
                Text(sunriseStr)
            }
            HStack(spacing: 6) {
                Image(systemName: "sunset")
                Text(sunsetStr)
            }
            HStack(spacing: 6) {
                Image(systemName: "sun.max")
                Text(dayLength)
            }
        }
        .font(.system(size: fontSize))
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: bubbleWidth, height: bubbleHeight, alignment: .topLeading)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .position(x: x + bubbleWidth / 2, y: y + bubbleHeight / 2)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.15), value: selectedIndex)
    }

    // MARK: - Bubble Size Precomputation

    /// Measures the widest possible bubble content for the current data set at the given font size.
    /// Called from `.task(id:)` whenever year/data/font/locale/timezone changes — not per frame.
    private func computeBubbleSize(fontSize: CGFloat) -> CGSize {
        let regular = UIFont.systemFont(ofSize: fontSize)
        let semibold = UIFont.systemFont(ofSize: fontSize, weight: .semibold)

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale.current
        timeFormatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "j:mm", options: 0, locale: Locale.current)

        func width(_ s: String, font: UIFont) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }

        func timeString(_ minutes: Double?) -> String {
            guard let m = minutes else { return "—" }
            var wrapped = Int(m) % 1440
            if wrapped < 0 { wrapped += 1440 }
            let h = wrapped / 60
            let mn = wrapped % 60
            var comps = DateComponents()
            comps.hour = h
            comps.minute = mn
            guard let date = Calendar.current.date(from: comps) else { return "—" }
            return timeFormatter.string(from: date)
        }

        var maxDate: CGFloat = 0
        var maxSunrise: CGFloat = 0
        var maxSunset: CGFloat = 0
        var maxDayLen: CGFloat = 0

        for day in data {
            maxDate = max(maxDate, width(formatter.string(from: day.date), font: semibold))
            maxSunrise = max(maxSunrise, width(timeString(day.sunrise), font: regular))
            maxSunset = max(maxSunset, width(timeString(day.sunset), font: regular))
            let dayLen = String(
                format: String(localized: "dayLength.format"),
                Int(day.dayLengthHours),
                Int(day.dayLengthHours.truncatingRemainder(dividingBy: 1) * 60)
            )
            maxDayLen = max(maxDayLen, width(dayLen, font: regular))
        }

        func iconWidth(_ name: String) -> CGFloat {
            let cfg = UIImage.SymbolConfiguration(pointSize: fontSize)
            return UIImage(systemName: name, withConfiguration: cfg)?.size.width ?? fontSize * 1.2
        }

        let sunriseIcon = iconWidth("sunrise")
        let sunsetIcon = iconWidth("sunset")
        let sunIcon = iconWidth("sun.max")

        let hSpacing: CGFloat = 6
        let row1 = maxDate
        let row2 = sunriseIcon + hSpacing + maxSunrise
        let row3 = sunsetIcon + hSpacing + maxSunset
        let row4 = sunIcon + hSpacing + maxDayLen

        let contentWidth = max(row1, row2, row3, row4)
        let lineHeight = regular.lineHeight
        let vSpacing: CGFloat = 6
        let contentHeight = lineHeight * 4 + vSpacing * 3

        let padding: CGFloat = 10
        return CGSize(
            width: ceil(contentWidth + padding * 2 + 2),
            height: ceil(contentHeight + padding * 2)
        )
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
