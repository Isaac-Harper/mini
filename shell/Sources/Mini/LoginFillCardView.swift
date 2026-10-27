import AppKit

@MainActor
final class LoginFillCardView: NSGlassEffectView {
    let usernameField = NSTextField()
    let passwordField = NSSecureTextField()
    private let hostLabel = NSTextField(labelWithString: "")
    private let frameLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let fillButton = NSButton(title: "Fill", target: nil, action: nil)

    var onFill: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(frame: .zero)
        cornerRadius = 16
        translatesAutoresizingMaskIntoConstraints = false

        hostLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        hostLabel.lineBreakMode = .byTruncatingMiddle
        frameLabel.font = .systemFont(ofSize: 11)
        frameLabel.textColor = .secondaryLabelColor
        frameLabel.lineBreakMode = .byTruncatingMiddle

        usernameField.contentType = .username
        usernameField.placeholderString = "Username"
        usernameField.bezelStyle = .roundedBezel
        passwordField.contentType = .password
        passwordField.placeholderString = "Password"
        passwordField.bezelStyle = .roundedBezel

        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        fillButton.keyEquivalent = "\r"
        fillButton.target = self
        fillButton.action = #selector(fillPressed)

        let buttonRow = NSStackView(views: [NSView(), cancelButton, fillButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let titleStack = NSStackView(views: [hostLabel, frameLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 2
        let content = NSStackView(views: [titleStack, usernameField, passwordField, buttonRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false
        contentView = content
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: 320),
            usernameField.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            passwordField.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            buttonRow.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(host: String, embeddingHost: String?) {
        hostLabel.stringValue = host
        frameLabel.stringValue = embeddingHost.map { "in a frame on \($0)" } ?? ""
        frameLabel.isHidden = embeddingHost == nil
    }

    func clearFields() {
        usernameField.stringValue = ""
        passwordField.stringValue = ""
    }

    @objc private func fillPressed() {
        onFill?()
    }

    @objc private func cancelPressed() {
        onCancel?()
    }
}
