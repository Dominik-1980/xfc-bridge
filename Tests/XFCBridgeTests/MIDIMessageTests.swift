import Testing
@testable import XFCBridge

@Test func parsesRunningStatusAndVelocityZero() {
    var parser = MIDIByteStreamParser()
    let messages = parser.feed([0x90, 0x5E, 0x7F, 0x5E, 0x00])

    #expect(messages == [
        .noteOn(channel: 0, note: 0x5E, velocity: 0x7F),
        .noteOff(channel: 0, note: 0x5E, velocity: 0)
    ])
}

@Test func mapsMeasuredJogDirections() {
    var controller = MCUController()

    let right = controller.handle(.controlChange(channel: 0, controller: 0x3C, value: 0x01), at: 1)
    _ = controller.handleIdle()
    let left = controller.handle(.controlChange(channel: 0, controller: 0x3C, value: 0x41), at: 2)

    #expect(right.contains(.command(.transport(.forward))))
    #expect(left.contains(.command(.transport(.reverse))))
}

@Test func jogDensityRaisesShuttleSpeedAndIdleStops() {
    var controller = MCUController()
    var effects: [ControlEffect] = []

    for index in 0..<12 {
        effects += controller.handle(
            .controlChange(channel: 0, controller: 0x3C, value: 0x01),
            at: 1 + Double(index) * 0.01
        )
    }

    #expect(effects.filter { $0 == .command(.transport(.forward)) }.count == 4)
    #expect(controller.handleIdle().contains(.command(.shuttleStop)))
}

@Test func scrubLatchesAndChangesJogBehavior() {
    var controller = MCUController()

    let toggle = controller.handle(.noteOn(channel: 0, note: 0x65, velocity: 0x7F), at: 1)
    let firstTick = controller.handle(.controlChange(channel: 0, controller: 0x3C, value: 0x01), at: 2)
    let secondTick = controller.handle(.controlChange(channel: 0, controller: 0x3C, value: 0x01), at: 2.05)
    let idle = controller.handleIdle()

    #expect(controller.isScrubEnabled)
    #expect(toggle.contains(.led(note: 0x65, isOn: true)))
    #expect(firstTick.contains(.command(.beginAudioScrub(.forward))))
    #expect(!secondTick.contains { effect in
        if case .command = effect { return true }
        return false
    })
    #expect(idle.contains(.command(.endAudioScrub)))
}

@Test func transportLEDsTrackLogicalState() {
    var controller = MCUController()

    let rewind = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 0)
    let play = controller.handle(.noteOn(channel: 0, note: 0x5E, velocity: 0x7F), at: 1)
    let stop = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 2)

    #expect(rewind.contains(.command(.transport(.reverse))))
    #expect(play.contains(.command(.togglePlayback)))
    #expect(play.contains(.led(note: 0x5E, isOn: true)))
    #expect(stop.contains(.command(.shuttleStop)))
    #expect(stop.contains(.led(note: 0x5D, isOn: true)))
    #expect(stop.contains(.led(note: 0x5E, isOn: false)))
}

@Test func unknownButtonsUseMomentaryLEDFeedback() {
    var controller = MCUController()
    let press = controller.handle(.noteOn(channel: 0, note: 0x2A, velocity: 0x7F), at: 1)
    let release = controller.handle(.noteOff(channel: 0, note: 0x2A, velocity: 0), at: 2)

    #expect(press == [.led(note: 0x2A, isOn: true)])
    #expect(release == [.led(note: 0x2A, isOn: false)])
}

