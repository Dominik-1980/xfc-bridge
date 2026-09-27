import CoreMIDI
import Foundation

final class MIDIDump: @unchecked Sendable {
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var source = MIDIEndpointRef()

    func start() throws {
        var status = MIDIClientCreateWithBlock("XFCBridge MIDI-Diagnose" as CFString, &client) { _ in }
        guard status == noErr else { throw Failure("MIDI-Client", status) }

        status = MIDIInputPortCreateWithBlock(client, "XFCBridge Diagnose-Eingang" as CFString, &inputPort) { packetList, _ in
            var packet = packetList.pointee.packet
            for _ in 0..<packetList.pointee.numPackets {
                let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
                let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("\(Self.timestamp())  \(hex)")
                fflush(stdout)
                packet = MIDIPacketNext(&packet).pointee
            }
        }
        guard status == noErr else { throw Failure("MIDI-Eingang", status) }

        let sources = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }
        guard let match = sources.first(where: { Self.name(of: $0).localizedCaseInsensitiveContains("X-Touch One") })
            ?? sources.first(where: { Self.name(of: $0).localizedCaseInsensitiveContains("X-Touch") }) else {
            throw Failure("Keine X-Touch-MIDI-Quelle gefunden", -1)
        }

        source = match
        status = MIDIPortConnectSource(inputPort, source, nil)
        guard status == noErr else { throw Failure("Verbindung", status) }
        print("Verbunden: \(Self.name(of: source))")
        print("Lausche auf MIDI … (Beenden mit Ctrl-C)")
        fflush(stdout)
    }

    private static func name(of object: MIDIObjectRef) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &value) == noErr,
              let value else { return "Unbekannt" }
        return value.takeRetainedValue() as String
    }

    private static func timestamp() -> String {
        String(format: "%.3f", Date().timeIntervalSince1970)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ operation: String, _ status: OSStatus) {
            description = "\(operation) fehlgeschlagen (\(status))"
        }
    }
}

let dump = MIDIDump()
do {
    try dump.start()
    RunLoop.main.run()
} catch {
    fputs("Fehler: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
