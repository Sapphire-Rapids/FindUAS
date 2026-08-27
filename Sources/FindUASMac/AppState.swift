import AppKit
import Combine
import FindUASCore
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case live = "实时监测"
        case map = "地图"
        case history = "历史记录"
        case devices = "设备"
        case lab = "兼容性实验室"
        case settings = "设置"

        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .live: "antenna.radiowaves.left.and.right"
            case .map: "map"
            case .history: "clock.arrow.circlepath"
            case .devices: "dot.radiowaves.left.and.right"
            case .lab: "testtube.2"
            case .settings: "gearshape"
            }
        }
    }

    @Published var selection: Section? = .live
    @Published var protocolMode: ProtocolMode = .automatic
    @Published var alertRadius: Double = 300
    @Published var alertSoundEnabled: Bool = true
    @Published var whitelist: Set<String> = []
    @Published private(set) var drones: [DroneTelemetry] = []

    let bluetooth = BluetoothManager()
    let records = RecordStore()
    let ridLab = RIDLabController()
    let djiUSB = DJIUSBReadOnlyMonitor()
    private var cancellables: Set<AnyCancellable> = []
    private var announcedUASIDs: Set<String> = []

    init() {
        whitelist = Set(UserDefaults.standard.stringArray(forKey: "whitelistedUASIDs") ?? [])
        bluetooth.$telemetry
            .receive(on: RunLoop.main)
            .sink { [weak self] values in
                guard let self else { return }
                if self.alertSoundEnabled,
                   values.contains(where: { !self.announcedUASIDs.contains($0.uasID) && !self.whitelist.contains($0.uasID) }) {
                    NSSound.beep()
                }
                announcedUASIDs.formUnion(values.map(\.uasID))
                drones = values.sorted { $0.lastSeen > $1.lastSeen }
                for value in values { records.append(value) }
            }
            .store(in: &cancellables)

        $protocolMode
            .sink { [weak bluetooth] mode in bluetooth?.protocolMode = mode }
            .store(in: &cancellables)

        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak bluetooth] now in
                bluetooth?.pruneTelemetry(olderThan: now.addingTimeInterval(-120))
            }
            .store(in: &cancellables)
    }

    var visibleDrones: [DroneTelemetry] {
        drones.filter { !whitelist.contains($0.uasID) }
    }

    func toggleWhitelist(_ uasID: String) {
        if whitelist.contains(uasID) { whitelist.remove(uasID) }
        else { whitelist.insert(uasID) }
        UserDefaults.standard.set(whitelist.sorted(), forKey: "whitelistedUASIDs")
    }
}
