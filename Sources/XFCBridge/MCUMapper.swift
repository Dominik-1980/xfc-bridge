import Foundation

enum ShuttleDirection: Equatable, Sendable {
    case reverse
    case forward
}

enum ExternalTransportHint: Equatable, Sendable {
    case reverse
    case forward
    case stopped
}

enum FCPCommand: Equatable, Sendable {
    case previousFrame
    case nextFrame
    case transport(ShuttleDirection)
    case shuttleStop
    case togglePlayback
    case beginAudioScrub(ShuttleDirection)
    case endAudioScrub
    case addEdit
    case ensureVideoAnimationOpen
    case ensureVideoAnimationClosed
    case addKeyframe
    case deleteKeyframe
    case previousKeyframe
    case nextKeyframe
    case addMarker
    case addMarkerAndModify
    case deleteMarker
    case undo
    case redo
    case setRangeStart
    case setRangeEnd
    case clearSelectedRanges
    case playSelection
    case nudgeLeft
    case nudgeRight
    case nudgeLeftMany
    case nudgeRightMany
    case selectPreviousClip
    case selectNextClip
    case selectClipAbove
    case selectClipBelow
    case previousMarker
    case nextMarker
    case previousEdit
    case nextEdit
    case timelineZoomOut
    case timelineZoomIn
    case decreaseTimelineElementHeight
    case increaseTimelineElementHeight
}

enum ControlEffect: Equatable, Sendable {
    case command(FCPCommand)
    case led(note: UInt8, isOn: Bool)
}

struct MCUController: Sendable {
    private enum ControlLayer: Sendable {
        case normal
        case marker
        case nudge
        case zoom
        case cycle
        case keyframe
    }

    static let jogController: UInt8 = 0x3C
    static let rewindNote: UInt8 = 0x5B
    static let fastForwardNote: UInt8 = 0x5C
    static let stopNote: UInt8 = 0x5D
    static let playNote: UInt8 = 0x5E
    static let markerNote: UInt8 = 0x54
    static let nudgeNote: UInt8 = 0x55
    static let cycleNote: UInt8 = 0x56
    static let dropNote: UInt8 = 0x57
    static let recordNote: UInt8 = 0x5F
    static let cursorUpNote: UInt8 = 0x60
    static let cursorDownNote: UInt8 = 0x61
    static let cursorLeftNote: UInt8 = 0x62
    static let cursorRightNote: UInt8 = 0x63
    static let zoomNote: UInt8 = 0x64
    static let scrubNote: UInt8 = 0x65
    static let bankLeftNote: UInt8 = 0x2E
    static let bankRightNote: UInt8 = 0x2F
    static let idleDelay: TimeInterval = 0.32
    static let longPressDelay: TimeInterval = 0.6
    static let nudgeJogMinimumInterval: TimeInterval = 0.1

    private(set) var isScrubEnabled = false
    private var activeLayer: ControlLayer = .normal
    var isZoomEnabled: Bool { activeLayer == .zoom }
    var isMarkerEnabled: Bool { activeLayer == .marker }
    var isNudgeEnabled: Bool { activeLayer == .nudge }
    var isCycleEnabled: Bool { activeLayer == .cycle }
    var isKeyframeEnabled: Bool { activeLayer == .keyframe }
    private var isPlaying = false
    private var activeDirection: ShuttleDirection?
    private var activeSpeed = 0
    private var isAudioScrubbing = false
    private var recentJogTimes: [TimeInterval] = []
    private var lastNudgeJogCommandAt: TimeInterval?
    private var recordPressedAt: TimeInterval?

    var persistentLEDState: [UInt8: Bool] {
        [
            Self.rewindNote: activeDirection == .reverse,
            Self.fastForwardNote: activeDirection == .forward,
            Self.stopNote: activeDirection == nil && !isPlaying,
            Self.playNote: isPlaying && activeDirection == nil,
            Self.scrubNote: isScrubEnabled,
            Self.zoomNote: isZoomEnabled,
            Self.markerNote: isMarkerEnabled,
            Self.nudgeNote: isNudgeEnabled,
            Self.cycleNote: isCycleEnabled,
            Self.dropNote: isKeyframeEnabled,
        ]
    }

