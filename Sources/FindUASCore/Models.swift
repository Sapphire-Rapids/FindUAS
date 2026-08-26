import Foundation

public enum ProtocolMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case legacy
    case v2
}

public struct DroneTelemetry: Codable, Identifiable, Hashable, Sendable {
    public var id: String { uasID }

    public let uasID: String
    public var name: String?
    public var manufacturer: String?
    public var model: String?
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
    public var height: Double?
    public var horizontalSpeed: Double?
    public var verticalSpeed: Double?
    public var heading: Double?
    public var operatorLatitude: Double?
    public var operatorLongitude: Double?
    public var operatorAltitude: Double?
    /// A phone number is not part of standard Remote ID. This is populated only
    /// when receiver firmware explicitly supplies a proprietary phone field.
    public var operatorRegistrationPhone: String?
    public var rssi: Int?
    public var monitorName: String?
    public var monitorID: String?
    public var monitorTemperature: Double?
    public var monitorChannel: Int?
    public var uavType: String?
    public var uavIDType: String?
    public var ridStandard: String?
    public var registrationID: String?
    public var altitudeGeometric: Double?
    public var altitudeBarometric: Double?
    public var flightStatus: Int?
    public var eventTime: Date?
    public var gpsFixType: Int?
    public var gpsHDOP: Double?
    public var gpsAltitudeGeometric: Double?
    public var gpsSpeedKmh: Double?
    public var gpsSpeedKnots: Double?
    public var gpsUTCTime: String?
    public var gpsUTCDate: String?
    public var gpsSatelliteCount: Int?
    public var operationCategory: String?
    public var aircraftCategory: String?
    public var controlStationLocationType: String?
    public var coordinateSystem: String?
    public var horizontalAccuracy: Double?
    public var verticalAccuracy: Double?
    public var speedAccuracy: Double?
    public var timestampAccuracy: Double?
    public var emergencyStatus: String?
    public var firstSeen: Date
    public var lastSeen: Date

    public init(
        uasID: String,
        name: String? = nil,
        manufacturer: String? = nil,
        model: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        height: Double? = nil,
        horizontalSpeed: Double? = nil,
        verticalSpeed: Double? = nil,
        heading: Double? = nil,
        operatorLatitude: Double? = nil,
        operatorLongitude: Double? = nil,
        operatorAltitude: Double? = nil,
        operatorRegistrationPhone: String? = nil,
        rssi: Int? = nil,
        monitorName: String? = nil,
        monitorID: String? = nil,
        monitorTemperature: Double? = nil,
        monitorChannel: Int? = nil,
        uavType: String? = nil,
        uavIDType: String? = nil,
        ridStandard: String? = nil,
        registrationID: String? = nil,
        altitudeGeometric: Double? = nil,
        altitudeBarometric: Double? = nil,
        flightStatus: Int? = nil,
        eventTime: Date? = nil,
        gpsFixType: Int? = nil,
        gpsHDOP: Double? = nil,
        gpsAltitudeGeometric: Double? = nil,
        gpsSpeedKmh: Double? = nil,
        gpsSpeedKnots: Double? = nil,
        gpsUTCTime: String? = nil,
        gpsUTCDate: String? = nil,
        gpsSatelliteCount: Int? = nil,
        operationCategory: String? = nil,
        aircraftCategory: String? = nil,
        controlStationLocationType: String? = nil,
        coordinateSystem: String? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        speedAccuracy: Double? = nil,
        timestampAccuracy: Double? = nil,
        emergencyStatus: String? = nil,
        firstSeen: Date = Date(),
        lastSeen: Date = Date()
    ) {
        self.uasID = uasID
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.height = height
        self.horizontalSpeed = horizontalSpeed
        self.verticalSpeed = verticalSpeed
        self.heading = heading
        self.operatorLatitude = operatorLatitude
        self.operatorLongitude = operatorLongitude
        self.operatorAltitude = operatorAltitude
        self.operatorRegistrationPhone = operatorRegistrationPhone
        self.rssi = rssi
        self.monitorName = monitorName
        self.monitorID = monitorID
        self.monitorTemperature = monitorTemperature
        self.monitorChannel = monitorChannel
        self.uavType = uavType
        self.uavIDType = uavIDType
        self.ridStandard = ridStandard
        self.registrationID = registrationID
        self.altitudeGeometric = altitudeGeometric
        self.altitudeBarometric = altitudeBarometric
        self.flightStatus = flightStatus
        self.eventTime = eventTime
        self.gpsFixType = gpsFixType
        self.gpsHDOP = gpsHDOP
        self.gpsAltitudeGeometric = gpsAltitudeGeometric
        self.gpsSpeedKmh = gpsSpeedKmh
        self.gpsSpeedKnots = gpsSpeedKnots
        self.gpsUTCTime = gpsUTCTime
        self.gpsUTCDate = gpsUTCDate
        self.gpsSatelliteCount = gpsSatelliteCount
        self.operationCategory = operationCategory
        self.aircraftCategory = aircraftCategory
        self.controlStationLocationType = controlStationLocationType
        self.coordinateSystem = coordinateSystem
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speedAccuracy = speedAccuracy
        self.timestampAccuracy = timestampAccuracy
        self.emergencyStatus = emergencyStatus
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        normalizeUnavailableValues()
    }

