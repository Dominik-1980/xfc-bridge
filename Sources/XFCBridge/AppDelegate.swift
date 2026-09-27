import AppKit
import OSLog

struct AccessibilityRelaunchGate {
    private(set) var isWaitingForGrant = false

    mutating func configureAtLaunch(isTrusted: Bool) {
        isWaitingForGrant = !isTrusted
    }

    mutating func beginWaitingIfNeeded(isTrusted: Bool) {
        if !isTrusted {
            isWaitingForGrant = true
        }
    }

    mutating func shouldRelaunch(isTrusted: Bool) -> Bool {
        guard isWaitingForGrant, isTrusted else { return false }
        isWaitingForGrant = false
        return true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let midiService = MIDIService()
    private var controller = MCUController()
    private let dispatcher = KeyCommandDispatcher()
    private let stateMonitor = FinalCutStateMonitor()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "de.dominik.xfcbridge",
        category: "Accessibility"
    )

    private var statusItem: NSStatusItem!
    private let midiStatusItem = NSMenuItem(title: "MIDI: suche …", action: nil, keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "Bedienungshilfen: prüfe …", action: #selector(requestAccessibility), keyEquivalent: "")
    private let finalCutItem = NSMenuItem(title: "Final Cut: nicht aktiv", action: nil, keyEquivalent: "")
    private let modeItem = NSMenuItem(title: "Wheel: Shuttle", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Mapping aktiv", action: #selector(toggleEnabled), keyEquivalent: "")
    private let midiStatusLabel = NSTextField(labelWithString: "MIDI: suche …")
    private let accessibilityLabel = NSTextField(labelWithString: "Bedienungshilfen: prüfe …")
    private let finalCutLabel = NSTextField(labelWithString: "Final Cut: nicht aktiv")
    private let modeLabel = NSTextField(labelWithString: "Wheel: Shuttle")
    private var statusWindow: NSWindow!
    private var aboutWindow: NSWindow?
    private var jogIdleTimer: Timer?
    private var finalCutSnapshot = FinalCutStateSnapshot(playback: .unknown)
    private var wasFinalCutActive = false
    private var accessibilityRelaunchGate = AccessibilityRelaunchGate()
    private var accessibilityPermissionTimer: Timer?
    private var accessibilityPermissionDeadline: TimeInterval?
    private var isRelaunchingForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        configureStatusWindow()

        let trustedAtLaunch = dispatcher.isAccessibilityTrusted
        accessibilityRelaunchGate.configureAtLaunch(isTrusted: trustedAtLaunch)
        if accessibilityRelaunchGate.isWaitingForGrant {
            logger.info("Bedienungshilfen beim Start noch nicht erlaubt; warte auf Freigabe")
            startAccessibilityPermissionMonitoring()
        } else {
            logger.info("Bedienungshilfen beim Start bereits erlaubt; kein Neustart erforderlich")
        }

        midiService.onMessages = { [weak self] messages in
            Task { @MainActor in self?.handle(messages) }
        }
        midiService.onStatus = { [weak self] status in
            Task { @MainActor in self?.updateMIDIStatus(status) }
        }
        midiService.onOutputReady = { [weak self] in
            Task { @MainActor in self?.synchronizeLEDs() }
        }
        midiService.start()

        stateMonitor.onStateChange = { [weak self] snapshot in
            self?.updateFinalCutState(snapshot)
        }
        stateMonitor.onExternalInteraction = { [weak self] transportHint in
            self?.handleExternalFinalCutInteraction(transportHint: transportHint)
        }
        stateMonitor.onAvailabilityChange = { [weak self] in
            self?.refreshRuntimeStatus()
        }
        stateMonitor.start()
        refreshRuntimeStatus()
        showStatusWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return true
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "XFC"
        statusItem.button?.toolTip = "XFC Bridge"

        enabledItem.target = self
        enabledItem.state = .on
        accessibilityItem.target = self

        let menu = NSMenu()
        let appNameItem = NSMenuItem(title: "XFC Bridge", action: nil, keyEquivalent: "")
        appNameItem.isEnabled = false
        menu.addItem(appNameItem)
        let aboutItem = NSMenuItem(title: "Über XFC Bridge …", action: #selector(showAboutWindow), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        menu.addItem(midiStatusItem)
        menu.addItem(accessibilityItem)
        menu.addItem(finalCutItem)
        menu.addItem(modeItem)
        menu.addItem(.separator())
        menu.addItem(enabledItem)
        let showWindowItem = NSMenuItem(title: "Statusfenster öffnen …", action: #selector(showStatusWindowFromMenu), keyEquivalent: "")
        showWindowItem.target = self
        menu.addItem(showWindowItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func configureStatusWindow() {
        statusWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        statusWindow.title = "XFC Bridge"
        statusWindow.isReleasedWhenClosed = false
        statusWindow.center()

        let title = NSTextField(labelWithString: "X-Touch One → Final Cut Pro")
        title.font = .systemFont(ofSize: 20, weight: .semibold)

        let explanation = NSTextField(wrappingLabelWithString: "XFC Bridge läuft in der Menüleiste unter „XFC“. MIDI-Befehle werden nur an Final Cut gesendet, wenn Final Cut im Vordergrund ist.")
        explanation.textColor = .secondaryLabelColor

        for label in [midiStatusLabel, accessibilityLabel, finalCutLabel, modeLabel] {
            label.font = .systemFont(ofSize: 13)
        }

        let permissionButton = NSButton(title: "Bedienungshilfen erlauben …", target: self, action: #selector(requestAccessibility))
        permissionButton.bezelStyle = .rounded

        let stack = NSStackView(views: [title, explanation, midiStatusLabel, accessibilityLabel, finalCutLabel, modeLabel, permissionButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(20, after: explanation)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        statusWindow.contentView = contentView

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func showStatusWindow() {
        statusWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAboutWindow() {
        if aboutWindow == nil {
            configureAboutWindow()
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureAboutWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Über XFC Bridge"
        window.isReleasedWhenClosed = false
        window.center()

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
        ])

        let name = NSTextField(labelWithString: "XFC Bridge")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "X-Touch One Controller für Final Cut Pro")
        subtitle.textColor = .secondaryLabelColor
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (Build \(build))")
        versionLabel.textColor = .secondaryLabelColor

        let heading = NSStackView(views: [name, subtitle, versionLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 4

        let header = NSStackView(views: [icon, heading])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 16

        let author = NSTextField(labelWithString: "Autor: Dominik Weiland")
        let support = NSTextField(labelWithString: "XFC Bridge freiwillig unterstützen:")
        support.textColor = .secondaryLabelColor

        let koFiButton = NSButton(title: "Ko-fi", target: self, action: #selector(openKoFi))
        koFiButton.bezelStyle = .rounded
        koFiButton.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Ko-fi")
        koFiButton.imagePosition = .imageLeading

        let payPalButton = NSButton(title: "PayPal", target: self, action: #selector(openPayPal))
        payPalButton.bezelStyle = .rounded
        payPalButton.image = NSImage(systemSymbolName: "creditcard.fill", accessibilityDescription: "PayPal")
        payPalButton.imagePosition = .imageLeading

        let buttons = NSStackView(views: [koFiButton, payPalButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [header, author, support, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(stack)
        window.contentView = contentView
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
        ])
        aboutWindow = window
    }

    @objc private func openKoFi() {
        guard let url = URL(string: "https://ko-fi.com/dominik_w") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openPayPal() {
        guard let url = URL(string: "https://paypal.me/DominikWeiland") else { return }
        NSWorkspace.shared.open(url)
    }

    private func handle(_ messages: [MIDIMessage]) {
        guard dispatcher.canDispatch else { return }
        for message in messages {
            let effects = controller.handle(message, at: ProcessInfo.processInfo.systemUptime)
            apply(effects)
            if case let .controlChange(_, controllerNumber, _) = message,
               controllerNumber == MCUController.jogController {
                scheduleJogIdle()
            }
        }
        updateModeStatus()
    }

    private func updateMIDIStatus(_ status: MIDIService.Status) {
        if let error = status.errorDescription {
            midiStatusItem.title = "MIDI: Fehler – \(error)"
        } else if let sourceName = status.sourceName, status.destinationName != nil {
            midiStatusItem.title = "MIDI: \(sourceName) (Ein-/Ausgang)"
        } else if let sourceName = status.sourceName {
            midiStatusItem.title = "MIDI: \(sourceName) (nur Eingang)"
        } else {
            midiStatusItem.title = "MIDI: X-Touch One nicht gefunden"
        }
        midiStatusLabel.stringValue = midiStatusItem.title
    }

    private func refreshRuntimeStatus() {
        let trusted = dispatcher.isAccessibilityTrusted
        accessibilityItem.title = trusted
            ? "Bedienungshilfen: erlaubt"
            : "Bedienungshilfen erlauben …"
        accessibilityItem.isEnabled = !trusted
        accessibilityLabel.stringValue = accessibilityItem.title

        if accessibilityRelaunchGate.shouldRelaunch(isTrusted: trusted) {
            logger.info("Bedienungshilfen wurden erlaubt; automatischer Neustart wird ausgelöst")
            relaunchAfterAccessibilityGrant()
            return
        }

        let isFinalCutActive = dispatcher.isFinalCutFrontmost
        if isFinalCutActive {
            updateFinalCutStatusText()
        } else {
            finalCutItem.title = "Final Cut: nicht im Vordergrund"
            finalCutLabel.stringValue = finalCutItem.title
        }

        if isFinalCutActive != wasFinalCutActive {
            if isFinalCutActive, dispatcher.isEnabled, trusted {
                synchronizeLEDs()
            } else {
                jogIdleTimer?.invalidate()
                dispatcher.releaseHeldKeys()
                _ = controller.resetAfterExternalInteraction()
                finalCutSnapshot = FinalCutStateSnapshot(playback: .unknown)
                updateModeStatus()
                clearControlledLEDs()
            }
            wasFinalCutActive = isFinalCutActive
        }
    }

    @objc private func requestAccessibility() {
        let trusted = dispatcher.isAccessibilityTrusted
        accessibilityRelaunchGate.beginWaitingIfNeeded(isTrusted: trusted)
        dispatcher.requestAccessibilityPermission()
        if accessibilityRelaunchGate.isWaitingForGrant {
            startAccessibilityPermissionMonitoring()
        }
    }

    private func startAccessibilityPermissionMonitoring() {
        accessibilityPermissionTimer?.invalidate()
        accessibilityPermissionDeadline = ProcessInfo.processInfo.systemUptime + 120
        accessibilityPermissionTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(checkAccessibilityPermission),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func checkAccessibilityPermission(_ timer: Timer) {
        let deadline = accessibilityPermissionDeadline ?? 0
        guard ProcessInfo.processInfo.systemUptime < deadline else {
            timer.invalidate()
            accessibilityPermissionTimer = nil
            accessibilityPermissionDeadline = nil
            return
        }

        refreshRuntimeStatus()
        stateMonitor.refreshNow()
    }

    private func relaunchAfterAccessibilityGrant() {
        guard !isRelaunchingForAccessibility else { return }
        isRelaunchingForAccessibility = true
        accessibilityPermissionTimer?.invalidate()
        accessibilityPermissionTimer = nil
        accessibilityPermissionDeadline = nil

        accessibilityItem.title = "Bedienungshilfen: erlaubt · App wird neu gestartet …"
        accessibilityLabel.stringValue = accessibilityItem.title

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true

        logger.info("Starte neue XFCBridge-Instanz nach Bedienungshilfen-Freigabe")
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            Task { @MainActor in
                guard let self else { return }
                if application != nil, error == nil {
                    self.logger.info("Neue XFCBridge-Instanz gestartet; beende vorherige Instanz")
                    NSApp.terminate(nil)
                } else {
                    self.logger.error(
                        "Automatischer Neustart fehlgeschlagen: \(error?.localizedDescription ?? "unbekannter Fehler", privacy: .public)"
                    )
                    self.isRelaunchingForAccessibility = false
                    self.accessibilityItem.title =
                        "Bedienungshilfen: erlaubt · Neustart fehlgeschlagen"
                    self.accessibilityLabel.stringValue =
                        self.accessibilityItem.title
                }
            }
        }
    }

    @objc private func showStatusWindowFromMenu() {
        showStatusWindow()
    }

    @objc private func toggleEnabled() {
        dispatcher.isEnabled.toggle()
        enabledItem.state = dispatcher.isEnabled ? .on : .off
        if dispatcher.isEnabled, dispatcher.canDispatch {
            synchronizeLEDs()
        } else {
            jogIdleTimer?.invalidate()
            dispatcher.releaseHeldKeys()
            _ = controller.resetAfterExternalInteraction()
            updateModeStatus()
            clearControlledLEDs()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stateMonitor.stop()
        jogIdleTimer?.invalidate()
        accessibilityPermissionTimer?.invalidate()
        dispatcher.releaseHeldKeys()
        if !isRelaunchingForAccessibility {
            clearControlledLEDs()
        }
    }

    private func apply(_ effects: [ControlEffect]) {
        for effect in effects {
            switch effect {
            case let .command(command):
                dispatcher.dispatch(command)
                stateMonitor.refreshAfterCommand()
            case let .led(note, isOn):
                midiService.sendLED(note: note, isOn: isOn)
            }
        }
    }

    private func updateFinalCutState(_ snapshot: FinalCutStateSnapshot) {
        finalCutSnapshot = snapshot
        apply(controller.reconcilePlayback(snapshot.playback))
        updateFinalCutStatusText()
    }

    private func handleExternalFinalCutInteraction(
        transportHint: ExternalTransportHint?
    ) {
        jogIdleTimer?.invalidate()
        dispatcher.releaseHeldKeys()
        apply(controller.resetAfterExternalInteraction())
        if let transportHint {
            apply(controller.reconcileExternalTransport(transportHint))
        }
        updateModeStatus()
    }

    private func updateFinalCutStatusText() {
        guard dispatcher.isFinalCutFrontmost else { return }
        let playback: String
        switch finalCutSnapshot.playback {
        case .playing:
            playback = "Wiedergabe"
        case .stopped:
            playback = "angehalten"
        case .unknown:
            playback = "Status unbekannt"
        }
        finalCutItem.title = "Final Cut: aktiv · \(playback)"
        finalCutLabel.stringValue = finalCutItem.title
    }

    private func scheduleJogIdle() {
        jogIdleTimer?.invalidate()
        jogIdleTimer = Timer.scheduledTimer(withTimeInterval: MCUController.idleDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.apply(self.controller.handleIdle())
                self.updateModeStatus()
            }
        }
    }

    private func synchronizeLEDs() {
        guard dispatcher.canDispatch else { return }
        for (note, isOn) in controller.persistentLEDState {
            midiService.sendLED(note: note, isOn: isOn)
        }
    }

    private func clearControlledLEDs() {
        for note in controller.persistentLEDState.keys {
            midiService.sendLED(note: note, isOn: false)
        }
    }

    private func updateModeStatus() {
        let wheel: String
        if controller.isNudgeEnabled {
            wheel = controller.isScrubEnabled ? "NUDGE 1 Frame" : "NUDGE 10 Frames"
        } else {
            wheel = controller.isScrubEnabled ? "SCRUB mit Audio" : "dynamischer Shuttle"
        }

        let cursor: String
        if controller.isZoomEnabled {
            cursor = "Timeline-Zoom"
        } else if controller.isNudgeEnabled {
            cursor = "Clip-Auswahl"
        } else {
            cursor = "Navigation"
        }
        let mode = controller.isKeyframeEnabled ? "DROP: Video-Keyframes · " : ""
        let title = "\(mode)Wheel: \(wheel) · Steuerkreuz: \(cursor)"
        modeItem.title = title
        modeLabel.stringValue = title
    }
}