    mutating func handle(_ message: MIDIMessage, at time: TimeInterval) -> [ControlEffect] {
        switch message {
        case let .controlChange(_, controller, value) where controller == Self.jogController:
            let ticks = Int(value & 0x3F)
            guard ticks > 0 else { return [] }
            let direction: ShuttleDirection = value & 0x40 == 0 ? .forward : .reverse
            return handleJog(direction: direction, ticks: min(ticks, 8), at: time)

        case let .noteOn(_, note, velocity) where velocity > 0:
            return handlePress(note: note, at: time)

        case let .noteOff(_, note, _):
            return handleRelease(note: note, at: time)

        default:
            return []
        }
    }

    mutating func handleIdle() -> [ControlEffect] {
        recentJogTimes.removeAll(keepingCapacity: true)
        lastNudgeJogCommandAt = nil

        if isAudioScrubbing {
            isAudioScrubbing = false
            activeDirection = nil
            activeSpeed = 0
            return [
                .command(.endAudioScrub),
                .led(note: Self.rewindNote, isOn: false),
                .led(note: Self.fastForwardNote, isOn: false),
                .led(note: Self.stopNote, isOn: true),
            ]
        }

        guard activeDirection != nil else { return [] }
        activeDirection = nil
        activeSpeed = 0
        isPlaying = false
        return [
            .command(.shuttleStop),
            .led(note: Self.rewindNote, isOn: false),
            .led(note: Self.fastForwardNote, isOn: false),
            .led(note: Self.playNote, isOn: false),
            .led(note: Self.stopNote, isOn: true),
        ]
    }

    private mutating func handleJog(direction: ShuttleDirection, ticks: Int, at time: TimeInterval) -> [ControlEffect] {
        if isNudgeEnabled {
            if let lastNudgeJogCommandAt,
               time - lastNudgeJogCommandAt < Self.nudgeJogMinimumInterval {
                return []
            }
            lastNudgeJogCommandAt = time
            let command: FCPCommand
            switch (direction, isScrubEnabled) {
            case (.reverse, false):
                command = .nudgeLeftMany
            case (.forward, false):
                command = .nudgeRightMany
            case (.reverse, true):
                command = .nudgeLeft
            case (.forward, true):
                command = .nudgeRight
            }
            return [.command(command)]
        }

        if isScrubEnabled {
            guard !isAudioScrubbing || activeDirection != direction else { return [] }
            activeDirection = direction
            isPlaying = false
            isAudioScrubbing = true
            return directionLEDs(direction) + [
                .command(.beginAudioScrub(direction)),
                .led(note: Self.stopNote, isOn: false),
            ]
        }

        if activeDirection != nil, activeDirection != direction {
            recentJogTimes.removeAll(keepingCapacity: true)
            activeSpeed = 0
        }
        for _ in 0..<ticks { recentJogTimes.append(time) }
        recentJogTimes.removeAll { time - $0 > 0.18 }
        let density = recentJogTimes.count
        let speed = density <= 3 ? 1 : density <= 6 ? 2 : density <= 10 ? 4 : 8

        guard activeDirection != direction || speed > activeSpeed else { return [] }
        activeDirection = direction
        activeSpeed = speed
        isPlaying = false
        return directionLEDs(direction) + [
            .command(.transport(direction)),
            .led(note: Self.playNote, isOn: false),
            .led(note: Self.stopNote, isOn: false),
        ]
    }

