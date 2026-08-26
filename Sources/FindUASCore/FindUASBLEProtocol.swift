import Foundation

public enum FindUASBLEProtocolError: Error, Equatable {
    case automaticModeCannotEncode
    case payloadTooLarge(Int)
}

public enum FindUASBLEProtocol {
    public static func encode(json: String, mode: ProtocolMode) throws -> Data {
        try encode(payload: Data(json.utf8), mode: mode)
    }

    public static func encode(payload: Data, mode: ProtocolMode) throws -> Data {
        switch mode {
        case .automatic:
            throw FindUASBLEProtocolError.automaticModeCannotEncode
        case .legacy:
            return payload
        case .v2:
            let framedLength = payload.count + BLEFrameAssembler.v2Tail.count
            guard framedLength <= UInt16.max else {
                throw FindUASBLEProtocolError.payloadTooLarge(payload.count)
            }
            var frame = BLEFrameAssembler.v2Header
            frame.append(UInt8(framedLength & 0xFF))
            frame.append(UInt8((framedLength >> 8) & 0xFF))
            frame.append(payload)
            frame.append(BLEFrameAssembler.v2Tail)
            return frame
        }
    }
}

public struct DeviceConfiguration: Codable, Equatable, Sendable {
    public var channels: [Int]
    public var channelStayTime: Int
    public var vibrate: Bool
    public var sound: Bool
    public var flashLight: Bool
    public var batteryPercent: Int?
    public var supports5GHz: Bool?

    public init(
        channels: [Int] = [],
        channelStayTime: Int = 0,
        vibrate: Bool = false,
        sound: Bool = false,
        flashLight: Bool = false,
        batteryPercent: Int? = nil,
        supports5GHz: Bool? = nil
    ) {
        self.channels = channels
        self.channelStayTime = channelStayTime
        self.vibrate = vibrate
        self.sound = sound
        self.flashLight = flashLight
        self.batteryPercent = batteryPercent
        self.supports5GHz = supports5GHz
    }

    public func updateJSON() throws -> String {
        let object: [String: Any] = [
            "channel": channels,
            "channelStayTime": channelStayTime,
            "vibrate": vibrate,
            "sound": sound,
            "flashLight": flashLight
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ payload: Data) -> DeviceConfiguration? {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return nil }
        return DeviceConfiguration(
            channels: intArray(object["channel"] ?? object["channelNumbers"]),
            channelStayTime: int(object["channelStayTime"]) ?? 0,
            vibrate: bool(object["vibrate"]) ?? false,
            sound: bool(object["sound"]) ?? false,
            flashLight: bool(object["flashLight"]) ?? false,
            batteryPercent: int(object["batteryPercent"]),
            supports5GHz: bool(object["support5GChannel"])
        )
    }

    private static func intArray(_ value: Any?) -> [Int] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(int)
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            if value == "1" || value.lowercased() == "true" { return true }
            if value == "0" || value.lowercased() == "false" { return false }
        }
        return nil
    }
}
