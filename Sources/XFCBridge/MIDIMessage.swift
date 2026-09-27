import Foundation

enum MIDIMessage: Equatable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
}

struct MIDIByteStreamParser: Sendable {
    private var runningStatus: UInt8?
    private var dataBytes: [UInt8] = []
    private var inSystemExclusive = false

    mutating func feed<S: Sequence>(_ bytes: S) -> [MIDIMessage] where S.Element == UInt8 {
        var messages: [MIDIMessage] = []

        for byte in bytes {
            if byte >= 0xF8 { continue }

            if inSystemExclusive {
                if byte == 0xF7 { inSystemExclusive = false }
                continue
            }

            if byte == 0xF0 {
                inSystemExclusive = true
                runningStatus = nil
                dataBytes.removeAll(keepingCapacity: true)
                continue
            }

            if byte & 0x80 != 0 {
                if byte < 0xF0 {
                    runningStatus = byte
                } else {
                    runningStatus = nil
                }
                dataBytes.removeAll(keepingCapacity: true)
                continue
            }

            guard let status = runningStatus else { continue }
            dataBytes.append(byte)

            let type = status & 0xF0
            let expectedBytes = (type == 0xC0 || type == 0xD0) ? 1 : 2
            guard dataBytes.count == expectedBytes else { continue }

            if let message = Self.makeMessage(status: status, data: dataBytes) {
                messages.append(message)
            }
            dataBytes.removeAll(keepingCapacity: true)
        }

        return messages
    }

    private static func makeMessage(status: UInt8, data: [UInt8]) -> MIDIMessage? {
        let channel = status & 0x0F
        switch status & 0xF0 {
        case 0x80:
            return .noteOff(channel: channel, note: data[0], velocity: data[1])
        case 0x90:
            if data[1] == 0 {
                return .noteOff(channel: channel, note: data[0], velocity: 0)
            }
            return .noteOn(channel: channel, note: data[0], velocity: data[1])
        case 0xB0:
            return .controlChange(channel: channel, controller: data[0], value: data[1])
        default:
            return nil
        }
    }
}
