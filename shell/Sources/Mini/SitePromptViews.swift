import AppKit
import MiniRules
import SwiftUI

struct FaviconView: View {
    let image: NSImage?
    let size: CGFloat
    var tone: FaviconTone? = nil
    var fadesIn = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).transition(.opacity)
            } else {
                Image(systemName: "globe").resizable().foregroundStyle(.secondary).transition(.opacity)
            }
        }
        .animation(fadesIn ? .easeOut(duration: 0.15) : nil, value: image != nil)
        .frame(width: size, height: size)
        .background {
            if image != nil, let tone, tone.needsBackingPlate(on: colorScheme == .dark ? .dark : .light) {
                RoundedRectangle(cornerRadius: size / 4 + Self.plateInset, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
                    .opacity(plateOpacity)
                    .padding(-Self.plateInset)
            }
        }
    }

    private static let plateInset: CGFloat = 2

    private var plateOpacity: Double {
        let base = colorScheme == .dark ? 0.45 : 0.25
        return contrast == .increased || reduceTransparency ? min(1, base + 0.3) : base
    }
}

struct TabIconView: View {
    let tab: Tab
    let size: CGFloat

    var body: some View {
        if tab.isLoading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(size / 20)
                .frame(width: size, height: size)
        } else {
            FaviconView(image: tab.favicon, size: size, tone: tab.faviconTone, fadesIn: tab.faviconArrivedLive)
        }
    }
}

struct PermissionPromptView: View {
    let host: String
    let favicon: NSImage?
    let permissionNames: String
    let respond: (Bool) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                FaviconView(image: favicon, size: 18)
                Text("\(host) wants to use your \(permissionNames)")
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Don\u{2019}t Allow") { respond(false) }
                Button("Allow") { respond(true) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 360)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.return) {
            respond(true)
            return .handled
        }
        .onKeyPress(.escape) {
            respond(false)
            return .handled
        }
    }
}

struct AuthenticationPromptView: View {
    let host: String
    let realm: String
    let isProxy: Bool
    let favicon: NSImage?
    let respond: ((username: String, password: String)?) -> Void

    private enum Field {
        case username
        case password
    }

    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                FaviconView(image: favicon, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isProxy ? "The proxy \(host) requires a sign in" : "Sign in to \(host)")
                        .fontWeight(.semibold)
                    if !realm.isEmpty {
                        Text(realm).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .username)
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .password)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { respond(nil) }
                Button("Sign In") { respond((username, password)) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onSubmit { respond((username, password)) }
        .onExitCommand { respond(nil) }
        .task { focusedField = .username }
    }
}
