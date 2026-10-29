import AppKit
import CMiniCore
import QuartzCore

extension ShellController {
    func registerSpacesWithEngine() {
        for space in spaces {
            registerWithEngine(space)
        }
        removeOrphanedSpaceDirectories()
        history.removeHistory(ofSpacesOtherThan: Set(spaces.map(\.id)))
    }

    private func registerWithEngine(_ space: Space) {
        if space.usesDefaultProfile {
            space.id.withCString { mini_space_create($0, nil) }
            return
        }
        let directory = Space.cacheDirectory(forSpace: space.id, rootCacheDirectory: rootCacheDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create space directory \(directory.path): \(error)")
        }
        space.id.withCString { identifier in directory.path.withCString { mini_space_create(identifier, $0) } }
    }

    private func removeOrphanedSpaceDirectories() {
        let spacesDirectory = rootCacheDirectory.appendingPathComponent("Spaces")
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: spacesDirectory.path) else { return }
        let liveIdentifiers = Set(spaces.filter { !$0.usesDefaultProfile }.map(\.id))
        for name in names where !liveIdentifiers.contains(name) {
            removeSpaceDirectory(spacesDirectory.appendingPathComponent(name))
        }
    }

    private func removeSpaceDirectory(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            NSLog("Mini: could not remove space directory %@: %@", directory.lastPathComponent, String(describing: error))
        }
    }

    func switchToSpace(_ space: Space) {
        guard space !== currentSpace else { return }
        precondition(spaces.contains { $0 === space }, "Switching to a space the shell does not hold")
        findBar.close(restoringWebFocus: false)
        loginFill.closeIfOpen()
        commandBar.close(restoringWebFocus: false)
        if let previous = store.selectedTab, previous.hasBrowser {
            mini_browser_set_focus(previous.id, false)
        }
        currentSpace = space
        applySpaceAccent()
        if let tab = store.selectedTab {
            tab.hostView.onWebViewAttached = { [weak self, weak tab] in
                guard let self, let tab else { return }
                self.focusIfAwaitingInitialFocus(tab)
            }
        }
        refreshDisplayedTabs()
        fadeInWebArea()
        sitePrompts.refresh()
        crashOverlay.refresh()
        if store.selectedTab != nil {
            focusSelectedWebContent()
        } else {
            window.makeFirstResponder(nil)
        }
        historyWindow?.reload()
        scheduleSessionSave()
    }

    private func fadeInWebArea() {
        let webAreaView = windowController.webAreaView
        webAreaView.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            webAreaView.animator().alphaValue = 1
        }
    }

    func switchToSpace(at index: Int) {
        guard spaces.indices.contains(index) else { return }
        switchToSpace(spaces[index])
    }

    @discardableResult
    func createSpace(name: String, symbol: String) -> Space {
        let space = Space(id: Space.newIdentifier(), name: name, symbol: symbol, color: SpaceColor.nextUnused(after: spaces.map(\.color)), usesDefaultProfile: false, identifiers: tabIdentifiers)
        space.store.observer = self
        registerWithEngine(space)
        spaces.append(space)
        switchToSpace(space)
        return space
    }

    func rename(_ space: Space, to name: String, symbol: String) {
        space.name = name
        space.symbol = symbol
        scheduleSessionSave()
    }

    func setColor(_ color: SpaceColor, of space: Space) {
        space.color = color
        if space === currentSpace { applySpaceAccent() }
        scheduleSessionSave()
    }

    func applySpaceAccent() {
        windowController.webAreaView.spaceAccent = currentSpace.color.accent
    }

    @objc func setCurrentSpaceColor(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String, let color = SpaceColor(rawValue: rawValue) else {
            preconditionFailure("Space color item without a color")
        }
        setColor(color, of: currentSpace)
    }

    func canDelete(_ space: Space) -> Bool {
        spaces.count > 1 && !space.usesDefaultProfile
    }

    func delete(_ space: Space) {
        precondition(canDelete(space), "Deleting a space that must stay")
        if space === currentSpace, let other = spaces.first(where: { $0 !== space }) {
            switchToSpace(other)
        }
        var closingIdentifiers = Set<MiniTabId>()
        for littleWindow in littleWindows.values where littleWindow.space === space {
            if littleWindow.tab.hasBrowser {
                closingIdentifiers.insert(littleWindow.tab.id)
            }
            littleWindow.close()
        }
        forgetTabUndo(for: space.store)
        closingIdentifiers.formUnion(space.store.removeAll().filter(\.hasBrowser).map(\.id))
        spaces.removeAll { $0 === space }
        pendingSpaceDeletions[space.id] = closingIdentifiers
        finishSpaceDeletionIfReady(space.id)
        scheduleSessionSave()
    }

    func browserFinishedClosing(_ identifier: MiniTabId) {
        for (spaceIdentifier, var remaining) in pendingSpaceDeletions where remaining.remove(identifier) != nil {
            pendingSpaceDeletions[spaceIdentifier] = remaining
            finishSpaceDeletionIfReady(spaceIdentifier)
        }
    }

    private func finishSpaceDeletionIfReady(_ spaceIdentifier: String) {
        guard let remaining = pendingSpaceDeletions[spaceIdentifier], remaining.isEmpty else { return }
        pendingSpaceDeletions[spaceIdentifier] = nil
        spaceIdentifier.withCString { mini_space_destroy($0) }
        history.removeHistory(ofSpace: spaceIdentifier)
        removeSpaceDirectory(Space.cacheDirectory(forSpace: spaceIdentifier, rootCacheDirectory: rootCacheDirectory))
    }

    @objc func newSpace(_ sender: Any?) {
        let symbol = Space.symbols.first { symbol in !spaces.contains { $0.symbol == symbol } } ?? "globe"
        presentSpaceSheet(title: "New Space", confirmTitle: "Create", name: "", symbol: symbol) { [weak self] name, symbol in
            self?.createSpace(name: name, symbol: symbol)
        }
    }

    @objc func renameCurrentSpace(_ sender: Any?) {
        let space = currentSpace
        presentSpaceSheet(title: "Rename Space", confirmTitle: "Rename", name: space.name, symbol: space.symbol) { [weak self] name, symbol in
            self?.rename(space, to: name, symbol: symbol)
        }
    }

    @objc func deleteCurrentSpace(_ sender: Any?) {
        confirmDeletion(of: currentSpace)
    }

    @objc func selectSpaceAtIndex(_ sender: NSMenuItem) {
        switchToSpace(at: sender.tag - 1)
    }

    func confirmDeletion(of space: Space) {
        guard canDelete(space) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \u{201C}\(space.name)\u{201D}?"
        alert.informativeText = "Its tabs close, and its cookies, logins and site data are removed from this Mac."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self, weak space] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let self, let space, self.spaces.contains(where: { $0 === space }) else { return }
                self.delete(space)
            }
        }
    }

    private func presentSpaceSheet(title: String, confirmTitle: String, name: String, symbol: String, completion: @escaping (String, String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        let nameField = NSTextField(string: name)
        nameField.placeholderString = "Name"
        let symbolButton = NSPopUpButton(frame: .zero, pullsDown: false)
        for symbolName in Space.symbols {
            symbolButton.addItem(withTitle: "")
            guard let item = symbolButton.lastItem else { preconditionFailure("Symbol menu lost its item") }
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: symbolName)
            item.representedObject = symbolName
        }
        symbolButton.selectItem(at: Space.symbols.firstIndex(of: symbol) ?? 0)
        let stack = NSStackView(views: [symbolButton, nameField])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 260, height: 26)
        nameField.widthAnchor.constraint(equalToConstant: 190).isActive = true
        alert.accessoryView = stack
        alert.window.initialFirstResponder = nameField
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                let trimmed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard response == .alertFirstButtonReturn, !trimmed.isEmpty,
                      let chosenSymbol = symbolButton.selectedItem?.representedObject as? String
                else { return }
                completion(trimmed, chosenSymbol)
            }
        }
    }
}
