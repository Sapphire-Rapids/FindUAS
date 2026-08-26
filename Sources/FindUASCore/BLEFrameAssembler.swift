import Foundation

/// Reassembles JSON transported by the two protocols used by FindUAV Device.
/// The byte constants and length semantics were recovered from FindUAS Android 1.4.4.
public struct BLEFrameAssembler: Sendable {
    public enum Error: Swift.Error, Equatable {
        case bufferOverflow
        case invalidFrameLength(Int)
        case invalidFrameTail
    }

    public static let v2Header = Data([0x08, 0x17, 0x30])
    public static let v2Tail = Data([0x3F, 0x55])

    public var mode: ProtocolMode
    public private(set) var buffer = Data()
    public let maximumFrameLength: Int

    public init(mode: ProtocolMode = .automatic, maximumFrameLength: Int = 4_096) {
        self.mode = mode
        self.maximumFrameLength = maximumFrameLength
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    public mutating func feed(_ chunk: Data) throws -> [Data] {
        guard !chunk.isEmpty else { return [] }
        buffer.append(chunk)
        guard buffer.count <= maximumFrameLength * 2 + 7 else {
            reset()
            throw Error.bufferOverflow
        }

        var frames: [Data] = []
        while !buffer.isEmpty {
            trimLeadingSeparators()
            guard !buffer.isEmpty else { break }

            switch mode {
            case .legacy:
                guard let frame = extractLegacyFrame() else { return frames }
                frames.append(frame)
            case .v2:
                if let frame = try extractV2Frame(strict: true) {
                    frames.append(frame)
                } else {
                    return frames
                }
            case .automatic:
                if isV2PrefixOrPartial {
                    if let frame = try extractV2Frame(strict: false) {
                        frames.append(frame)
                    } else {
                        return frames
                    }
                } else if buffer.first == 0x7B {
                    guard let frame = extractLegacyFrame() else { return frames }
                    frames.append(frame)
                } else {
                    buffer.removeFirst()
                }
            }
        }
        return frames
    }

    private var isV2PrefixOrPartial: Bool {
        let header = [UInt8](Self.v2Header)
        let count = min(buffer.count, header.count)
        return Array(buffer.prefix(count)) == Array(header.prefix(count))
    }

    private mutating func extractV2Frame(strict: Bool) throws -> Data? {
        let header = [UInt8](Self.v2Header)
        if buffer.count < header.count {
            if Array(buffer) == Array(header.prefix(buffer.count)) { return nil }
            if strict { buffer.removeFirst() }
            return nil
        }

        guard buffer.prefix(3) == Self.v2Header else {
            buffer.removeFirst()
            return nil
        }
        guard buffer.count >= 5 else { return nil }

        // Data indices are not guaranteed to restart at zero after removing a
        // prefix. Always address bytes relative to startIndex; otherwise an
        // idle zero-filled FF01 packet followed by a real V2 packet traps here.
        let start = buffer.startIndex
        let lengthLowIndex = buffer.index(start, offsetBy: 3)
        let lengthHighIndex = buffer.index(start, offsetBy: 4)
        let frameLength = Int(buffer[lengthLowIndex]) | (Int(buffer[lengthHighIndex]) << 8)
        guard frameLength >= 2 else {
            buffer.removeFirst()
            throw Error.invalidFrameLength(frameLength)
        }
        let payloadLength = frameLength - Self.v2Tail.count
        guard payloadLength <= maximumFrameLength else {
            buffer.removeFirst()
            throw Error.invalidFrameLength(frameLength)
        }

        let totalLength = 5 + frameLength
        guard buffer.count >= totalLength else { return nil }
        let frameEnd = buffer.index(start, offsetBy: totalLength)
        let tailStart = buffer.index(frameEnd, offsetBy: -Self.v2Tail.count)
        guard buffer.subdata(in: tailStart..<frameEnd) == Self.v2Tail else {
            buffer.removeFirst()
            throw Error.invalidFrameTail
        }

        let payloadStart = buffer.index(start, offsetBy: 5)
        let payload = buffer.subdata(in: payloadStart..<tailStart)
        buffer.removeSubrange(start..<frameEnd)
        return payload
    }

    private mutating func extractLegacyFrame() -> Data? {
        guard let start = buffer.firstIndex(of: 0x7B) else {
            buffer.removeAll(keepingCapacity: true)
            return nil
        }
        if start > buffer.startIndex {
            buffer.removeSubrange(buffer.startIndex..<start)
        }

        var braceDepth = 0
        var inString = false
        var escaped = false

        for index in buffer.indices {
            let byte = buffer[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                braceDepth += 1
            } else if byte == 0x7D {
                braceDepth -= 1
                if braceDepth == 0 {
                    let end = buffer.index(after: index)
                    let frame = buffer.subdata(in: buffer.startIndex..<end)
                    buffer.removeSubrange(buffer.startIndex..<end)
                    return frame
                }
                if braceDepth < 0 {
                    buffer.removeSubrange(buffer.startIndex...index)
                    return nil
                }
            }
        }
        return nil
    }

    private mutating func trimLeadingSeparators() {
        while let first = buffer.first, first == 0x00 || first == 0x0A || first == 0x0D || first == 0x20 {
            buffer.removeFirst()
        }
    }
}
