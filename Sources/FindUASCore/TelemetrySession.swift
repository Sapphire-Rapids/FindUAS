import Foundation

public struct TelemetryIngestResult: Sendable {
    public let framesAssembled: Int
    public let targetsDecoded: Int
    public let framesRejected: Int
    public let activeTargets: [DroneTelemetry]
}

/// Stateful, platform-neutral FF01 processing used by the macOS client and
/// suitable for reuse by a future Windows transport layer.
public struct TelemetrySession: Sendable {
    public var mode: ProtocolMode {
        didSet { assembler.mode = mode }
    }
    public let targetLifetime: TimeInterval
    public private(set) var targets: [DroneTelemetry] = []

    private var assembler: BLEFrameAssembler
    private let decoder = TelemetryDecoder()

    public init(mode: ProtocolMode = .automatic, targetLifetime: TimeInterval = 120) {
        self.mode = mode
        self.targetLifetime = targetLifetime
        assembler = BLEFrameAssembler(mode: mode)
    }

    public mutating func reset() {
        assembler.reset()
        targets.removeAll(keepingCapacity: true)
    }

    public mutating func ingest(_ chunk: Data, receivedAt: Date = Date()) throws -> TelemetryIngestResult {
        let frames = try assembler.feed(chunk)
        var decodedCount = 0
        var rejectedCount = 0

        for frame in frames {
            let decoded = decoder.decode(frame, receivedAt: receivedAt)
            if decoded.isEmpty {
                rejectedCount += 1
                continue
            }
            decodedCount += decoded.count
            for item in decoded { upsert(item) }
        }

        _ = prune(olderThan: receivedAt.addingTimeInterval(-targetLifetime))
        targets.sort { $0.lastSeen > $1.lastSeen }
        return TelemetryIngestResult(
            framesAssembled: frames.count,
            targetsDecoded: decodedCount,
            framesRejected: rejectedCount,
            activeTargets: targets
        )
    }

    @discardableResult
    public mutating func prune(olderThan cutoff: Date) -> Bool {
        let previousCount = targets.count
        targets.removeAll { $0.lastSeen < cutoff }
        return previousCount != targets.count
    }

    private mutating func upsert(_ item: DroneTelemetry) {
        if let index = targets.firstIndex(where: { $0.uasID == item.uasID }) {
            targets[index].merge(item)
        } else {
            targets.append(item)
        }
    }
}