@Test func measuredZoomButtonSwitchesCursorLayer() {
    var controller = MCUController()

    let enabled = controller.handle(.noteOn(channel: 0, note: 0x64, velocity: 0x7F), at: 1)
    let left = controller.handle(.noteOn(channel: 0, note: 0x62, velocity: 0x7F), at: 2)
    let right = controller.handle(.noteOn(channel: 0, note: 0x63, velocity: 0x7F), at: 3)
    let up = controller.handle(.noteOn(channel: 0, note: 0x60, velocity: 0x7F), at: 4)
    let down = controller.handle(.noteOn(channel: 0, note: 0x61, velocity: 0x7F), at: 5)

    #expect(controller.isZoomEnabled)
    #expect(enabled.contains(.led(note: 0x64, isOn: true)))
    #expect(enabled.contains(.led(note: 0x54, isOn: false)))
    #expect(enabled.contains(.led(note: 0x56, isOn: false)))
    #expect(left.contains(.command(.timelineZoomOut)))
    #expect(right.contains(.command(.timelineZoomIn)))
    #expect(up.contains(.command(.increaseTimelineElementHeight)))
    #expect(down.contains(.command(.decreaseTimelineElementHeight)))
}

@Test func cursorNavigatesWhenZoomLayerIsOff() {
    var controller = MCUController()

    let left = controller.handle(.noteOn(channel: 0, note: 0x62, velocity: 0x7F), at: 1)
    let right = controller.handle(.noteOn(channel: 0, note: 0x63, velocity: 0x7F), at: 2)
    let up = controller.handle(.noteOn(channel: 0, note: 0x60, velocity: 0x7F), at: 3)
    let down = controller.handle(.noteOn(channel: 0, note: 0x61, velocity: 0x7F), at: 4)

    #expect(left.contains(.command(.previousFrame)))
    #expect(right.contains(.command(.nextFrame)))
    #expect(up.contains(.command(.previousEdit)))
    #expect(down.contains(.command(.nextEdit)))
}

@Test func recordCreatesEditUnlessMarkerModeIsEnabled() {
    var controller = MCUController()

    _ = controller.handle(.noteOn(channel: 0, note: 0x5F, velocity: 0x7F), at: 1)
    let editRelease = controller.handle(.noteOff(channel: 0, note: 0x5F, velocity: 0), at: 1.2)

    let markerToggle = controller.handle(.noteOn(channel: 0, note: 0x54, velocity: 0x7F), at: 2)
    _ = controller.handle(.noteOn(channel: 0, note: 0x5F, velocity: 0x7F), at: 3)
    let shortRelease = controller.handle(.noteOff(channel: 0, note: 0x5F, velocity: 0), at: 3.2)
    _ = controller.handle(.noteOn(channel: 0, note: 0x5F, velocity: 0x7F), at: 4)
    let longRelease = controller.handle(.noteOff(channel: 0, note: 0x5F, velocity: 0), at: 4.8)

    #expect(editRelease.contains(.command(.addEdit)))
    #expect(controller.isMarkerEnabled)
    #expect(markerToggle.contains(.led(note: 0x54, isOn: true)))
    #expect(markerToggle.contains(.led(note: 0x64, isOn: false)))
    #expect(markerToggle.contains(.led(note: 0x56, isOn: false)))
    #expect(shortRelease.contains(.command(.addMarker)))
    #expect(longRelease.contains(.command(.addMarkerAndModify)))
}

@Test func bankButtonsAreGlobalUndoAndRedo() {
    var controller = MCUController()

    let undo = controller.handle(.noteOn(channel: 0, note: 0x2E, velocity: 0x7F), at: 1)
    _ = controller.handle(.noteOn(channel: 0, note: 0x54, velocity: 0x7F), at: 2)
    let redoInMarkerMode = controller.handle(.noteOn(channel: 0, note: 0x2F, velocity: 0x7F), at: 3)

    #expect(undo.contains(.command(.undo)))
    #expect(redoInMarkerMode.contains(.command(.redo)))
}