    public mutating func merge(_ newer: DroneTelemetry) {
        name = newer.name ?? name
        manufacturer = newer.manufacturer ?? manufacturer
        model = newer.model ?? model
        latitude = newer.latitude ?? latitude
        longitude = newer.longitude ?? longitude
        altitude = newer.altitude ?? altitude
        height = newer.height ?? height
        horizontalSpeed = newer.horizontalSpeed ?? horizontalSpeed
        verticalSpeed = newer.verticalSpeed ?? verticalSpeed
        heading = newer.heading ?? heading
        operatorLatitude = newer.operatorLatitude ?? operatorLatitude
        operatorLongitude = newer.operatorLongitude ?? operatorLongitude
        operatorAltitude = newer.operatorAltitude ?? operatorAltitude
        operatorRegistrationPhone = newer.operatorRegistrationPhone ?? operatorRegistrationPhone
        rssi = newer.rssi ?? rssi
        monitorName = newer.monitorName ?? monitorName
        monitorID = newer.monitorID ?? monitorID
        monitorTemperature = newer.monitorTemperature ?? monitorTemperature
        monitorChannel = newer.monitorChannel ?? monitorChannel
        uavType = newer.uavType ?? uavType
        uavIDType = newer.uavIDType ?? uavIDType
        ridStandard = newer.ridStandard ?? ridStandard
        registrationID = newer.registrationID ?? registrationID
        altitudeGeometric = newer.altitudeGeometric ?? altitudeGeometric
        altitudeBarometric = newer.altitudeBarometric ?? altitudeBarometric
        flightStatus = newer.flightStatus ?? flightStatus
        eventTime = newer.eventTime ?? eventTime
        gpsFixType = newer.gpsFixType ?? gpsFixType
        gpsHDOP = newer.gpsHDOP ?? gpsHDOP
        gpsAltitudeGeometric = newer.gpsAltitudeGeometric ?? gpsAltitudeGeometric
        gpsSpeedKmh = newer.gpsSpeedKmh ?? gpsSpeedKmh
        gpsSpeedKnots = newer.gpsSpeedKnots ?? gpsSpeedKnots
        gpsUTCTime = newer.gpsUTCTime ?? gpsUTCTime
        gpsUTCDate = newer.gpsUTCDate ?? gpsUTCDate
        gpsSatelliteCount = newer.gpsSatelliteCount ?? gpsSatelliteCount
        operationCategory = newer.operationCategory ?? operationCategory
        aircraftCategory = newer.aircraftCategory ?? aircraftCategory
        controlStationLocationType = newer.controlStationLocationType ?? controlStationLocationType
        coordinateSystem = newer.coordinateSystem ?? coordinateSystem
        horizontalAccuracy = newer.horizontalAccuracy ?? horizontalAccuracy
        verticalAccuracy = newer.verticalAccuracy ?? verticalAccuracy
        speedAccuracy = newer.speedAccuracy ?? speedAccuracy
        timestampAccuracy = newer.timestampAccuracy ?? timestampAccuracy
        emergencyStatus = newer.emergencyStatus ?? emergencyStatus
        lastSeen = newer.lastSeen
        normalizeUnavailableValues()
    }

    /// Receiver firmware uses protocol sentinel values for unavailable data.
    /// Keep them out of maps, histories, and user-visible measurements.
    public mutating func normalizeUnavailableValues() {
        normalizeCoordinate(latitude: &latitude, longitude: &longitude)
        normalizeCoordinate(latitude: &operatorLatitude, longitude: &operatorLongitude)

        altitude = validAltitude(altitude)
        altitudeGeometric = validAltitude(altitudeGeometric)
        altitudeBarometric = validAltitude(altitudeBarometric)
        operatorAltitude = validAltitude(operatorAltitude)
        gpsAltitudeGeometric = validAltitude(gpsAltitudeGeometric)

        if let value = heading, !value.isFinite || value < 0 || value >= 360 { heading = nil }
        horizontalAccuracy = nonnegative(horizontalAccuracy)
        verticalAccuracy = nonnegative(verticalAccuracy)
        speedAccuracy = nonnegative(speedAccuracy)
        timestampAccuracy = nonnegative(timestampAccuracy)
        gpsHDOP = nonnegative(gpsHDOP)
    }

    private func validAltitude(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > -999 else { return nil }
        return value
    }

    private func nonnegative(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func normalizeCoordinate(latitude: inout Double?, longitude: inout Double?) {
        guard let lat = latitude, let lon = longitude,
              lat.isFinite, lon.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lon),
              !(lat == 0 && lon == 0) else {
            latitude = nil
            longitude = nil
            return
        }
    }
}

public struct KnownDroneModel: Codable, Hashable, Sendable {
    public let name: String
    public let manufactureName: String
    public let factoryCode: String
    public let typeId: Int?
    public let snPrefix: String
    public let weight: Double?
}

public struct DroneModelCatalog: Codable, Sendable {
    public let createAt: Int64
    public let models: [KnownDroneModel]

    public func match(uasID: String) -> KnownDroneModel? {
        models.first { !$0.snPrefix.isEmpty && uasID.uppercased().hasPrefix($0.snPrefix.uppercased()) }
    }
}
