import SwiftUI

struct WeatherRowView: View {
    let reading: WeatherReading
    let presenter: WeatherPopoverPresenter
    let action: () -> Void

    @State private var anchor = WeatherAnchor()

    private var condition: WeatherCondition { WeatherCondition.forCode(reading.code, isDay: reading.isDay) }

    var body: some View {
        Button {
            presenter.close()
            action()
        } label: {
            HStack(spacing: SidebarMetrics.iconSpacing) {
                Image(systemName: condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(InterfaceFont.rowSymbol)
                    .frame(width: SidebarMetrics.iconSize)
                Text(WeatherFormat.degrees(reading.temperature))
                    .foregroundStyle(.primary)
                Text("\(WeatherFormat.degrees(reading.high)) / \(WeatherFormat.degrees(reading.low))")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SidebarMetrics.footerRowPadding)
            .frame(height: SidebarMetrics.rowHeight)
            .hoverHighlight()
            .background { WeatherAnchorRepresentable(anchor: anchor) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { inside in
            guard let view = anchor.view else { return }
            presenter.rowHoverChanged(inside, anchor: view, reading: reading)
        }
    }
}

enum WeatherFormat {
    static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }
}

@MainActor
final class WeatherAnchor {
    weak var view: NSView?
}

final class WeatherAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct WeatherAnchorRepresentable: NSViewRepresentable {
    let anchor: WeatherAnchor

    func makeNSView(context: Context) -> WeatherAnchorView {
        let view = WeatherAnchorView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: WeatherAnchorView, context: Context) {
        anchor.view = nsView
    }
}