@Test func markerLayerRepurposesTransportAndExcludesZoom() {
    var controller = MCUController()

    _ = controller.handle(.noteOn(channel: 0, note: 0x64, velocity: 0x7F), at: 1)
    let markerToggle = controller.handle(.noteOn(channel: 0, note: 0x54, velocity: 0x7F), at: 2)
    let previous = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 3)
    let next = controller.handle(.noteOn(channel: 0, note: 0x5C, velocity: 0x7F), at: 4)
    let delete = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 5)

    #expect(controller.isMarkerEnabled)
    #expect(!controller.isZoomEnabled)
    #expect(!controller.isCycleEnabled)
    #expect(markerToggle.contains(.led(note: 0x54, isOn: true)))
    #expect(markerToggle.contains(.led(note: 0x64, isOn: false)))
    #expect(markerToggle.contains(.led(note: 0x56, isOn: false)))
    #expect(previous.contains(.command(.previousMarker)))
    #expect(next.contains(.command(.nextMarker)))
    #expect(delete.contains(.command(.deleteMarker)))
}

@Test func cycleLayerPlaysSelectionAndUsesActualPlaybackState() {
    var controller = MCUController()

    let cycleToggle = controller.handle(.noteOn(channel: 0, note: 0x56, velocity: 0x7F), at: 1)
    let setIn = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 2)
    let setOut = controller.handle(.noteOn(channel: 0, note: 0x5C, velocity: 0x7F), at: 3)
    let clear = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 4)
    let play = controller.handle(.noteOn(channel: 0, note: 0x5E, velocity: 0x7F), at: 5)
    let stopWhilePlaying = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 6)
    _ = controller.reconcilePlayback(.stopped)
    let clearAfterNaturalEnd = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 7)
    let replay = controller.handle(.noteOn(channel: 0, note: 0x5E, velocity: 0x7F), at: 8)

    #expect(controller.isCycleEnabled)
    #expect(cycleToggle.contains(.led(note: 0x56, isOn: true)))
    #expect(setIn.contains(.command(.setRangeStart)))
    #expect(setOut.contains(.command(.setRangeEnd)))
    #expect(clear.contains(.command(.clearSelectedRanges)))
    #expect(play.contains(.command(.playSelection)))
    #expect(stopWhilePlaying.contains(.command(.shuttleStop)))
    #expect(!stopWhilePlaying.contains(.command(.clearSelectedRanges)))
    #expect(clearAfterNaturalEnd.contains(.command(.clearSelectedRanges)))
    #expect(replay.contains(.command(.playSelection)))
}

@Test func externalInteractionResetsExclusiveLayerButKeepsScrubMode() {
    var controller = MCUController()

    _ = controller.handle(.noteOn(channel: 0, note: 0x65, velocity: 0x7F), at: 1)
    _ = controller.handle(.noteOn(channel: 0, note: 0x56, velocity: 0x7F), at: 2)
    let effects = controller.resetAfterExternalInteraction()

    #expect(controller.isScrubEnabled)
    #expect(!controller.isMarkerEnabled)
    #expect(!controller.isCycleEnabled)
    #expect(!controller.isZoomEnabled)
    #expect(effects.contains(.led(note: 0x54, isOn: false)))
    #expect(effects.contains(.led(note: 0x56, isOn: false)))
    #expect(effects.contains(.led(note: 0x64, isOn: false)))
}

@Test func externalTransportHintsPreserveKeyboardDirection() {
    var controller = MCUController()

    let reverse = controller.reconcileExternalTransport(.reverse)
    let forward = controller.reconcileExternalTransport(.forward)
    let stopped = controller.reconcileExternalTransport(.stopped)

    #expect(reverse.contains(.led(note: 0x5B, isOn: true)))
    #expect(reverse.contains(.led(note: 0x5C, isOn: false)))
    #expect(forward.contains(.led(note: 0x5B, isOn: false)))
    #expect(forward.contains(.led(note: 0x5C, isOn: true)))
    #expect(stopped.contains(.led(note: 0x5D, isOn: true)))
    #expect(stopped.contains(.led(note: 0x5E, isOn: false)))
}