    private mutating func handlePress(note: UInt8, at time: TimeInterval) -> [ControlEffect] {
        switch note {
        case Self.scrubNote:
            isScrubEnabled.toggle()
            lastNudgeJogCommandAt = nil
            activeDirection = nil
            activeSpeed = 0
            isAudioScrubbing = false
            isPlaying = false
            recentJogTimes.removeAll(keepingCapacity: true)
            return [
                .command(.shuttleStop),
                .led(note: Self.scrubNote, isOn: isScrubEnabled),
                .led(note: Self.rewindNote, isOn: false),
                .led(note: Self.fastForwardNote, isOn: false),
                .led(note: Self.playNote, isOn: false),
                .led(note: Self.stopNote, isOn: true),
            ]

        case Self.zoomNote:
            return toggleLayer(.zoom)

        case Self.markerNote:
            return toggleLayer(.marker)

        case Self.nudgeNote:
            return toggleLayer(.nudge)

        case Self.cycleNote:
            return toggleLayer(.cycle)

        case Self.dropNote:
            return toggleLayer(.keyframe)

        case Self.recordNote:
            recordPressedAt = time
            return [.led(note: Self.recordNote, isOn: true)]

        case Self.cursorLeftNote:
            if isZoomEnabled { return commandWithMomentaryLED(.timelineZoomOut, note: note) }
            if isNudgeEnabled { return commandWithMomentaryLED(.selectPreviousClip, note: note) }
            return commandWithMomentaryLED(.previousFrame, note: note)
        case Self.cursorRightNote:
            if isZoomEnabled { return commandWithMomentaryLED(.timelineZoomIn, note: note) }
            if isNudgeEnabled { return commandWithMomentaryLED(.selectNextClip, note: note) }
            return commandWithMomentaryLED(.nextFrame, note: note)
        case Self.cursorUpNote:
            if isZoomEnabled { return commandWithMomentaryLED(.increaseTimelineElementHeight, note: note) }
            if isNudgeEnabled { return commandWithMomentaryLED(.selectClipAbove, note: note) }
            return commandWithMomentaryLED(.previousEdit, note: note)
        case Self.cursorDownNote:
            if isZoomEnabled { return commandWithMomentaryLED(.decreaseTimelineElementHeight, note: note) }
            if isNudgeEnabled { return commandWithMomentaryLED(.selectClipBelow, note: note) }
            return commandWithMomentaryLED(.nextEdit, note: note)

        case Self.bankLeftNote:
            return commandWithMomentaryLED(.undo, note: note)
        case Self.bankRightNote:
            return commandWithMomentaryLED(.redo, note: note)

        case Self.rewindNote:
            if isMarkerEnabled { return [.command(.previousMarker)] }
            if isCycleEnabled { return [.command(.setRangeStart)] }
            if isNudgeEnabled { return [.command(.nudgeLeft)] }
            if isKeyframeEnabled { return [.command(.previousKeyframe)] }
            return setTransport(direction: .reverse, command: .transport(.reverse))
        case Self.fastForwardNote:
            if isMarkerEnabled { return [.command(.nextMarker)] }
            if isCycleEnabled { return [.command(.setRangeEnd)] }
            if isNudgeEnabled { return [.command(.nudgeRight)] }
            if isKeyframeEnabled { return [.command(.nextKeyframe)] }
            return setTransport(direction: .forward, command: .transport(.forward))
        case Self.stopNote:
            if isMarkerEnabled { return [.command(.deleteMarker)] }
            if isKeyframeEnabled { return [.command(.deleteKeyframe)] }
            if isCycleEnabled {
                if isPlaying {
                    isPlaying = false
                    return [
                        .command(.shuttleStop),
                        .led(note: Self.playNote, isOn: false),
                        .led(note: Self.stopNote, isOn: true),
                    ]
                }
                return [.command(.clearSelectedRanges)]
            }
            activeDirection = nil
            activeSpeed = 0
            isPlaying = false
            isAudioScrubbing = false
            return [
                .command(.shuttleStop),
                .led(note: Self.rewindNote, isOn: false),
                .led(note: Self.fastForwardNote, isOn: false),
                .led(note: Self.playNote, isOn: false),
                .led(note: Self.stopNote, isOn: true),
            ]
        case Self.playNote:
            if isCycleEnabled {
                guard !isPlaying else { return [] }
                activeDirection = nil
                activeSpeed = 0
                isAudioScrubbing = false
                isPlaying = true
                return [
                    .command(.playSelection),
                    .led(note: Self.rewindNote, isOn: false),
                    .led(note: Self.fastForwardNote, isOn: false),
                    .led(note: Self.stopNote, isOn: false),
                    .led(note: Self.playNote, isOn: true),
                ]
            }
            activeDirection = nil
            activeSpeed = 0
            isAudioScrubbing = false
            isPlaying.toggle()
            return [
                .command(.togglePlayback),
                .led(note: Self.rewindNote, isOn: false),
                .led(note: Self.fastForwardNote, isOn: false),
                .led(note: Self.stopNote, isOn: !isPlaying),
                .led(note: Self.playNote, isOn: isPlaying),
            ]
        default:
            return [.led(note: note, isOn: true)]
        }
    }

