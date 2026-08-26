import Foundation

/// Decodes both field naming schemes accepted by FindUAS Android 1.4.4.
public struct TelemetryDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data, receivedAt: Date = Date()) -> [DroneTelemetry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let array = root as? [Any] {
            return array.compactMap { ($0 as? [String: Any]).flatMap { decodeRoot($0, receivedAt: receivedAt) } }
        }
        guard let object = root as? [String: Any] else { return [] }

        if let direct = decodeRoot(object, receivedAt: receivedAt) { return [direct] }
        // Some firmware batches multiple complete messages under an arbitrary envelope.
        return object.values.compactMap { ($0 as? [String: Any]).flatMap { decodeRoot($0, receivedAt: receivedAt) } }
    }

    private func decodeRoot(_ root: [String: Any], receivedAt: Date) -> DroneTelemetry? {
        let monitor = dictionary(root, keys: ["MonitorInfo"]) ?? root
        let uav = dictionary(root, keys: ["UAVInfo"]) ?? root
        let operatorInfo = dictionary(root, keys: ["OperatorInfo"]) ?? root
        let gps = dictionary(root, keys: ["GPS", "GPSInfo"]) ?? root

        guard let uasID = string(uav, keys: ["uasid", "uasId", "uasID", "ID", "UAV ID", "remoteId", "remote_id", "serialNumber", "sn"]),
              !uasID.isEmpty else { return nil }

        let eventMilliseconds = number(uav, keys: ["eventTimeMs", "T_Stamp", "UAV TimeStamp"])
        let eventDate = eventMilliseconds.flatMap(normalizeEventTime)
        let type = string(uav, keys: ["uavType", "Type", "UAV Type"])

        return DroneTelemetry(
            uasID: uasID,
            name: string(uav, keys: ["uasName", "name", "droneName"]),
            manufacturer: string(uav, keys: ["manufactureName", "manufacturer", "brand"]),
            model: string(uav, keys: ["model", "modelName"]) ?? type,
            latitude: number(uav, keys: ["uavLatitude", "Lat", "UAV Latitude", "latitude", "lat"]),
            longitude: number(uav, keys: ["uavLongitude", "Lon", "UAV Longitude", "longitude", "lon", "lng"]),
            altitude: number(gps, keys: ["gpsAltGeo", "AltGeo"]) ?? number(uav, keys: ["altitude", "uavAltitude"]),
            height: number(uav, keys: ["uavHeight", "Height", "UAV Height", "height"]),
            horizontalSpeed: number(uav, keys: ["uavHorizontalSpeed", "H_Speed", "UAV Horizontal Speed", "horizontalSpeed", "speed"]),
            verticalSpeed: number(uav, keys: ["uavVerticalSpeed", "V_Speed", "UAV Vertical Speed", "verticalSpeed"]),
            heading: number(uav, keys: ["heading", "Trk", "direction", "track"]) ?? number(gps, keys: ["gpsTrack", "Trk"]),
            operatorLatitude: number(operatorInfo, keys: ["operatorLatitude", "Lat", "Operator Latitude", "pilotLatitude", "operatorLat"]),
            operatorLongitude: number(operatorInfo, keys: ["operatorLongitude", "Lon", "Operator Longitude", "pilotLongitude", "operatorLon", "operatorLng"]),
            operatorAltitude: number(operatorInfo, keys: ["operatorAltitude", "Height", "Operator Height", "AltGeo", "altitude"]),
            operatorRegistrationPhone: nonEmptyString(operatorInfo, keys: ["operatorPhone", "Operator Phone", "registrationPhone", "Registration Phone", "phone", "Phone", "mobile", "Mobile"])
                ?? nonEmptyString(root, keys: ["operatorPhone", "Operator Phone", "registrationPhone", "Registration Phone"]),
            rssi: integer(root, keys: ["rssi", "RSSI"]),
            monitorName: string(monitor, keys: ["monitorName", "Name", "MonitorName"]),
            monitorID: string(monitor, keys: ["monitorId", "SN", "MonitorUUID"]),
            monitorTemperature: number(monitor, keys: ["monitorTemp", "Temp"]),
            monitorChannel: integer(monitor, keys: ["monitorChannel", "Ch"]),
            uavType: type,
            uavIDType: string(uav, keys: ["uavIdType", "ID_Type", "UAV ID Type"]),
            ridStandard: nonEmptyString(uav, keys: ["ridStandard", "RID_Standard"])
                ?? nonEmptyString(root, keys: ["ridStandard", "RID_Standard"]),
            registrationID: nonEmptyString(uav, keys: ["regId", "Reg", "registrationID", "registrationId"])
                ?? nonEmptyString(root, keys: ["regId", "Reg", "registrationID", "registrationId"]),
            altitudeGeometric: number(uav, keys: ["altGeo", "AltGeo"]),
            altitudeBarometric: number(uav, keys: ["altBaro", "AltBaro"]),
            flightStatus: integer(uav, keys: ["flightStatus", "Sta"]),
            eventTime: eventDate,
            gpsFixType: integer(gps, keys: ["gpsFixType", "Fix_Type"]),
            gpsHDOP: number(gps, keys: ["gpsHdop", "HDOP"]),
            gpsAltitudeGeometric: number(gps, keys: ["gpsAltGeo", "AltGeo"]),
            gpsSpeedKmh: number(gps, keys: ["gpsSpeedKmh", "Spkm"]),
            gpsSpeedKnots: number(gps, keys: ["gpsSpeedKnots", "Spkn"]),
            gpsUTCTime: string(gps, keys: ["gpsUtcTime", "Utc_Time"]),
            gpsUTCDate: string(gps, keys: ["gpsUtcDate", "Utc_Date"]),
            gpsSatelliteCount: integer(gps, keys: ["gpsSatCount", "NSat"]),
            operationCategory: string(uav, keys: ["operationCategory", "Operation_Category", "operation_category"]),
            aircraftCategory: string(uav, keys: ["aircraftCategory", "Aircraft_Category", "aircraft_category"]),
            controlStationLocationType: string(operatorInfo, keys: ["locationType", "Location_Type", "controlStationLocationType", "Control_Station_Location_Type"]),
            coordinateSystem: string(uav, keys: ["coordinateSystem", "Coordinate_System", "coordinateSystemType", "Coord_Type"]),
            horizontalAccuracy: number(uav, keys: ["horizontalAccuracy", "Horizontal_Accuracy", "H_Accuracy"]),
            verticalAccuracy: number(uav, keys: ["verticalAccuracy", "Vertical_Accuracy", "V_Accuracy"]),
            speedAccuracy: number(uav, keys: ["speedAccuracy", "Speed_Accuracy"]),
            timestampAccuracy: number(uav, keys: ["timestampAccuracy", "Timestamp_Accuracy", "T_Accuracy"]),
            emergencyStatus: string(uav, keys: ["emergencyStatus", "Emergency_Status"]),
            firstSeen: receivedAt,
            // Firmware timestamps are payload metadata and have shipped as Unix time,
            // uptime, or zero. Target freshness must use the local receive time or a
            // valid target can be removed immediately as "stale".
            lastSeen: receivedAt
        )
    }

    private func dictionary(_ object: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys where object[key] is [String: Any] {
            return object[key] as? [String: Any]
        }
        return nil
    }

    private func string(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private func nonEmptyString(_ object: [String: Any], keys: [String]) -> String? {
        guard let value = string(object, keys: keys)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    private func number(_ object: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = object[key] as? NSNumber { return value.doubleValue }
            if let value = object[key] as? String, let number = Double(value) { return number }
        }
        return nil
    }

    private func integer(_ object: [String: Any], keys: [String]) -> Int? {
        number(object, keys: keys).map(Int.init)
    }

    private func normalizeEventTime(_ value: Double) -> Date? {
        guard value > 0, value.isFinite else { return nil }
        // Only accept plausible absolute timestamps. Remote ID Location timestamps
        // may instead be seconds after the current UTC hour; those are not dates.
        let seconds: Double
        if value >= 1_000_000_000_000_000 {
            seconds = value / 1_000_000
        } else if value >= 1_000_000_000_000 {
            seconds = value / 1_000
        } else {
            seconds = value
        }
        let date = Date(timeIntervalSince1970: seconds)
        guard let year = Calendar(identifier: .gregorian).dateComponents(in: .gmt, from: date).year,
              (2_000...2_100).contains(year) else { return nil }
        return date
    }
}
