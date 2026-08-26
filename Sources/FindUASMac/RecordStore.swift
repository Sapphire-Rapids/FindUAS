import Combine
import FindUASCore
import Foundation

@MainActor
final class RecordStore: ObservableObject {
    @Published private(set) var records: [DroneTelemetry] = []
    private var lastWrittenAt: [String: Date] = [:]

    init() {
        loadPersistedRecords()
    }

    func append(_ telemetry: DroneTelemetry) {
        if let index = records.firstIndex(where: { $0.uasID == telemetry.uasID }) {
            records[index].merge(telemetry)
        } else {
            records.insert(telemetry, at: 0)
        }

        let previous = lastWrittenAt[telemetry.uasID] ?? .distantPast
        guard Date().timeIntervalSince(previous) >= 2 else { return }
        lastWrittenAt[telemetry.uasID] = Date()
        persistJSONLine(telemetry)
    }

    private func persistJSONLine(_ telemetry: DroneTelemetry) {
        guard let data = try? JSONEncoder().encode(telemetry) else { return }
        let fm = FileManager.default
        guard let directory = storageDirectory else { return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("telemetry.jsonl")
        var line = data
        line.append(0x0A)
        if fm.fileExists(atPath: file.path), let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: file, options: .atomic)
        }
    }

    private var storageDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FindUASMac", isDirectory: true)
    }

    private func loadPersistedRecords() {
        guard let file = storageDirectory?.appendingPathComponent("telemetry.jsonl"),
              let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n") {
            guard var telemetry = try? decoder.decode(DroneTelemetry.self, from: Data(line.utf8)) else { continue }
            telemetry.normalizeUnavailableValues()
            if let index = records.firstIndex(where: { $0.uasID == telemetry.uasID }) {
                records[index].merge(telemetry)
            } else {
                records.append(telemetry)
            }
        }
        records.sort { $0.lastSeen > $1.lastSeen }
    }
}