    private mutating func handleRelease(note: UInt8, at time: TimeInterval) -> [ControlEffect] {
        if note == Self.recordNote, let pressedAt = recordPressedAt {
            recordPressedAt = nil
            let command: FCPCommand
            if isKeyframeEnabled {
                command = .addKeyframe
            } else if isMarkerEnabled {
                command = time - pressedAt >= Self.longPressDelay
                    ? .addMarkerAndModify
                    : .addMarker
            } else {
                command = .addEdit
            }
            return [.command(command), .led(note: note, isOn: false)]
        }

        guard !Self.persistentNotes.contains(note) else { return [] }
        return [.led(note: note, isOn: false)]
    }

    private mutating func toggleLayer(_ layer: ControlLayer) -> [ControlEffect] {
        let wasKeyframeEnabled = isKeyframeEnabled
        activeLayer = activeLayer == layer ? .normal : layer
        lastNudgeJogCommandAt = nil
        if isKeyframeEnabled {
            return layerLEDs + [.command(.ensureVideoAnimationOpen)]
        }
        if wasKeyframeEnabled {
            return layerLEDs + [.command(.ensureVideoAnimationClosed)]
        }
        return layerLEDs
    }

    mutating func reconcilePlayback(_ playback: FinalCutPlaybackState) -> [ControlEffect] {
        guard playback != .unknown else { return [] }

        isPlaying = playback == .playing
        if !isPlaying {
            activeDirection = nil
            activeSpeed = 0
            isAudioScrubbing = false
        }

        return transportLEDState
    }

    mutating func reconcileExternalTransport(_ hint: ExternalTransportHint) -> [ControlEffect] {
        switch hint {
        case .reverse:
            activeDirection = .reverse
            activeSpeed = 1
            isPlaying = true
        case .forward:
            activeDirection = .forward
            activeSpeed = 1
            isPlaying = true
        case .stopped:
            activeDirection = nil
            activeSpeed = 0
            isPlaying = false
        }
        isAudioScrubbing = false
        return transportLEDState
    }

    mutating func resetAfterExternalInteraction() -> [ControlEffect] {
        activeLayer = .normal
        activeDirection = nil
        activeSpeed = 0
        isAudioScrubbing = false
        recentJogTimes.removeAll(keepingCapacity: true)
        lastNudgeJogCommandAt = nil
        recordPressedAt = nil

        return layerLEDs + [
            .led(note: Self.rewindNote, isOn: false),
            .led(note: Self.fastForwardNote, isOn: false),
        ]
    }

    private var layerLEDs: [ControlEffect] {
        [
            .led(note: Self.markerNote, isOn: isMarkerEnabled),
            .led(note: Self.nudgeNote, isOn: isNudgeEnabled),
            .led(note: Self.zoomNote, isOn: isZoomEnabled),
            .led(note: Self.cycleNote, isOn: isCycleEnabled),
            .led(note: Self.dropNote, isOn: isKeyframeEnabled),
        ]
    }

    private var transportLEDState: [ControlEffect] {
        [
            .led(note: Self.rewindNote, isOn: activeDirection == .reverse),
            .led(note: Self.fastForwardNote, isOn: activeDirection == .forward),
            .led(note: Self.playNote, isOn: isPlaying && activeDirection == nil),
            .led(note: Self.stopNote, isOn: !isPlaying && activeDirection == nil),
        ]
    }

    private func commandWithMomentaryLED(_ command: FCPCommand, note: UInt8) -> [ControlEffect] {
        [.command(command), .led(note: note, isOn: true)]
    }

    private mutating func setTransport(direction: ShuttleDirection, command: FCPCommand) -> [ControlEffect] {
        activeDirection = direction
        activeSpeed = 1
        isPlaying = false
        isAudioScrubbing = false
        return directionLEDs(direction) + [
            .command(command),
            .led(note: Self.playNote, isOn: false),
            .led(note: Self.stopNote, isOn: false),
        ]
    }

    private func directionLEDs(_ direction: ShuttleDirection) -> [ControlEffect] {
        [
            .led(note: Self.rewindNote, isOn: direction == .reverse),
            .led(note: Self.fastForwardNote, isOn: direction == .forward),
        ]
    }

    private static let persistentNotes: Set<UInt8> = [
        rewindNote, fastForwardNote, stopNote, playNote, scrubNote, zoomNote, markerNote, nudgeNote,
        cycleNote, dropNote,
    ]
}
