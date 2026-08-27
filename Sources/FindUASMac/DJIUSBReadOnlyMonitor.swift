import CDJIUSBBridge
import Combine
import Foundation

enum DJIUSBObservedValue: Equatable, Sendable {
    case value(String)
    case unavailable(String)
    case notApplicable(String)

    var displayValue: String {
        switch self {
        case let .value(value): value
        case .unavailable: "不可用"
        case .notApplicable: "不适用"
        }
    }

    var detail: String? {
        switch self {
        case .value: nil
        case let .unavailable(detail), let .notApplicable(detail): detail
        }
    }
}

struct DJIUSBReadOnlySnapshot: Sendable {
    let libusbAvailable: Bool
    let aircraftPresent: Bool
    let controllerPresent: Bool
    let flightControllerArea: DJIUSBObservedValue
    let skyCountry: DJIUSBObservedValue
    let groundCountry: DJIUSBObservedValue
    let franceEID: DJIUSBObservedValue
    let capturedAt: Date
}

@MainActor
final class DJIUSBReadOnlyMonitor: ObservableObject {
    @Published private(set) var snapshot: DJIUSBReadOnlySnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        errorMessage = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.capture()
            }.value
            snapshot = result.snapshot
            errorMessage = result.errorMessage
            isRefreshing = false
        }
    }

    nonisolated private static func capture() -> (
        snapshot: DJIUSBReadOnlySnapshot?,
        errorMessage: String?
    ) {
        var presence = DJIUSBBridgeDevicePresence()
        let presenceStatus = dji_usb_bridge_get_device_presence(&presence)
        guard presenceStatus == DJIUSB_BRIDGE_STATUS_OK else {
            return (nil, "DJI USB 枚举失败：\(statusDescription(presenceStatus))")
        }

        let aircraftPresent = presence.aircraft_present != 0
        let controllerPresent = presence.controller_present != 0
        let fc = aircraftPresent ? readFCArea() : .unavailable("未发现受支持的飞机 USB 端点")
        let sky = aircraftPresent ? readSkyCountry() : .unavailable("未发现受支持的飞机 USB 端点")
        let ground = controllerPresent ? readGroundCountry() : .unavailable("未发现受支持的 RC 2 USB 端点")

        let eid: DJIUSBObservedValue
        switch fc {
        case .value("FR"):
            eid = readFranceEID()
        case .value:
            eid = .notApplicable("只在 FC area 明确读回 FR 时查询法国 EID；当前不会发送 0x03/0x77。")
        case let .unavailable(detail):
            eid = .unavailable("FC area 不可用，未查询法国 EID：\(detail)")
        case let .notApplicable(detail):
            eid = .unavailable("无法判断 FC area，未查询法国 EID：\(detail)")
        }

        return (
            DJIUSBReadOnlySnapshot(
                libusbAvailable: presence.libusb_available != 0,
                aircraftPresent: aircraftPresent,
                controllerPresent: controllerPresent,
                flightControllerArea: fc,
                skyCountry: sky,
                groundCountry: ground,
                franceEID: eid,
                capturedAt: Date()
            ),
            nil
        )
    }

    nonisolated private static func readFCArea() -> DJIUSBObservedValue {
        var area = DJIUSBBridgeFCArea()
        let status = dji_usb_bridge_get_aircraft_fc_area(&area)
        guard status == DJIUSB_BRIDGE_STATUS_OK else {
            return .unavailable(statusDescription(status))
        }
        var tuple = area.alpha2
        let alpha2 = stringFromCBytes(&tuple)
        guard !alpha2.isEmpty else {
            return .unavailable("飞控返回了未列入实验白名单的 ISO 数字地区码")
        }
        return .value(alpha2)
    }

    nonisolated private static func readSkyCountry() -> DJIUSBObservedValue {
        var country = DJIUSBBridgeCountry()
        let status = dji_usb_bridge_get_sky_country(&country)
        guard status == DJIUSB_BRIDGE_STATUS_OK else {
            return .unavailable(statusDescription(status))
        }
        var tuple = country.alpha2
        return .value(stringFromCBytes(&tuple))
    }

    nonisolated private static func readGroundCountry() -> DJIUSBObservedValue {
        var country = DJIUSBBridgeCountry()
        let status = dji_usb_bridge_get_ground_country(&country)
        guard status == DJIUSB_BRIDGE_STATUS_OK else {
            return .unavailable(statusDescription(status))
        }
        var tuple = country.alpha2
        return .value(stringFromCBytes(&tuple))
    }

    nonisolated private static func readFranceEID() -> DJIUSBObservedValue {
        var statusValue = DJIUSBBridgeFranceEIDStatus()
        let status = dji_usb_bridge_get_france_eid_status(&statusValue)
        guard status == DJIUSB_BRIDGE_STATUS_OK else {
            return .unavailable(statusDescription(status))
        }
        return .value(statusValue.enabled != 0 ? "已启用" : "已停用")
    }

    nonisolated private static func stringFromCBytes<T>(_ tuple: inout T) -> String {
        withUnsafeBytes(of: &tuple) { bytes in
            let prefix = bytes.prefix { $0 != 0 }
            return String(decoding: prefix, as: UTF8.self)
        }
    }

    nonisolated private static func statusDescription(_ status: DJIUSBBridgeStatus) -> String {
        switch status {
        case DJIUSB_BRIDGE_STATUS_LIBUSB_UNAVAILABLE:
            "缺少 libusb 运行库"
        case DJIUSB_BRIDGE_STATUS_DEVICE_NOT_FOUND:
            "设备未连接"
        case DJIUSB_BRIDGE_STATUS_ACCESS_DENIED:
            "USB 访问被系统拒绝"
        case DJIUSB_BRIDGE_STATUS_INTERFACE_BUSY:
            "USB 接口正被其他程序占用"
        case DJIUSB_BRIDGE_STATUS_TIMEOUT:
            "设备没有返回匹配响应"
        case DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR:
            "响应未通过长度、CRC、路由或载荷校验"
        case DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT:
            "内部参数错误"
        default:
            "USB I/O 错误"
        }
    }
}
