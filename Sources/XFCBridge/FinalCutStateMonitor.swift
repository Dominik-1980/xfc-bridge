import AppKit
import ApplicationServices

enum FinalCutPlaybackState: Equatable, Sendable {
    case playing
    case stopped
    case unknown
}

struct FinalCutStateSnapshot: Equatable, Sendable {
    let playback: FinalCutPlaybackState
}

@MainActor
final class FinalCutAccessibilityReader {
    func readSnapshot() -> FinalCutStateSnapshot {
        guard let application = applicationElement(),
              let playbackButton = playbackButton(in: application) else {
            return FinalCutStateSnapshot(playback: .unknown)
        }

        let description = normalized(attributeString(kAXDescriptionAttribute, of: playbackButton))
        let help = normalized(attributeString(kAXHelpAttribute, of: playbackButton))

        if description.contains("aktiv")
            || description.contains("active")
            || help.contains("wiedergabe stoppen")
            || help.contains("stop playback") {
            return FinalCutStateSnapshot(playback: .playing)
        }

        if description.contains("angehalten")
            || description.contains("paused")
            || description.contains("stopped")
            || help.contains("ab abspielposition")
            || help.contains("play forward from") {
            return FinalCutStateSnapshot(playback: .stopped)
        }

        return FinalCutStateSnapshot(playback: .unknown)
    }

    func applicationElement() -> AXUIElement? {
        guard let finalCut = NSRunningApplication.runningApplications(
            withBundleIdentifier: KeyCommandDispatcher.finalCutBundleIdentifier
        ).first else { return nil }

        return AXUIElementCreateApplication(finalCut.processIdentifier)
    }

    func playbackButton(in application: AXUIElement) -> AXUIElement? {
        findElement(in: application) { element in
            guard attributeString(kAXRoleAttribute, of: element) == kAXButtonRole else {
                return false
            }

            let description = normalized(attributeString(kAXDescriptionAttribute, of: element))
            let help = normalized(attributeString(kAXHelpAttribute, of: element))
            return description.contains("wiedergabetaste")
                || description.contains("play button")
                || help.contains("ab abspielposition vorwarts wiedergeben")
                || help.contains("play forward from playhead")
                || help.contains("wiedergabe stoppen")
                || help.contains("stop playback")
        }
    }

    private func findElement(
        in element: AXUIElement,
        depth: Int = 0,
        matching predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        guard depth <= 18 else { return nil }
        if predicate(element) { return element }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &value
        ) == .success,
        let children = value as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = findElement(in: child, depth: depth + 1, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func attributeString(_ attribute: String, of element: AXUIElement) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let string = value as? String else {
            return ""
        }
        return string
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private func finalCutAccessibilityObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<FinalCutStateMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let notificationName = notification as String
    Task { @MainActor in
        monitor.accessibilityDidChange(notificationName)
    }
}

@MainActor
final class FinalCutStateMonitor {
    private let reader = FinalCutAccessibilityReader()
    private var observer: AXObserver?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var globalInputMonitor: Any?
    private var refreshWorkItem: DispatchWorkItem?

    var onStateChange: ((FinalCutStateSnapshot) -> Void)?
    var onExternalInteraction: ((ExternalTransportHint?) -> Void)?
    var onAvailabilityChange: (() -> Void)?

    func start() {
        guard workspaceObservers.isEmpty else { return }

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let notificationName = notification.name.rawValue
                let bundleIdentifier = (
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication
                )?.bundleIdentifier
                Task { @MainActor in
                    self?.workspaceDidChange(
                        name: notificationName,
                        applicationBundleIdentifier: bundleIdentifier
                    )
                }
            }
        }

        // Mouse-up and key-up run after Final Cut has committed the input. Reading
        // on the corresponding down event would observe the previous transport state.
        let inputMask: NSEvent.EventTypeMask = [
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
            .keyUp,
            .scrollWheel,
        ]
        globalInputMonitor = NSEvent.addGlobalMonitorForEvents(matching: inputMask) { [weak self] event in
            let sourceTag = event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0
            let transportHint = event.type == .keyUp
                ? Self.transportHint(for: event.keyCode)
                : nil
            Task { @MainActor in
                self?.globalInputOccurred(
                    sourceTag: sourceTag,
                    transportHint: transportHint
                )
            }
        }

        attachAccessibilityObserver()
        refreshNow()
        onAvailabilityChange?()
    }

    func stop() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil

        if let globalInputMonitor {
            NSEvent.removeMonitor(globalInputMonitor)
            self.globalInputMonitor = nil
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
        detachAccessibilityObserver()
    }

    func refreshNow() {
        guard isFinalCutFrontmost, AXIsProcessTrusted() else {
            onStateChange?(FinalCutStateSnapshot(playback: .unknown))
            return
        }
        onStateChange?(reader.readSnapshot())
    }

    func refreshAfterCommand() {
        scheduleRefresh(after: 0.08)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshNow()
        }
    }

    fileprivate func accessibilityDidChange(_ notification: String) {
        if notification == kAXUIElementDestroyedNotification as String
            || notification == kAXWindowCreatedNotification as String {
            attachAccessibilityObserver()
        }
        scheduleRefresh(after: 0.03)
    }

    private var isFinalCutFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            == KeyCommandDispatcher.finalCutBundleIdentifier
    }

    private func workspaceDidChange(
        name: String,
        applicationBundleIdentifier: String?
    ) {
        guard applicationBundleIdentifier == KeyCommandDispatcher.finalCutBundleIdentifier
                || name == NSWorkspace.didActivateApplicationNotification.rawValue else {
            return
        }

        attachAccessibilityObserver()
        onAvailabilityChange?()
        refreshNow()
    }

    private func globalInputOccurred(
        sourceTag: Int64,
        transportHint: ExternalTransportHint?
    ) {
        guard sourceTag != KeyCommandDispatcher.syntheticEventUserData,
              isFinalCutFrontmost else { return }

        onExternalInteraction?(transportHint)
        scheduleRefresh(after: 0.03)
    }

    nonisolated private static func transportHint(for keyCode: UInt16) -> ExternalTransportHint? {
        switch keyCode {
        case 38:
            return .reverse
        case 37:
            return .forward
        case 40:
            return .stopped
        default:
            return nil
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.refreshNow()
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func attachAccessibilityObserver() {
        detachAccessibilityObserver()

        guard AXIsProcessTrusted(),
              let finalCut = NSRunningApplication.runningApplications(
                withBundleIdentifier: KeyCommandDispatcher.finalCutBundleIdentifier
              ).first,
              let application = reader.applicationElement() else { return }

        var createdObserver: AXObserver?
        guard AXObserverCreate(
            finalCut.processIdentifier,
            finalCutAccessibilityObserverCallback,
            &createdObserver
        ) == .success,
        let createdObserver else { return }

        observer = createdObserver
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        for notification in [
            kAXFocusedWindowChangedNotification,
            kAXWindowCreatedNotification,
        ] {
            AXObserverAddNotification(
                createdObserver,
                application,
                notification as CFString,
                context
            )
        }

        if let playbackButton = reader.playbackButton(in: application) {
            for notification in [
                kAXValueChangedNotification,
                kAXTitleChangedNotification,
                kAXUIElementDestroyedNotification,
            ] {
                AXObserverAddNotification(
                    createdObserver,
                    playbackButton,
                    notification as CFString,
                    context
                )
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(createdObserver),
            .commonModes
        )
    }

    private func detachAccessibilityObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )
        self.observer = nil
    }
}
