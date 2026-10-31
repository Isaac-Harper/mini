import AppKit
import CMiniCore
import MiniRules
import SwiftUI

extension ShellController {
    func resetSiteSettings(_ site: StoredSite) {
        for origin in site.origins {
            sitePreferences.resetPermissions(forSiteAt: origin)
        }
        if site.allowsAds {
            sitePreferences.setAdBlockExempt(host: site.host, exempt: false)
        }
        if site.zoomLevel != nil {
            sitePreferences.setZoomLevel(nil, host: site.host)
            for tab in allSpaceTabs + littleWindows.values.map(\.tab) where tab.hasBrowser && SitePreferences.host(of: tab.url) == site.host {
                mini_browser_set_zoom_level(tab.id, 0)
            }
        }
    }
}

struct SitesSettingsPane: View {
    let shell: ShellController
    @State private var query = ""

    var body: some View {
        let sites = shell.sitePreferences.storedSites
        let shownSites = StoredSites.matching(sites, query: query)
        VStack(spacing: 0) {
            SiteSearchField(text: $query)
                .padding(.horizontal, 20)
                .padding(.top, 20)
            Form {
                Section {
                    if shownSites.isEmpty {
                        Text(sites.isEmpty ? "No sites have stored settings" : "No sites match \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    ForEach(shownSites) { site in
                        SiteSettingsRow(site: site, favicon: shell.faviconCache.image(forPageAt: site.origins.first ?? "https://\(site.host)")) {
                            shell.resetSiteSettings(site)
                        }
                    }
                } footer: {
                    SettingsFootnote("A site appears here once you answer one of its permission prompts, allow its ads or change its zoom. Reset forgets everything stored for it.")
                }
            }
            .formStyle(.grouped)
        }
        .frame(height: SettingsMetrics.sitesHeight)
    }
}

private struct SiteSettingsRow: View {
    let site: StoredSite
    let favicon: NSImage?
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(image: favicon, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.host)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(site.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Reset", action: reset)
        }
    }
}

private struct SiteSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search sites"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