@Test func nudgeLayerNavigatesClipsAndUsesScrubAsJogStepModifier() {
    var controller = MCUController()

    let enabled = controller.handle(.noteOn(channel: 0, note: 0x55, velocity: 0x7F), at: 1)
    let previousClip = controller.handle(.noteOn(channel: 0, note: 0x62, velocity: 0x7F), at: 2)
    let nextClip = controller.handle(.noteOn(channel: 0, note: 0x63, velocity: 0x7F), at: 3)
    let clipAbove = controller.handle(.noteOn(channel: 0, note: 0x60, velocity: 0x7F), at: 4)
    let clipBelow = controller.handle(.noteOn(channel: 0, note: 0x61, velocity: 0x7F), at: 5)
    let leftFrame = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 6)
    let rightFrame = controller.handle(.noteOn(channel: 0, note: 0x5C, velocity: 0x7F), at: 7)
    let jogLeftMany = controller.handle(
        .controlChange(channel: 0, controller: 0x3C, value: 0x41),
        at: 8
    )
    let jogRightMany = controller.handle(
        .controlChange(channel: 0, controller: 0x3C, value: 0x01),
        at: 9
    )
    _ = controller.handle(.noteOn(channel: 0, note: 0x65, velocity: 0x7F), at: 10)
    let jogLeftFrame = controller.handle(
        .controlChange(channel: 0, controller: 0x3C, value: 0x41),
        at: 11
    )
    let jogRightFrame = controller.handle(
        .controlChange(channel: 0, controller: 0x3C, value: 0x01),
        at: 12
    )
    let play = controller.handle(.noteOn(channel: 0, note: 0x5E, velocity: 0x7F), at: 13)
    let switchToMarker = controller.handle(.noteOn(channel: 0, note: 0x54, velocity: 0x7F), at: 14)

    #expect(controller.isMarkerEnabled)
    #expect(!controller.isNudgeEnabled)
    #expect(controller.isScrubEnabled)
    #expect(enabled.contains(.led(note: 0x55, isOn: true)))
    #expect(enabled.contains(.led(note: 0x54, isOn: false)))
    #expect(enabled.contains(.led(note: 0x56, isOn: false)))
    #expect(enabled.contains(.led(note: 0x64, isOn: false)))
    #expect(previousClip.contains(.command(.selectPreviousClip)))
    #expect(nextClip.contains(.command(.selectNextClip)))
    #expect(clipAbove.contains(.command(.selectClipAbove)))
    #expect(clipBelow.contains(.command(.selectClipBelow)))
    #expect(leftFrame.contains(.command(.nudgeLeft)))
    #expect(rightFrame.contains(.command(.nudgeRight)))
    #expect(jogLeftMany.contains(.command(.nudgeLeftMany)))
    #expect(jogRightMany.contains(.command(.nudgeRightMany)))
    #expect(jogLeftFrame.contains(.command(.nudgeLeft)))
    #expect(jogRightFrame.contains(.command(.nudgeRight)))
    #expect(play.contains(.command(.togglePlayback)))
    #expect(switchToMarker.contains(.led(note: 0x55, isOn: false)))
}

@Test func nudgeJogLimitsRapidCommandsAndResetsAfterIdleOrModeChange() {
    var controller = MCUController()
    let jogRight = MIDIMessage.controlChange(channel: 0, controller: 0x3C, value: 0x01)
    let jogLeft = MIDIMessage.controlChange(channel: 0, controller: 0x3C, value: 0x41)

    _ = controller.handle(.noteOn(channel: 0, note: 0x55, velocity: 0x7F), at: 1)
    let first = controller.handle(jogRight, at: 2)
    let rapid = (1...9).flatMap { index in
        controller.handle(jogRight, at: 2 + Double(index) * 0.01)
    }
    let next = controller.handle(jogLeft, at: 2.11)
    let button = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 2.12)

    #expect(first == [.command(.nudgeRightMany)])
    #expect(rapid.isEmpty)
    #expect(next == [.command(.nudgeLeftMany)])
    #expect(button.contains(.command(.nudgeLeft)))

    _ = controller.handleIdle()
    #expect(controller.handle(jogRight, at: 2.13) == [.command(.nudgeRightMany)])

    _ = controller.handle(.noteOn(channel: 0, note: 0x65, velocity: 0x7F), at: 2.14)
    #expect(controller.handle(jogRight, at: 2.15) == [.command(.nudgeRight)])
}

