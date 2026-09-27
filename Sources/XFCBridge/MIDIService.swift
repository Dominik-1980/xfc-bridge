import CoreMIDI
import Foundation

final class MIDIService: @unchecked Sendable {
    struct Status: Sendable {
        let sourceName: String?
        let destinationName: String?
        let errorDescription: String?
    }

    private let lock = NSLock()
    private var parser = MIDIByteStreamParser()
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var connectedSource = MIDIEndpointRef()
    private var connectedDestination = MIDIEndpointRef()
    private var lastLEDStates: [UInt8: Bool] = [:]

    var onMessages: (@Sendable ([MIDIMessage]) -> Void)?
    var onStatus: (@Sendable (Status) -> Void)?
    var onOutputReady: (@Sendable () -> Void)?

    deinit {
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func start() {
        let clientStatus = MIDIClientCreateWithBlock("XFCBridge" as CFString, &client) { [weak self] _ in
            self?.refreshEndpoints()
        }
        guard clientStatus == noErr else {
            publishError("MIDI-Client konnte nicht erstellt werden (\(clientStatus)).")
            return
        }

        let inputStatus = MIDIInputPortCreateWithBlock(client, "XFCBridge Input" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.receive(packetList)
        }
        guard inputStatus == noErr else {
            publishError("MIDI-Eingang konnte nicht erstellt werden (\(inputStatus)).")
            return
        }

        let outputStatus = MIDIOutputPortCreate(client, "XFCBridge Output" as CFString, &outputPort)
        guard outputStatus == noErr else {
            publishError("MIDI-Ausgang konnte nicht erstellt werden (\(outputStatus)).")
            return
        }

        refreshEndpoints()
    }

    func sendLED(note: UInt8, isOn: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard outputPort != 0, connectedDestination != 0 else { return }
        guard lastLEDStates[note] != isOn else { return }

        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        let bytes: [UInt8] = [0x90, note, isOn ? 0x7F : 0x00]
        _ = bytes.withUnsafeBufferPointer { buffer in
            MIDIPacketListAdd(
                &packetList,
                MemoryLayout<MIDIPacketList>.size,
                packet,
                0,
                buffer.count,
                buffer.baseAddress!
            )
        }
        if MIDISend(outputPort, connectedDestination, &packetList) == noErr {
            lastLEDStates[note] = isOn
        }
    }

    private func refreshEndpoints() {
        lock.lock()

        if connectedSource != 0 {
            MIDIPortDisconnectSource(inputPort, connectedSource)
            connectedSource = 0
        }
        connectedDestination = 0
        lastLEDStates.removeAll(keepingCapacity: true)

        let sourceMatch = Self.findEndpoint(count: MIDIGetNumberOfSources(), endpoint: MIDIGetSource)
        let destinationMatch = Self.findEndpoint(count: MIDIGetNumberOfDestinations(), endpoint: MIDIGetDestination)

        var sourceName: String?
        var destinationName: String?
        var error: String?

        if let sourceMatch {
            let status = MIDIPortConnectSource(inputPort, sourceMatch.endpoint, nil)
            if status == noErr {
                connectedSource = sourceMatch.endpoint
                sourceName = sourceMatch.name
            } else {
                error = "Verbindung zum Eingang \(sourceMatch.name) fehlgeschlagen (\(status))."
            }
        }

        if let destinationMatch {
            connectedDestination = destinationMatch.endpoint
            destinationName = destinationMatch.name
        }

        let outputBecameReady = connectedDestination != 0
        lock.unlock()

        onStatus?(Status(sourceName: sourceName, destinationName: destinationName, errorDescription: error))
        if outputBecameReady { onOutputReady?() }
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        var collected: [MIDIMessage] = []

        withUnsafePointer(to: packetList.pointee.packet) { firstPacket in
            var packetPointer = firstPacket
            for _ in 0..<packetList.pointee.numPackets {
                let packet = packetPointer.pointee
                let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                    Array(rawBuffer.prefix(Int(packet.length)))
                }
                lock.lock()
                collected.append(contentsOf: parser.feed(bytes))
                lock.unlock()
                packetPointer = UnsafePointer(MIDIPacketNext(packetPointer))
            }
        }

        if !collected.isEmpty { onMessages?(collected) }
    }

    private func publishError(_ description: String) {
        onStatus?(Status(sourceName: nil, destinationName: nil, errorDescription: description))
    }

    private static func findEndpoint(
        count: Int,
        endpoint: (Int) -> MIDIEndpointRef
    ) -> (endpoint: MIDIEndpointRef, name: String)? {
        var fallback: (MIDIEndpointRef, String)?
        for index in 0..<count {
            let candidate = endpoint(index)
            let name = displayName(of: candidate)
            let normalized = name.lowercased()
            if normalized.contains("x-touch one") || normalized.contains("x touch one") {
                return (candidate, name)
            }
            if fallback == nil, normalized.contains("x-touch") || normalized.contains("x touch") {
                fallback = (candidate, name)
            }
        }
        return fallback
    }

    private static func displayName(of object: MIDIObjectRef) -> String {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let name = unmanagedName?.takeRetainedValue() else {
            return "Unbekannter MIDI-Port"
        }
        return name as String
    }
}
