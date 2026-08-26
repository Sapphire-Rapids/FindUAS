import Combine
@preconcurrency import CoreBluetooth
import FindUASCore
import Foundation

struct NearbyBLEDevice: Identifiable, Hashable {
    let id: UUID
    var name: String
    var rssi: Int
    var isConnectable: Bool
    var lastSeen: Date
}

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    enum State: String {
        case unavailable = "蓝牙不可用"
        case idle = "就绪"
        case scanning = "扫描中"
        case connecting = "连接中"
        case connected = "已连接"
        case disconnected = "未连接"
        case failed = "连接失败"
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var devices: [NearbyBLEDevice] = []
    @Published private(set) var telemetry: [DroneTelemetry] = []
    @Published private(set) var deviceConfiguration: DeviceConfiguration?
    @Published private(set) var detectedProtocolMode: ProtocolMode?
    @Published private(set) var lastPacketSummary = "尚无数据"
    @Published private(set) var lastTelemetryPacketSummary = "尚无 FF01 数据"
    @Published private(set) var telemetryPacketCount = 0
    @Published private(set) var assembledTelemetryFrameCount = 0
    @Published private(set) var decodedTargetCount = 0
    @Published private(set) var rejectedTelemetryFrameCount = 0
    @Published private(set) var lastError: String?

    var protocolMode: ProtocolMode = .automatic {
        didSet {
            telemetrySession.mode = protocolMode
            configurationAssembler.mode = protocolMode
        }
    }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var characteristics: [String: CBCharacteristic] = [:]
    private var pendingConfiguration: DeviceConfiguration?
    private var telemetrySession = TelemetrySession()
    private var configurationAssembler = BLEFrameAssembler()

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            state = .unavailable
            lastError = "请确认系统蓝牙已开启，并允许本应用访问蓝牙。"
            return
        }
        guard state != .connected && state != .connecting else {
            lastError = state == .connected
                ? "接收器已经连接，无需再次通过 Mac 蓝牙查找。"
                : "正在连接接收器，请稍候。"
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        lastError = nil
        state = .scanning
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(to device: NearbyBLEDevice) {
        guard FindUASProtocol.isCompatibleAdvertisementName(device.name) else {
            lastError = "“\(device.name)”不是已识别的 FindUAS / FindUAV 接收器。"
            return
        }
        guard device.isConnectable else {
            lastError = "“\(device.name)”当前只在广播，无法建立连接。"
            return
        }
        guard let peripheral = peripherals[device.id] else { return }
        stopScan()
        state = .connecting
        lastError = nil
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    func disconnect() {
        guard let connectedPeripheral else { return }
        central.cancelPeripheralConnection(connectedPeripheral)
    }

    func updateDeviceConfiguration(_ configuration: DeviceConfiguration) {
        guard let peripheral = connectedPeripheral,
              let characteristic = characteristics[FindUASProtocol.configurationCharacteristicUUID] else {
            lastError = "尚未连接到设备配置特征 FF02"
            return
        }
        guard !configuration.channels.isEmpty,
              configuration.channels.allSatisfy({ (1...196).contains($0) }),
              (1...10_000).contains(configuration.channelStayTime) else {
            lastError = "配置无效：信道必须位于 1...196，驻留时间必须位于 1...10000。"
            return
        }
        let encodingMode = protocolMode == .automatic ? (detectedProtocolMode ?? .legacy) : protocolMode
        do {
            let json = try configuration.updateJSON()
            let payload = try FindUASBLEProtocol.encode(json: json, mode: encodingMode)
            pendingConfiguration = configuration
            lastError = nil
            peripheral.writeValue(payload, for: characteristic, type: .withResponse)
        } catch {
            lastError = "配置编码失败：\(error)"
        }
    }

    func pruneTelemetry(olderThan cutoff: Date) {
        if telemetrySession.prune(olderThan: cutoff) {
            telemetry = telemetrySession.targets
        }
    }

    private func observeProtocol(in data: Data) {
        if data.starts(with: BLEFrameAssembler.v2Header) {
            detectedProtocolMode = .v2
        } else if data.first == 0x7B {
            detectedProtocolMode = .legacy
        }
    }

    private func packetSummary(_ data: Data, characteristicUUID: String) -> String {
        let hex = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        if let text = String(data: data, encoding: .utf8), text.contains("{") {
            return "\(characteristicUUID) · \(data.count) B · \(String(text.prefix(160)))"
        } else {
            return "\(characteristicUUID) · \(data.count) B · \(hex)\(data.count > 32 ? " …" : "")"
        }
    }

    private func consumeTelemetry(_ data: Data) {
        observeProtocol(in: data)
        do {
            let result = try telemetrySession.ingest(data)
            assembledTelemetryFrameCount += result.framesAssembled
            decodedTargetCount += result.targetsDecoded
            rejectedTelemetryFrameCount += result.framesRejected
            if result.framesAssembled > 0 {
                telemetry = result.activeTargets
            }
        } catch {
            rejectedTelemetryFrameCount += 1
            lastError = "协议帧解析失败：\(error)"
        }
    }

    private func consumeConfiguration(_ data: Data) {
        observeProtocol(in: data)
        do {
            for frame in try configurationAssembler.feed(data) {
                if let configuration = DeviceConfiguration.decode(frame) {
                    deviceConfiguration = configuration
                }
            }
        } catch {
            lastError = "设备配置帧解析失败：\(error)"
        }
    }

    private func failReceiverConnection(_ message: String) {
        state = .failed
        lastError = message
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
    }

}

extension BluetoothManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if state != .scanning && state != .connecting && state != .connected {
                state = .idle
            }
        case .poweredOff, .unauthorized, .unsupported:
            central.stopScan()
            state = .unavailable
        default: break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name ?? "未命名设备"
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let device = NearbyBLEDevice(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            isConnectable: connectable,
            lastSeen: Date()
        )
        peripherals[device.id] = peripheral
        if let index = devices.firstIndex(where: { $0.id == device.id }) { devices[index] = device }
        else { devices.append(device) }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // A BLE link alone is not enough: keep showing “连接中” until the
        // receiver's FF01 telemetry characteristic has actually been found.
        state = .connecting
        telemetrySession.reset()
        telemetry = []
        configurationAssembler.reset()
        detectedProtocolMode = nil
        lastPacketSummary = "尚无数据"
        lastTelemetryPacketSummary = "尚无 FF01 数据"
        telemetryPacketCount = 0
        assembledTelemetryFrameCount = 0
        decodedTargetCount = 0
        rejectedTelemetryFrameCount = 0
        peripheral.discoverServices([CBUUID(string: FindUASProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .failed
        connectedPeripheral = nil
        lastError = error?.localizedDescription ?? "未知连接错误"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state = .disconnected
        characteristics.removeAll()
        connectedPeripheral = nil
        deviceConfiguration = nil
        pendingConfiguration = nil
        detectedProtocolMode = nil
        if let error { lastError = error.localizedDescription }
    }
}

extension BluetoothManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            failReceiverConnection("读取接收器服务失败：\(error.localizedDescription)")
            return
        }
        let services = peripheral.services ?? []
        guard !services.isEmpty else {
            failReceiverConnection("设备未提供 FindUAS 服务 00FF。")
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            failReceiverConnection("读取接收器特征失败：\(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString.uppercased()
            characteristics[uuid] = characteristic
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
        if characteristics[FindUASProtocol.telemetryCharacteristicUUID] != nil {
            state = .connected
            lastError = nil
        } else {
            failReceiverConnection("接收器未提供 FF01 遥测特征。")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { lastError = error.localizedDescription; return }
        guard let data = characteristic.value else { return }
        let uuid = characteristic.uuid.uuidString.uppercased()
        let summary = packetSummary(data, characteristicUUID: uuid)
        lastPacketSummary = summary
        switch uuid {
        case FindUASProtocol.telemetryCharacteristicUUID:
            telemetryPacketCount += 1
            lastTelemetryPacketSummary = summary
            consumeTelemetry(data)
        case FindUASProtocol.configurationCharacteristicUUID:
            consumeConfiguration(data)
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid.uuidString.uppercased() == FindUASProtocol.configurationCharacteristicUUID else {
            return
        }
        if let error {
            pendingConfiguration = nil
            lastError = "配置写入失败：\(error.localizedDescription)"
            return
        }
        if let pendingConfiguration {
            deviceConfiguration = pendingConfiguration
            self.pendingConfiguration = nil
        }
        lastError = nil
        if characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
    }
}