@Test func measuredDropButtonOpensExclusiveKeyframeLayer() {
    var controller = MCUController()

    _ = controller.handle(.noteOn(channel: 0, note: 0x55, velocity: 0x7F), at: 1)
    let enabled = controller.handle(.noteOn(channel: 0, note: 0x57, velocity: 0x7F), at: 2)
    let previous = controller.handle(.noteOn(channel: 0, note: 0x5B, velocity: 0x7F), at: 3)
    let next = controller.handle(.noteOn(channel: 0, note: 0x5C, velocity: 0x7F), at: 4)
    let delete = controller.handle(.noteOn(channel: 0, note: 0x5D, velocity: 0x7F), at: 4.5)
    _ = controller.handle(.noteOn(channel: 0, note: 0x5F, velocity: 0x7F), at: 5)
    let add = controller.handle(.noteOff(channel: 0, note: 0x5F, velocity: 0), at: 5.1)

    #expect(controller.isKeyframeEnabled)
    #expect(!controller.isNudgeEnabled)
    #expect(enabled.contains(.led(note: 0x57, isOn: true)))
    #expect(enabled.contains(.led(note: 0x55, isOn: false)))
    #expect(enabled.contains(.command(.ensureVideoAnimationOpen)))
    #expect(controller.persistentLEDState[0x57] == true)
    #expect(previous.contains(.command(.previousKeyframe)))
    #expect(next.contains(.command(.nextKeyframe)))
    #expect(delete == [.command(.deleteKeyframe)])
    #expect(add.contains(.command(.addKeyframe)))

    let disabled = controller.handle(.noteOn(channel: 0, note: 0x57, velocity: 0x7F), at: 6)
    _ = controller.handle(.noteOn(channel: 0, note: 0x5F, velocity: 0x7F), at: 7)
    let normalRecord = controller.handle(.noteOff(channel: 0, note: 0x5F, velocity: 0), at: 7.1)
    #expect(!controller.isKeyframeEnabled)
    #expect(disabled.contains(.led(note: 0x57, isOn: false)))
    #expect(disabled.contains(.command(.ensureVideoAnimationClosed)))
    #expect(normalRecord.contains(.command(.addEdit)))

    _ = controller.handle(.noteOn(channel: 0, note: 0x57, velocity: 0x7F), at: 8)
    let reset = controller.resetAfterExternalInteraction()
    #expect(!controller.isKeyframeEnabled)
    #expect(reset.contains(.led(note: 0x57, isOn: false)))
}

@Test func accessibilityRelaunchGateUsesLaunchStateAndRestartsOnlyOnce() {
    var alreadyTrustedAtLaunch = AccessibilityRelaunchGate()
    alreadyTrustedAtLaunch.configureAtLaunch(isTrusted: true)
    let trustedLaunch = alreadyTrustedAtLaunch.shouldRelaunch(isTrusted: true)

    var waitingForGrant = AccessibilityRelaunchGate()
    waitingForGrant.configureAtLaunch(isTrusted: false)
    let stillWaiting = waitingForGrant.shouldRelaunch(isTrusted: false)
    let permissionGranted = waitingForGrant.shouldRelaunch(isTrusted: true)
    let permissionStillGranted = waitingForGrant.shouldRelaunch(isTrusted: true)

    #expect(!alreadyTrustedAtLaunch.isWaitingForGrant)
    #expect(!trustedLaunch)
    #expect(!stillWaiting)
    #expect(permissionGranted)
    #expect(!permissionStillGranted)
    #expect(!waitingForGrant.isWaitingForGrant)
}
