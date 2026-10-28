import SwiftUI

struct WeatherRowView: View {
    let reading: WeatherReading
    let action: () -> Void

    @State private var isHovered = false

    private var condition: WeatherCondition { WeatherCondition.forCode(reading.code, isDay: reading.isDay) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 13))
                    .frame(width: 16)
                Text(degrees(reading.temperature))
                    .foregroundStyle(.primary)
                Text("\(degrees(reading.high)) / \(degrees(reading.low))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: SidebarMetrics.rowHeight)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous).fill(.fill.quaternary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help([condition.name, reading.place].compactMap { $0 }.joined(separator: ", "))
    }

    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}
