import Foundation

/// A deliberately small allow-list of regulatory regions recovered from DJI's
/// product-configuration area-code implementation. Values are ISO 3166-1, not
/// RF-power presets and not Remote ID packet-format selectors.
public enum DJIRegulatoryRegion: String, Codable, CaseIterable, Sendable {
    case australia
    case china
    case france
    case germany
    case japan
    case singapore
    case unitedArabEmirates
    case unitedKingdom
    case unitedStates

    public var alpha2: String {
        switch self {
        case .australia: "AU"
        case .china: "CN"
        case .france: "FR"
        case .germany: "DE"
        case .japan: "JP"
        case .singapore: "SG"
        case .unitedArabEmirates: "AE"
        case .unitedKingdom: "GB"
        case .unitedStates: "US"
        }
    }

    public var isoNumeric: UInt16 {
        switch self {
        case .australia: 36
        case .china: 156
        case .france: 250
        case .germany: 276
        case .japan: 392
        case .singapore: 702
        case .unitedArabEmirates: 784
        case .unitedKingdom: 826
        case .unitedStates: 840
        }
    }

    public var displayName: String {
        switch self {
        case .australia: "澳大利亚"
        case .china: "中国"
        case .france: "法国"
        case .germany: "德国"
        case .japan: "日本"
        case .singapore: "新加坡"
        case .unitedArabEmirates: "阿联酋"
        case .unitedKingdom: "英国"
        case .unitedStates: "美国"
        }
    }

    public init?(alpha2: String) {
        guard let match = Self.allCases.first(where: { $0.alpha2 == alpha2.uppercased() }) else {
            return nil
        }
        self = match
    }

    public init?(isoNumeric: UInt16) {
        guard let match = Self.allCases.first(where: { $0.isoNumeric == isoNumeric }) else {
            return nil
        }
        self = match
    }
}

/// Region policy is spread across separate DJI components. A value on one
/// surface must never be presented as the state of all the others.
public enum DJIRegionSurface: String, Codable, CaseIterable, Sendable {
    case flightControllerArea
    case airlinkSkyCountry
    case airlinkGroundCountry
    case remoteControllerPolicy

    public var displayName: String {
        switch self {
        case .flightControllerArea: "飞控 area"
        case .airlinkSkyCountry: "Sky country"
        case .airlinkGroundCountry: "Ground country"
        case .remoteControllerPolicy: "遥控器 / DJI Fly policy"
        }
    }
}

public enum DJIRegionSurfaceValue: Codable, Equatable, Sendable {
    case region(DJIRegulatoryRegion)
    case unavailable

    public var region: DJIRegulatoryRegion? {
        guard case let .region(region) = self else { return nil }
        return region
    }
}

public struct DJIRegionSnapshot: Codable, Equatable, Sendable {
    public let flightControllerArea: DJIRegionSurfaceValue
    public let airlinkSkyCountry: DJIRegionSurfaceValue
    public let airlinkGroundCountry: DJIRegionSurfaceValue
    public let remoteControllerPolicy: DJIRegionSurfaceValue

    public init(
        flightControllerArea: DJIRegionSurfaceValue,
        airlinkSkyCountry: DJIRegionSurfaceValue,
        airlinkGroundCountry: DJIRegionSurfaceValue,
        remoteControllerPolicy: DJIRegionSurfaceValue = .unavailable
    ) {
        self.flightControllerArea = flightControllerArea
        self.airlinkSkyCountry = airlinkSkyCountry
        self.airlinkGroundCountry = airlinkGroundCountry
        self.remoteControllerPolicy = remoteControllerPolicy
    }

    public subscript(surface: DJIRegionSurface) -> DJIRegionSurfaceValue {
        switch surface {
        case .flightControllerArea: flightControllerArea
        case .airlinkSkyCountry: airlinkSkyCountry
        case .airlinkGroundCountry: airlinkGroundCountry
        case .remoteControllerPolicy: remoteControllerPolicy
        }
    }

    /// A complete experimental region transaction currently requires all
    /// three USB-addressable surfaces to agree. RC/Fly policy remains an
    /// explicitly unknown fourth surface.
    public var usbSurfacesAgree: Bool {
        guard
            let fc = flightControllerArea.region,
            let sky = airlinkSkyCountry.region,
            let ground = airlinkGroundCountry.region
        else { return false }
        return fc == sky && sky == ground
    }

    public var agreedUSBRegion: DJIRegulatoryRegion? {
        guard usbSurfacesAgree else { return nil }
        return flightControllerArea.region
    }
}

public enum DJIRegionTransactionPhase: String, Codable, CaseIterable, Sendable {
    case snapshotDurable
    case applyingFlightController
    case applyingSky
    case applyingGround
    case activeVerified
    case rollbackRequested
    case restoringGround
    case restoringSky
    case restoringFlightController
    case restored
    case recoveryRequired
}

/// Minimal crash-recovery record. It intentionally contains no serial number,
/// account, coordinate, raw DUML frame, UAS ID, or operator identity.
public struct DJIRegionRecoveryJournal: Codable, Equatable, Sendable {
    public static let formatVersion = 1

    public let formatVersion: Int
    public let original: DJIRegionSnapshot
    public let target: DJIRegulatoryRegion
    /// Random per-process transaction scope. It is not a device identifier.
    /// A journal from a previous process may be inspected but must not trigger
    /// automatic writes without a separately verified device-pair binding.
    public let processSessionID: UUID
    public var phase: DJIRegionTransactionPhase
    public let createdAt: Date
    public var leaseExpiresAt: Date?

    public init(
        original: DJIRegionSnapshot,
        target: DJIRegulatoryRegion,
        processSessionID: UUID = UUID(),
        phase: DJIRegionTransactionPhase = .snapshotDurable,
        createdAt: Date = Date(),
        leaseExpiresAt: Date? = nil
    ) {
        formatVersion = Self.formatVersion
        self.original = original
        self.target = target
        self.processSessionID = processSessionID
        self.phase = phase
        self.createdAt = createdAt
        self.leaseExpiresAt = leaseExpiresAt
    }
}

public enum DJIRegionReconciliationDecision: Equatable, Sendable {
    case alreadyRestored
    case targetStillActive
    case partialTargetState
    case thirdPartyState
    case unavailable
}

/// Classifies a post-timeout or post-crash readback without issuing a write.
/// A third value is treated as concurrent ownership and must never be
/// overwritten automatically.
public func classifyDJIRegionReconciliation(
    current: DJIRegionSnapshot,
    journal: DJIRegionRecoveryJournal
) -> DJIRegionReconciliationDecision {
    let writableSurfaces: [DJIRegionSurface] = [
        .flightControllerArea,
        .airlinkSkyCountry,
        .airlinkGroundCountry,
    ]

    guard writableSurfaces.allSatisfy({ current[$0].region != nil }) else {
        return .unavailable
    }

    let originalMatches = writableSurfaces.map { surface in
        current[surface].region == journal.original[surface].region
    }
    if originalMatches.allSatisfy({ $0 }) {
        return .alreadyRestored
    }

    let targetMatches = writableSurfaces.map { current[$0].region == journal.target }
    if targetMatches.allSatisfy({ $0 }) {
        return .targetStillActive
    }

    let everyValueIsKnown = writableSurfaces.allSatisfy { surface in
        let value = current[surface].region
        return value == journal.original[surface].region || value == journal.target
    }
    if everyValueIsKnown {
        return .partialTargetState
    }
    return .thirdPartyState
}
