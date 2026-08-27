import AppKit
import FindUASCore
import MapKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Section.allCases, selection: $app.selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("FindUAS")
        } detail: {
            switch app.selection ?? .live {
            case .live: LiveView()
            case .map: DroneMapView()
            case .history: HistoryView()
            case .devices: DevicesView()
            case .lab: AdminLabView()
            case .settings: SettingsView()
            }
        }
    }
}

private struct LiveView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var detailUASID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("实时监测").font(.largeTitle.bold())
                    Text("未加入白名单的目标：\(app.visibleDrones.count)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(state: bluetooth.state)
                Button(primaryReceiverActionTitle) {
                    performPrimaryReceiverAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(bluetooth.state == .connecting || bluetooth.state == .unavailable)
            }
            .padding()
            Toggle("发现新目标时播放告警音", isOn: $app.alertSoundEnabled)
                .padding(.horizontal)
                .padding(.bottom, 8)

            Divider()
            if app.visibleDrones.isEmpty {
                ContentUnavailableView(
                    "尚未收到无人机遥测",
                    systemImage: bluetooth.state == .connected
                        ? "antenna.radiowaves.left.and.right"
                        : "antenna.radiowaves.left.and.right.slash",
                    description: Text(emptyStateDescription)
                )
            } else {
                Table(app.visibleDrones) {
                    TableColumn("UAS ID") { Text($0.uasID).font(.system(.body, design: .monospaced)) }
                    TableColumn("型号") { Text($0.model ?? $0.name ?? "未知") }
                    TableColumn("高度") { Text(metric($0.height ?? $0.altitude, suffix: "m")) }
                    TableColumn("速度") { Text(metric($0.horizontalSpeed, suffix: "m/s")) }
                    TableColumn("信号") { Text($0.rssi.map { "\($0) dBm" } ?? "—") }
                    TableColumn("更新时间") { Text($0.lastSeen, style: .time) }
                    TableColumn("操作") { drone in
                        HStack(spacing: 10) {
                            Button("详情") { detailUASID = drone.uasID }
                            Button("加入白名单") { app.toggleWhitelist(drone.uasID) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .sheet(isPresented: detailPresented) {
            if let detailUASID {
                DroneDetailView(uasID: detailUASID)
            }
        }
    }

    private func metric(_ value: Double?, suffix: String) -> String {
        value.map { String(format: "%.1f %@", $0, suffix) } ?? "—"
    }

    private var primaryReceiverActionTitle: String {
        switch bluetooth.state {
        case .connected: "断开接收器"
        case .connecting: "正在连接…"
        case .scanning: "停止查找"
        default: "查找接收器"
        }
    }

    private var emptyStateDescription: String {
        switch bluetooth.state {
        case .connected:
            "接收器已连接，正在等待 FF01 Remote ID 遥测。飞机由接收器自身持续监听，无需让 Mac 再次扫描。"
        case .connecting:
            "Mac 正在连接 FindUAS / FindUAV 接收器，并检查 FF01 遥测通道。"
        case .scanning:
            "Mac 正在通过蓝牙查找附近的 FindUAS / FindUAV 接收器；这不是在扫描飞机。"
        case .unavailable:
            "Mac 蓝牙不可用。请开启蓝牙，并在系统设置中授予本应用蓝牙权限。"
        default:
            "请先让 Mac 查找并连接 FindUAS / FindUAV 接收器。连接后，接收器会自行监听飞机的 Remote ID。"
        }
    }

    private func performPrimaryReceiverAction() {
        switch bluetooth.state {
        case .connected:
            bluetooth.disconnect()
        case .scanning:
            bluetooth.stopScan()
        case .connecting, .unavailable:
            break
        default:
            bluetooth.startScan()
        }
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { detailUASID != nil },
            set: { if !$0 { detailUASID = nil } }
        )
    }
}

private struct DroneDetailView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    let uasID: String

    private var drone: DroneTelemetry? {
        app.drones.first { $0.uasID == uasID }
            ?? app.records.records.first { $0.uasID == uasID }
    }

    var body: some View {
        NavigationStack {
            if let drone {
                Form {
                    Section("身份信息") {
                        DetailRow("UAS ID", drone.uasID, monospaced: true)
                        DetailRow("实名登记标识", text(drone.registrationID), monospaced: true)
                        DetailRow("Remote ID 标准", text(drone.ridStandard))
                        DetailRow("飞机类型", text(drone.uavType))
                        DetailRow("ID 类型", text(drone.uavIDType))
                        DetailRow("制造商", text(drone.manufacturer))
                        DetailRow("型号 / 名称", text(drone.model ?? drone.name))
                        DetailRow("运行类别", text(drone.operationCategory))
                        DetailRow("航空器类别", text(drone.aircraftCategory))
                    }

                    Section("飞机位置与运动") {
                        DetailRow("坐标", coordinate(drone.latitude, drone.longitude), monospaced: true)
                        DetailRow("坐标系", text(drone.coordinateSystem))
                        DetailRow("相对高度", metric(drone.height, unit: "m"))
                        DetailRow("几何高度", metric(drone.altitudeGeometric ?? drone.altitude, unit: "m"))
                        DetailRow("气压高度", metric(drone.altitudeBarometric, unit: "m"))
                        DetailRow("水平速度", metric(drone.horizontalSpeed, unit: "m/s"))
                        DetailRow("垂直速度", metric(drone.verticalSpeed, unit: "m/s"))
                        DetailRow("航向 / 航迹角", metric(drone.heading, unit: "°"))
                        DetailRow("运行状态代码", integer(drone.flightStatus))
                        DetailRow("紧急状态", text(drone.emergencyStatus))
                    }

                    Section("操作手 / 控制站") {
                        DetailRow("坐标", coordinate(drone.operatorLatitude, drone.operatorLongitude), monospaced: true)
                        DetailRow("几何高度", metric(drone.operatorAltitude, unit: "m"))
                        DetailRow("位置类型", text(drone.controlStationLocationType))
                        if let phone = nonEmpty(drone.operatorRegistrationPhone) {
                            DetailRow("厂商私有电话字段", phone, monospaced: true)
                        } else {
                            Text("未收到电话字段。标准 Remote ID 不广播姓名、电话或住址；只有接收器明确提供厂商私有字段时，本应用才会显示。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("定位质量与时间") {
                        DetailRow("水平精度", metric(drone.horizontalAccuracy, unit: "m"))
                        DetailRow("垂直精度", metric(drone.verticalAccuracy, unit: "m"))
                        DetailRow("速度精度", metric(drone.speedAccuracy, unit: "m/s"))
                        DetailRow("时间戳精度", metric(drone.timestampAccuracy, unit: "s"))
                        DetailRow("GPS 定位类型", integer(drone.gpsFixType))
                        DetailRow("GPS HDOP", decimal(drone.gpsHDOP))
                        DetailRow("GPS 卫星数", integer(drone.gpsSatelliteCount))
                        DetailRow("接收器 GPS 高度", metric(drone.gpsAltitudeGeometric, unit: "m"))
                        DetailRow("接收器 GPS 速度", gpsSpeed(drone))
                        DetailRow("GPS UTC", gpsUTC(drone))
                        DetailRow("广播时间", date(drone.eventTime))
                        DetailRow("本机首次收到", date(drone.firstSeen))
                        DetailRow("本机最近收到", date(drone.lastSeen))
                    }

                    Section("接收器") {
                        DetailRow("名称", text(drone.monitorName))
                        DetailRow("序列号 / UUID", text(drone.monitorID), monospaced: true)
                        DetailRow("信道", integer(drone.monitorChannel))
                        DetailRow("温度", metric(drone.monitorTemperature, unit: "℃"))
                        DetailRow("RSSI", drone.rssi.map { "\($0) dBm" } ?? "—")
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("目标详情")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(copied ? "已复制" : "复制全部") { copy(drone) }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
            } else {
                ContentUnavailableView("目标已离线", systemImage: "airplane.slash")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { dismiss() }
                        }
                    }
            }
        }
        .frame(minWidth: 700, minHeight: 680)
    }

    private func copy(_ drone: DroneTelemetry) {
        let lines = [
            "UAS ID: \(drone.uasID)",
            "实名登记标识: \(text(drone.registrationID))",
            "Remote ID 标准: \(text(drone.ridStandard))",
            "飞机类型: \(text(drone.uavType))",
            "飞机坐标: \(coordinate(drone.latitude, drone.longitude))",
            "相对高度: \(metric(drone.height, unit: "m"))",
            "几何高度: \(metric(drone.altitudeGeometric ?? drone.altitude, unit: "m"))",
            "气压高度: \(metric(drone.altitudeBarometric, unit: "m"))",
            "水平速度: \(metric(drone.horizontalSpeed, unit: "m/s"))",
            "垂直速度: \(metric(drone.verticalSpeed, unit: "m/s"))",
            "航向: \(metric(drone.heading, unit: "°"))",
            "运行状态代码: \(integer(drone.flightStatus))",
            "操作手/控制站坐标: \(coordinate(drone.operatorLatitude, drone.operatorLongitude))",
            "操作手/控制站高度: \(metric(drone.operatorAltitude, unit: "m"))",
            "厂商私有电话字段: \(text(drone.operatorRegistrationPhone))",
            "GPS 定位类型: \(integer(drone.gpsFixType))",
            "GPS HDOP: \(decimal(drone.gpsHDOP))",
            "GPS 卫星数: \(integer(drone.gpsSatelliteCount))",
            "广播时间: \(date(drone.eventTime))",
            "本机最近收到: \(date(drone.lastSeen))",
            "接收器: \(text(drone.monitorName)) / \(text(drone.monitorID))",
            "接收器信道: \(integer(drone.monitorChannel))",
            "RSSI: \(drone.rssi.map { "\($0) dBm" } ?? "—")"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
    }

    private func text(_ value: String?) -> String { nonEmpty(value) ?? "—" }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func coordinate(_ latitude: Double?, _ longitude: Double?) -> String {
        guard let latitude, let longitude else { return "—" }
        return String(format: "%.7f, %.7f", latitude, longitude)
    }

    private func metric(_ value: Double?, unit: String) -> String {
        value.map { String(format: "%.2f %@", $0, unit) } ?? "—"
    }

    private func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "—"
    }

    private func integer(_ value: Int?) -> String { value.map(String.init) ?? "—" }

    private func date(_ value: Date?) -> String {
        value?.formatted(date: .numeric, time: .standard) ?? "—"
    }

    private func gpsSpeed(_ drone: DroneTelemetry) -> String {
        if let speed = drone.gpsSpeedKmh { return String(format: "%.2f km/h", speed) }
        if let speed = drone.gpsSpeedKnots { return String(format: "%.2f kn", speed) }
        return "—"
    }

    private func gpsUTC(_ drone: DroneTelemetry) -> String {
        [nonEmpty(drone.gpsUTCDate), nonEmpty(drone.gpsUTCTime)].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? "—"
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    let monospaced: Bool

    init(_ label: String, _ value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .fontDesign(monospaced ? .monospaced : .default)
                .textSelection(.enabled)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private struct DroneMapView: View {
    @EnvironmentObject private var app: AppState
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position) {
            ForEach(app.visibleDrones) { drone in
                if let latitude = drone.latitude, let longitude = drone.longitude {
                    Marker(drone.model ?? drone.uasID, systemImage: "airplane", coordinate: .init(latitude: latitude, longitude: longitude))
                        .tint(.red)
                }
                if let latitude = drone.operatorLatitude, let longitude = drone.operatorLongitude {
                    Marker("操作者", systemImage: "person.fill", coordinate: .init(latitude: latitude, longitude: longitude))
                        .tint(.blue)
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
        .navigationTitle("目标地图")
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var records: RecordStore
    @State private var detailUASID: String?

    var body: some View {
        Table(records.records) {
            TableColumn("首次发现") { Text($0.firstSeen, style: .time) }
            TableColumn("最后出现") { Text($0.lastSeen, style: .time) }
            TableColumn("UAS ID") { Text($0.uasID).font(.system(.body, design: .monospaced)) }
            TableColumn("制造商") { Text($0.manufacturer ?? "未知") }
            TableColumn("型号") { Text($0.model ?? $0.name ?? "未知") }
            TableColumn("操作") { drone in
                Button("详情") { detailUASID = drone.uasID }
                    .buttonStyle(.borderless)
            }
        }
        .navigationTitle("历史记录")
        .sheet(isPresented: detailPresented) {
            if let detailUASID {
                DroneDetailView(uasID: detailUASID)
            }
        }
    }

    private var detailPresented: Binding<Bool> {
        Binding(
            get: { detailUASID != nil },
            set: { if !$0 { detailUASID = nil } }
        )
    }
}

private struct DevicesView: View {
    @EnvironmentObject private var bluetooth: BluetoothManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("蓝牙设备").font(.largeTitle.bold())
                Spacer()
                StatusBadge(state: bluetooth.state)
                if bluetooth.state == .connected {
                    Button("断开接收器") { bluetooth.disconnect() }
                } else if bluetooth.state == .connecting {
                    Button("正在连接…") {}
                        .disabled(true)
                } else {
                    Button(bluetooth.state == .scanning ? "停止蓝牙扫描" : "扫描附近蓝牙") {
                        bluetooth.state == .scanning ? bluetooth.stopScan() : bluetooth.startScan()
                    }
                    .disabled(bluetooth.state == .unavailable)
                }
            }
            .padding()
            Text("这里由 Mac 扫描附近的蓝牙接收器；连接后，飞机的 Remote ID 由接收器自身持续监听。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 10)
            Divider()
            if let error = bluetooth.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
            }
            List(bluetooth.devices) { device in
                let isCompatible = FindUASProtocol.isCompatibleAdvertisementName(device.name)
                HStack {
                    Image(systemName: isCompatible ? "dot.radiowaves.left.and.right" : "wave.3.right")
                        .foregroundStyle(isCompatible ? .blue : .secondary)
                    VStack(alignment: .leading) {
                        Text(device.name).font(.headline)
                        Text(deviceDescription(device, isCompatible: isCompatible))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isCompatible {
                        Button("连接接收器") { bluetooth.connect(to: device) }
                            .disabled(!device.isConnectable || bluetooth.state == .connecting || bluetooth.state == .connected)
                    } else {
                        Text("非兼容设备")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func deviceDescription(_ device: NearbyBLEDevice, isCompatible: Bool) -> String {
        let connection = device.isConnectable ? "可连接" : "仅广播"
        let kind = isCompatible ? "FindUAS 接收器" : "其他 BLE 设备"
        return "\(device.rssi) dBm · \(connection) · \(kind)"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var bluetooth: BluetoothManager
    @State private var channels = "1, 6, 11"
    @State private var channelStayTime = 250
    @State private var vibrate = true
    @State private var sound = true
    @State private var flashLight = false
    @State private var showWriteConfirmation = false

    var body: some View {
        Form {
            Picker("协议模式", selection: $app.protocolMode) {
                Text("自动识别").tag(ProtocolMode.automatic)
                Text("Legacy").tag(ProtocolMode.legacy)
                Text("V2").tag(ProtocolMode.v2)
            }
            HStack {
                Text("告警半径")
                Slider(value: $app.alertRadius, in: 50...2_000, step: 50)
                Text("\(Int(app.alertRadius)) m").monospacedDigit().frame(width: 70)
            }
            LabeledContent("蓝牙服务", value: FindUASProtocol.serviceUUID)
            LabeledContent("遥测 / 配置", value: "\(FindUASProtocol.telemetryCharacteristicUUID) / \(FindUASProtocol.configurationCharacteristicUUID)")
            LabeledContent("检测到的协议", value: bluetooth.detectedProtocolMode?.rawValue ?? "尚未识别")
            VStack(alignment: .leading, spacing: 4) {
                Text("最近 BLE 数据").font(.caption).foregroundStyle(.secondary)
                Text(bluetooth.lastPacketSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Section("FF01 遥测诊断") {
                LabeledContent("收到的数据包", value: "\(bluetooth.telemetryPacketCount)")
                LabeledContent("组装出的 JSON 帧", value: "\(bluetooth.assembledTelemetryFrameCount)")
                LabeledContent("解码出的目标", value: "\(bluetooth.decodedTargetCount)")
                LabeledContent("拒绝的 JSON 帧", value: "\(bluetooth.rejectedTelemetryFrameCount)")
                Text(bluetooth.lastTelemetryPacketSummary)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("接收器配置") {
                TextField("信道（逗号分隔）", text: $channels)
                Stepper("信道驻留时间：\(channelStayTime)", value: $channelStayTime, in: 1...10_000)
                Toggle("震动", isOn: $vibrate)
                Toggle("声音", isOn: $sound)
                Toggle("闪光灯", isOn: $flashLight)
                if let battery = bluetooth.deviceConfiguration?.batteryPercent {
                    LabeledContent("设备电量", value: "\(battery)%")
                }
                Button("同步到接收器") {
                    showWriteConfirmation = true
                }
                .disabled(bluetooth.state != .connected)
                .confirmationDialog(
                    "写入接收器配置？",
                    isPresented: $showWriteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("写入 FF02") { writeConfiguration() }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text("这会修改已连接的 FindUAS / FindUAV Device。应用不会写入用途未知的 FF03。")
                }
            }

            Section("白名单") {
                if app.whitelist.isEmpty {
                    Text("白名单为空").foregroundStyle(.secondary)
                } else {
                    ForEach(app.whitelist.sorted(), id: \.self) { uasID in
                        HStack {
                            Text(uasID).font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("移除") { app.toggleWhitelist(uasID) }
                        }
                    }
                }
            }
        }
        .padding()
        .navigationTitle("设置")
        .onReceive(bluetooth.$deviceConfiguration.compactMap { $0 }) { configuration in
            channels = configuration.channels.map(String.init).joined(separator: ", ")
            channelStayTime = configuration.channelStayTime
            vibrate = configuration.vibrate
            sound = configuration.sound
            flashLight = configuration.flashLight
        }
    }

    private func writeConfiguration() {
        let parsedChannels = channels
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        bluetooth.updateDeviceConfiguration(DeviceConfiguration(
            channels: parsedChannels,
            channelStayTime: channelStayTime,
            vibrate: vibrate,
            sound: sound,
            flashLight: flashLight
        ))
    }
}

private struct StatusBadge: View {
    let state: BluetoothManager.State

    var body: some View {
        Label(state.rawValue, systemImage: state == .connected ? "checkmark.circle.fill" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(state == .connected ? .green : state == .failed ? .red : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }
}
