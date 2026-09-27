import AppKit
import ApplicationServices

@MainActor
final class KeyCommandDispatcher {
    static let finalCutBundleIdentifier = "com.apple.FinalCut"
    static let syntheticEventUserData: Int64 = 0x58544643

    private enum TimelineControl {
        case zoom
        case clipHeight
    }

    private let jKey: CGKeyCode = 38
    private let kKey: CGKeyCode = 40
    private let lKey: CGKeyCode = 37
    private var heldKeys: [CGKeyCode] = []
    private var scrubRepeatTimer: Timer?

    var isEnabled = true

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isFinalCutFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finalCutBundleIdentifier
    }
    var canDispatch: Bool { isEnabled && isAccessibilityTrusted && isFinalCutFrontmost }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func dispatch(_ command: FCPCommand) {
        guard canDispatch else { return }

        switch command {
        case .previousFrame:
            cancelSequenceAndReleaseKeys()
            tap(123)
        case .nextFrame:
            cancelSequenceAndReleaseKeys()
            tap(124)
        case let .transport(direction):
            cancelSequenceAndReleaseKeys()
            tap(key(for: direction))
        case .shuttleStop:
            cancelSequenceAndReleaseKeys()
            tap(kKey)
        case .togglePlayback:
            cancelSequenceAndReleaseKeys()
            tap(49)
        case let .beginAudioScrub(direction):
            beginAudioScrub(direction: direction)
        case .endAudioScrub:
            cancelSequenceAndReleaseKeys()
        case .addEdit:
            cancelSequenceAndReleaseKeys()
            tap(11, flags: .maskCommand)
        case .ensureVideoAnimationOpen:
            cancelSequenceAndReleaseKeys()
            setVideoAnimationOpen(true)
        case .ensureVideoAnimationClosed:
            cancelSequenceAndReleaseKeys()
            setVideoAnimationOpen(false)
        case .addKeyframe:
            cancelSequenceAndReleaseKeys()
            tap(kKey, flags: .maskAlternate)
        case .deleteKeyframe:
            cancelSequenceAndReleaseKeys()
            tap(51, flags: [.maskAlternate, .maskShift])
        case .previousKeyframe:
            cancelSequenceAndReleaseKeys()
            tap(41, flags: .maskAlternate)
        case .nextKeyframe:
            cancelSequenceAndReleaseKeys()
            tap(39, flags: .maskAlternate)
        case .addMarker:
            cancelSequenceAndReleaseKeys()
            tap(46)
        case .addMarkerAndModify:
            cancelSequenceAndReleaseKeys()
            tap(46, flags: .maskAlternate)
        case .deleteMarker:
            cancelSequenceAndReleaseKeys()
            tap(46, flags: .maskControl)
        case .undo:
            cancelSequenceAndReleaseKeys()
            _ = performFinalCutMenuItem { title in
                title.localizedCaseInsensitiveContains("widerrufen")
                    || title.lowercased().hasPrefix("undo")
            }
        case .redo:
            cancelSequenceAndReleaseKeys()
            _ = performFinalCutMenuItem { title in
                title.localizedCaseInsensitiveContains("wiederholen")
                    || title.lowercased().hasPrefix("redo")
            }
        case .setRangeStart:
            cancelSequenceAndReleaseKeys()
            tap(34)
        case .setRangeEnd:
            cancelSequenceAndReleaseKeys()
            tap(31)
        case .clearSelectedRanges:
            cancelSequenceAndReleaseKeys()
            tap(7, flags: .maskAlternate)
        case .playSelection:
            cancelSequenceAndReleaseKeys()
            _ = performFinalCutMenuItem { title in
                title.localizedCaseInsensitiveCompare("Auswahl wiedergeben") == .orderedSame
                    || title.localizedCaseInsensitiveCompare("Play Selection") == .orderedSame
            }
        case .nudgeLeft:
            cancelSequenceAndReleaseKeys()
            tap(43)
        case .nudgeRight:
            cancelSequenceAndReleaseKeys()
            tap(47)
        case .nudgeLeftMany:
            cancelSequenceAndReleaseKeys()
            tap(43, flags: .maskShift)
        case .nudgeRightMany:
            cancelSequenceAndReleaseKeys()
            tap(47, flags: .maskShift)
        case .selectPreviousClip:
            cancelSequenceAndReleaseKeys()
            tap(123, flags: .maskCommand)
        case .selectNextClip:
            cancelSequenceAndReleaseKeys()
            tap(124, flags: .maskCommand)
        case .selectClipAbove:
            cancelSequenceAndReleaseKeys()
            tap(126, flags: .maskCommand)
        case .selectClipBelow:
            cancelSequenceAndReleaseKeys()
            tap(125, flags: .maskCommand)
        case .previousMarker:
            cancelSequenceAndReleaseKeys()
            tap(41, flags: .maskControl)
        case .nextMarker:
            cancelSequenceAndReleaseKeys()
            tap(39, flags: .maskControl)
        case .previousEdit:
            cancelSequenceAndReleaseKeys()
            tap(126)
        case .nextEdit:
            cancelSequenceAndReleaseKeys()
            tap(125)
        case .timelineZoomOut:
            cancelSequenceAndReleaseKeys()
            adjustTimelineControl(.zoom, increase: false)
        case .timelineZoomIn:
            cancelSequenceAndReleaseKeys()
            adjustTimelineControl(.zoom, increase: true)
        case .decreaseTimelineElementHeight:
            cancelSequenceAndReleaseKeys()
            adjustTimelineControl(.clipHeight, increase: false)
        case .increaseTimelineElementHeight:
            cancelSequenceAndReleaseKeys()
            adjustTimelineControl(.clipHeight, increase: true)
        }
    }

    func releaseHeldKeys() {
        cancelSequenceAndReleaseKeys()
    }

    private func beginAudioScrub(direction: ShuttleDirection) {
        cancelSequenceAndReleaseKeys()
        pressAndRemember(kKey)
        let directionKey = key(for: direction)
        pressAndRemember(directionKey)
        scrubRepeatTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.post(directionKey, isDown: true, isAutoRepeat: true)
            }
        }
    }

    private func cancelSequenceAndReleaseKeys() {
        scrubRepeatTimer?.invalidate()
        scrubRepeatTimer = nil
        releaseRememberedKeys()
    }

    private func pressAndRemember(_ key: CGKeyCode) {
        guard !heldKeys.contains(key) else { return }
        keyDown(key)
        heldKeys.append(key)
    }

    private func releaseRememberedKeys() {
        for key in heldKeys.reversed() { keyUp(key) }
        heldKeys.removeAll(keepingCapacity: true)
    }

    private func key(for direction: ShuttleDirection) -> CGKeyCode {
        direction == .forward ? lKey : jKey
    }

    private func performFinalCutMenuItem(
        where predicate: (String) -> Bool
    ) -> Bool {
        guard let finalCut = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finalCutBundleIdentifier
        ).first else { return false }

        let application = AXUIElementCreateApplication(finalCut.processIdentifier)
        guard let menuItem = findElement(in: application, matching: { element in
            guard attributeString(kAXRoleAttribute, of: element) == kAXMenuItemRole else {
                return false
            }
            return predicate(attributeString(kAXTitleAttribute, of: element))
        }) else { return false }

        return AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success
    }

    private func setVideoAnimationOpen(_ shouldBeOpen: Bool) {
        guard let finalCut = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finalCutBundleIdentifier
        ).first else { return }

        let application = AXUIElementCreateApplication(finalCut.processIdentifier)
        let editorIsOpen = findElement(in: application, matching: { element in
            guard attributeString(kAXRoleAttribute, of: element) == kAXGroupRole else {
                return false
            }
            let name = attributeString(kAXTitleAttribute, of: element)
            let roleDescription = attributeString(kAXRoleDescriptionAttribute, of: element)
            return name.localizedCaseInsensitiveContains("Videoanimation")
                || name.localizedCaseInsensitiveContains("Video Animation")
                || roleDescription.localizedCaseInsensitiveContains("Videoanimation")
                || roleDescription.localizedCaseInsensitiveContains("Video Animation")
        }) != nil
        guard editorIsOpen != shouldBeOpen else { return }

        tap(9, flags: .maskControl)
    }

    private func adjustTimelineControl(_ control: TimelineControl, increase: Bool) {
        guard let finalCut = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.finalCutBundleIdentifier
        ).first else { return }

        let application = AXUIElementCreateApplication(finalCut.processIdentifier)
        if performTimelineAdjustment(control, increase: increase, in: application) {
            return
        }

        guard let appearanceButton = findElement(in: application, matching: { element in
            let help = attributeString(kAXHelpAttribute, of: element)
            return help.localizedCaseInsensitiveContains("Erscheinungsbild der Clips in der Timeline")
                || help.localizedCaseInsensitiveContains("appearance of clips in the timeline")
        }) else { return }

        guard AXUIElementPerformAction(appearanceButton, kAXPressAction as CFString) == .success else {
            return
        }

        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let finalCut = NSRunningApplication.runningApplications(
                        withBundleIdentifier: Self.finalCutBundleIdentifier
                      ).first else { return }

                let refreshedApplication = AXUIElementCreateApplication(finalCut.processIdentifier)
                _ = self.performTimelineAdjustment(
                    control,
                    increase: increase,
                    in: refreshedApplication
                )

                if let button = self.findElement(in: refreshedApplication, matching: { element in
                    let help = self.attributeString(kAXHelpAttribute, of: element)
                    return help.localizedCaseInsensitiveContains("Erscheinungsbild der Clips in der Timeline")
                        || help.localizedCaseInsensitiveContains("appearance of clips in the timeline")
                }) {
                    _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
                }
            }
        }
    }

    private func performTimelineAdjustment(
        _ control: TimelineControl,
        increase: Bool,
        in application: AXUIElement
    ) -> Bool {
        guard let slider = findElement(in: application, matching: { element in
            guard attributeString(kAXRoleAttribute, of: element) == kAXSliderRole else {
                return false
            }

            let description = attributeString(kAXDescriptionAttribute, of: element)
            let help = attributeString(kAXHelpAttribute, of: element)

            switch control {
            case .zoom:
                return description.localizedCaseInsensitiveContains("Timeline zoomen")
                    || help.localizedCaseInsensitiveContains("Darstellungsgröße der Timeline")
                    || description.localizedCaseInsensitiveContains("timeline zoom")
                    || help.localizedCaseInsensitiveContains("timeline view size")
            case .clipHeight:
                return description.localizedCaseInsensitiveContains("Höhenanpassung")
                    || help.localizedCaseInsensitiveContains("Cliphöhe")
                    || description.localizedCaseInsensitiveContains("height adjustment")
                    || help.localizedCaseInsensitiveContains("clip height")
            }
        }) else { return false }

        let action = increase ? kAXIncrementAction : kAXDecrementAction
        return AXUIElementPerformAction(slider, action as CFString) == .success
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

    private func tap(_ key: CGKeyCode, flags: CGEventFlags = []) {
        keyDown(key, flags: flags)
        keyUp(key, flags: flags)
    }

    private func keyDown(_ key: CGKeyCode, flags: CGEventFlags = []) {
        post(key, isDown: true, isAutoRepeat: false, flags: flags)
    }

    private func keyUp(_ key: CGKeyCode, flags: CGEventFlags = []) {
        post(key, isDown: false, isAutoRepeat: false, flags: flags)
    }

    private func post(
        _ key: CGKeyCode,
        isDown: Bool,
        isAutoRepeat: Bool,
        flags: CGEventFlags = []
    ) {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventUserData)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isAutoRepeat ? 1 : 0)
        event.post(tap: .cghidEventTap)
    }
}
