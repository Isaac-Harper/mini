import AppKit
import MiniRules
import SwiftUI

struct GeneralSettingsPane: View {
    @Bindable var shell: ShellController
    @State private var isDefaultBrowser = DefaultBrowser.isDefault

    var body: some View {
        Form {
            Section {
                LabeledContent("Default browser") {
                    if isDefaultBrowser {
                        Text("Mini is your default browser")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Set as Default Browser") { DefaultBrowser.makeDefault() }
                    }
                }
            }
            Section {
                Toggle("Close the day automatically", isOn: $shell.closesDayAutomatically)
            } footer: {
                SettingsFootnote("At 4 AM, tabs you did not use the day before fold into a dated group at the end of the tab list. Groups are archived 12 hours later.")
            }
        }
        .settingsForm()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefaultBrowser = DefaultBrowser.isDefault
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            isDefaultBrowser = DefaultBrowser.isDefault
        }
    }
}

struct AppearanceSettingsPane: View {
    @Bindable var shell: ShellController

    private var interfaceSizeLevel: Binding<Int> {
        Binding(get: { InterfaceScale.shared.level }, set: { shell.setInterfaceSize($0) })
    }

    var body: some View {
        Form {
            Section {
                Picker("Interface size", selection: interfaceSizeLevel) {
                    ForEach(InterfaceSize.scales.indices, id: \.self) { level in
                        Text("\(Int((InterfaceSize.scales[level] * 100).rounded()))%").tag(level)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                SettingsFootnote("Scales the sidebar, command bar and overlays. Pages keep their own zoom.")
            }
            Section {
                Toggle("Evening tint", isOn: $shell.showsEveningTint)
            } footer: {
                SettingsFootnote("Warms the sidebar from sunset to sunrise.")
            }
        }
        .settingsForm()
    }
}

struct BrowsingSettingsPane: View {
    @Bindable var hoverPreloader: HoverPreloader

    var body: some View {
        Form {
            Section {
                Toggle("Preload on hover", isOn: $hoverPreloader.isEnabled)
            } footer: {
                SettingsFootnote("Fetches a link on the same site while the pointer rests on it, so it opens faster. Skipped in Low Power Mode and on expensive networks.")
            }
        }
        .settingsForm()
    }
}

struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsFormFit: ViewModifier {
    @State private var contentHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollDisabled(true)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            } action: { _, height in
                contentHeight = height
            }
            .frame(height: contentHeight > 0 ? contentHeight : nil)
    }
}

extension View {
    func settingsForm() -> some View {
        modifier(SettingsFormFit())
    }
}
