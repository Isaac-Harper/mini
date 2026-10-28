import AppKit
import SwiftUI

@MainActor
final class WeatherPopoverPresenter {
    private var popover: NSPopover?
    private var isOverRow = false
    private var isOverPopover = false
    private var generation = 0

    private static let openDelay: TimeInterval = 0.4
    private static let closeGrace: TimeInterval = 0.15

    func rowHoverChanged(_ inside: Bool, anchor: NSView, reading: WeatherReading) {
        isOverRow = inside
        generation += 1
        let current = generation
        guard inside else {
            scheduleCloseCheck()
            return
        }
        guard popover == nil, !reading.days.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openDelay) { [weak self, weak anchor] in
            MainActor.assumeIsolated {
                guard let self, let anchor, self.generation == current, self.isOverRow, self.popover == nil, anchor.window != nil else { return }
                self.show(reading, from: anchor)
            }
        }
    }

    func close() {
        generation += 1
        popover?.performClose(nil)
        popover = nil
        isOverPopover = false
    }

    private func show(_ reading: WeatherReading, from anchor: NSView) {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: WeatherWeekView(reading: reading) { [weak self] inside in
            self?.popoverHoverChanged(inside)
        })
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
        self.popover = popover
    }

    private func popoverHoverChanged(_ inside: Bool) {
        isOverPopover = inside
        generation += 1
        if !inside { scheduleCloseCheck() }
    }

    private func scheduleCloseCheck() {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeGrace) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, !self.isOverRow, !self.isOverPopover else { return }
                self.close()
            }
        }
    }
}

struct WeatherWeekView: View {
    let reading: WeatherReading
    let onHover: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var condition: WeatherCondition { WeatherCondition.forCode(reading.code, isDay: reading.isDay) }
    private var weekLow: Double { reading.days.map(\.low).min() ?? reading.low }
    private var weekHigh: Double { reading.days.map(\.high).max() ?? reading.high }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.place ?? "Weather")
                    .font(.system(size: 13, weight: .semibold))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(WeatherFormat.degrees(reading.temperature))
                        .font(.system(size: 26, weight: .light))
                    Text(condition.name)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(reading.days.enumerated()), id: \.element.id) { index, day in
                    GridRow {
                        Text(index == 0 ? "Today" : Self.weekday(day.date))
                            .frame(width: 44, alignment: .leading)
                        VStack(spacing: 0) {
                            Image(systemName: WeatherCondition.forCode(day.code, isDay: true).symbolName)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 14))
                                .shadow(color: .black.opacity(colorScheme == .light ? 0.35 : 0), radius: 1)
                            if let chance = day.precipitationProbability, chance >= 30 {
                                Text("\(chance)%")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .frame(width: 28)
                        Text(WeatherFormat.degrees(day.low))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                        WeatherRangeBar(low: day.low, high: day.high, weekLow: weekLow, weekHigh: weekHigh)
                            .frame(width: 96, height: 4)
                        Text(WeatherFormat.degrees(day.high))
                            .frame(width: 32, alignment: .leading)
                    }
                    .frame(minHeight: 24)
                }
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.75))
        .onHover(perform: onHover)
    }

    private static let inputFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static func weekday(_ date: String) -> String {
        guard let parsed = inputFormatter.date(from: date) else { preconditionFailure("Open-Meteo date \(date) is not yyyy-MM-dd") }
        return weekdayFormatter.string(from: parsed)
    }
}

private struct WeatherRangeBar: View {
    let low: Double
    let high: Double
    let weekLow: Double
    let weekHigh: Double

    var body: some View {
        GeometryReader { geometry in
            let span = max(weekHigh - weekLow, 1)
            let start = (low - weekLow) / span * geometry.size.width
            let end = (high - weekLow) / span * geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(end - start, geometry.size.height))
                    .offset(x: start)
            }
        }
    }
}
