import Foundation

/// A receiver-validation scenario. Selecting a profile never changes an aircraft,
/// receiver, account, radio region, or operating-system setting.
public enum RIDLabProfile: String, Codable, CaseIterable, Sendable {
    case raw
    case usStandard
    case usModule
    case euIntegrated
    case euAddOn
    case japan
    case china
    case uk
    case singapore
    case franceEID

    public var displayName: String {
        switch self {
        case .raw: "原始字段验证"
        case .usStandard: "美国 · 标准型"
        case .usModule: "美国 · 广播模块"
        case .euIntegrated: "欧盟 · 内置型"
        case .euAddOn: "欧盟 · 加装型"
        case .japan: "日本"
        case .china: "中国"
        case .uk: "英国"
        case .singapore: "新加坡"
        case .franceEID: "法国 · EID"
        }
    }
}

/// The desired behavior of a future, separately controlled laboratory source.
/// This value is an inert scenario input while `sourceCapability` is `.noRFBackend`.
public enum RIDLabBroadcastIntent: String, Codable, CaseIterable, Sendable {
    case silent
    case broadcast

    public var displayName: String {
        switch self {
        case .silent: "无信号"
        case .broadcast: "播报 Remote ID"
        }
    }
}

public enum RIDLabPhase: String, Codable, CaseIterable, Sendable {
    case complianceAuto
    case precheck
    case staged
    case activeDryRun
    case rollback
    case lockout

    public var displayName: String {
        switch self {
        case .complianceAuto: "合规自动"
        case .precheck: "安全预检"
        case .staged: "已暂存"
        case .activeDryRun: "Dry-run 运行中"
        case .rollback: "正在回滚"
        case .lockout: "安全锁定"
        }
    }
}

public enum RIDLabChecklistItem: String, Codable, CaseIterable, Hashable, Sendable {
    case controlledTestArea
    case regulatoryAuthorizationConfirmed
    case syntheticIdentityConfirmed
    case independentReceiverReady
    case emergencyStopReady

    public var displayName: String {
        switch self {
        case .controlledTestArea: "测试区域已隔离并受控"
        case .regulatoryAuthorizationConfirmed: "已确认法规与场地授权"
        case .syntheticIdentityConfirmed: "仅使用合成测试身份"
        case .independentReceiverReady: "独立监测设备已就绪"
        case .emergencyStopReady: "停止与回滚措施已就绪"
        }
    }
}

public enum RIDLabSourceBackend: String, Codable, Sendable {
    case noRFBackend
}

/// Capability truth for the currently compiled source adapter. The initial
/// implementation intentionally cannot transmit or write any attached device.
public struct RIDLabSourceCapability: Codable, Equatable, Sendable {
    public let backend: RIDLabSourceBackend
    public let supportsDryRun: Bool
    public let canTransmitRemoteID: Bool
    public let canWriteDevice: Bool
    public let canChangeDeviceRegion: Bool

    public static let noRFBackend = RIDLabSourceCapability(
        backend: .noRFBackend,
        supportsDryRun: true,
        canTransmitRemoteID: false,
        canWriteDevice: false,
        canChangeDeviceRegion: false
    )

    private init(
        backend: RIDLabSourceBackend,
        supportsDryRun: Bool,
        canTransmitRemoteID: Bool,
        canWriteDevice: Bool,
        canChangeDeviceRegion: Bool
    ) {
        self.backend = backend
        self.supportsDryRun = supportsDryRun
        self.canTransmitRemoteID = canTransmitRemoteID
        self.canWriteDevice = canWriteDevice
        self.canChangeDeviceRegion = canChangeDeviceRegion
    }
}

public enum RIDLabLockoutReason: String, Codable, Sendable {
    case manualSafetyInterlock
    case sourceStateMismatch
    case rollbackFailed
}

public enum RIDLabAuditKind: String, Codable, Sendable {
    case precheckStarted
    case checklistUpdated
    case broadcastIntentUpdated
    case staged
    case dryRunActivated
    case rollbackStarted
    case complianceRestored
    case leaseExpired
    case lockoutEntered
    case lockoutReset
}

/// A deliberately redacted audit record. It has no free-text payload and no
/// fields for UAS IDs, account data, coordinates, credentials, or raw frames.
public struct RIDLabAuditEvent: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let timestamp: Date
    public let kind: RIDLabAuditKind
    public let phase: RIDLabPhase
    public let profile: RIDLabProfile?
    public let broadcastIntent: RIDLabBroadcastIntent
    public let checklistItem: RIDLabChecklistItem?
    public let checklistSatisfied: Bool?
    public let leaseMinutes: Int?
    public let lockoutReason: RIDLabLockoutReason?
}

public enum RIDLabError: Error, Equatable, Sendable {
    case invalidTransition(expected: [RIDLabPhase], actual: RIDLabPhase)
    case invalidLeaseMinutes(Int)
    case missingChecklistItems([RIDLabChecklistItem])
}

/// A pure, in-memory state machine for staging laboratory validation scenarios.
/// It performs no device, network, file-system, Bluetooth, Wi-Fi, or RF I/O.
public struct RIDLabSession: Sendable {
    public static let allowedLeaseMinutes = 5...15
    public static let maximumAuditEventCount = 128

    public private(set) var phase: RIDLabPhase
    public private(set) var selectedProfile: RIDLabProfile?
    public private(set) var broadcastIntent: RIDLabBroadcastIntent
    public private(set) var leaseMinutes: Int?
    public private(set) var checklist: [RIDLabChecklistItem: Bool]
    public private(set) var expiresAt: Date?
    public private(set) var auditEvents: [RIDLabAuditEvent]
    public let sourceCapability: RIDLabSourceCapability

    private var nextAuditSequence: UInt64

    public init() {
        phase = .complianceAuto
        selectedProfile = nil
        broadcastIntent = .silent
        leaseMinutes = nil
        checklist = Self.emptyChecklist
        expiresAt = nil
        auditEvents = []
        sourceCapability = .noRFBackend
        nextAuditSequence = 1
    }

    public var missingChecklistItems: [RIDLabChecklistItem] {
        RIDLabChecklistItem.allCases.filter { checklist[$0] != true }
    }

    public var allChecklistItemsSatisfied: Bool {
        missingChecklistItems.isEmpty
    }

    public mutating func beginPrecheck(
        profile: RIDLabProfile,
        at timestamp: Date = Date()
    ) throws {
        try requirePhase([.complianceAuto])
        selectedProfile = profile
        broadcastIntent = .silent
        leaseMinutes = nil
        checklist = Self.emptyChecklist
        expiresAt = nil
        phase = .precheck
        appendAudit(.precheckStarted, at: timestamp)
    }

    public mutating func setChecklistItem(
        _ item: RIDLabChecklistItem,
        satisfied: Bool,
        at timestamp: Date = Date()
    ) throws {
        try requirePhase([.precheck])
        checklist[item] = satisfied
        appendAudit(
            .checklistUpdated,
            at: timestamp,
            checklistItem: item,
            checklistSatisfied: satisfied
        )
    }

    public mutating func setBroadcastIntent(
        _ intent: RIDLabBroadcastIntent,
        at timestamp: Date = Date()
    ) throws {
        try requirePhase([.precheck])
        broadcastIntent = intent
        appendAudit(.broadcastIntentUpdated, at: timestamp)
    }

    public mutating func stage(
        leaseMinutes requestedLeaseMinutes: Int,
        at timestamp: Date = Date()
    ) throws {
        try requirePhase([.precheck])
        guard Self.allowedLeaseMinutes.contains(requestedLeaseMinutes) else {
            throw RIDLabError.invalidLeaseMinutes(requestedLeaseMinutes)
        }
        let missing = missingChecklistItems
        guard missing.isEmpty else {
            throw RIDLabError.missingChecklistItems(missing)
        }

        leaseMinutes = requestedLeaseMinutes
        phase = .staged
        appendAudit(.staged, at: timestamp)
    }

    public mutating func activateDryRun(at timestamp: Date = Date()) throws {
        try requirePhase([.staged])
        let missing = missingChecklistItems
        guard missing.isEmpty else {
            throw RIDLabError.missingChecklistItems(missing)
        }
        guard let leaseMinutes, Self.allowedLeaseMinutes.contains(leaseMinutes) else {
            throw RIDLabError.invalidLeaseMinutes(leaseMinutes ?? 0)
        }

        expiresAt = timestamp.addingTimeInterval(TimeInterval(leaseMinutes * 60))
        phase = .activeDryRun
        appendAudit(.dryRunActivated, at: timestamp)
    }

    /// Returns `true` only when an active lease expired and was restored to the
    /// compliance-auto state during this call.
    @discardableResult
    public mutating func expire(at timestamp: Date = Date()) -> Bool {
        guard phase == .activeDryRun, let expiresAt, timestamp >= expiresAt else {
            return false
        }
        phase = .rollback
        self.expiresAt = nil
        appendAudit(.leaseExpired, at: timestamp)
        appendAudit(.rollbackStarted, at: timestamp)
        restoreCompliance(at: timestamp)
        return true
    }

    public mutating func beginRollback(at timestamp: Date = Date()) throws {
        try requirePhase([.staged, .activeDryRun])
        phase = .rollback
        expiresAt = nil
        appendAudit(.rollbackStarted, at: timestamp)
    }

    public mutating func completeRollback(at timestamp: Date = Date()) throws {
        try requirePhase([.rollback])
        restoreCompliance(at: timestamp)
    }

    /// Stops precheck, staged, rollback, or dry-run work and returns immediately
    /// to compliance-auto. A lockout is intentionally not cleared by Stop.
    public mutating func stop(at timestamp: Date = Date()) {
        switch phase {
        case .complianceAuto, .lockout:
            return
        case .precheck:
            restoreCompliance(at: timestamp)
        case .staged, .activeDryRun:
            phase = .rollback
            expiresAt = nil
            appendAudit(.rollbackStarted, at: timestamp)
            restoreCompliance(at: timestamp)
        case .rollback:
            restoreCompliance(at: timestamp)
        }
    }

    public mutating func enterLockout(
        reason: RIDLabLockoutReason,
        at timestamp: Date = Date()
    ) {
        expiresAt = nil
        phase = .lockout
        appendAudit(.lockoutEntered, at: timestamp, lockoutReason: reason)
    }

    public mutating func resetLockout(at timestamp: Date = Date()) throws {
        try requirePhase([.lockout])
        appendAudit(.lockoutReset, at: timestamp)
        restoreCompliance(at: timestamp)
    }

    private static var emptyChecklist: [RIDLabChecklistItem: Bool] {
        Dictionary(uniqueKeysWithValues: RIDLabChecklistItem.allCases.map { ($0, false) })
    }

    private mutating func restoreCompliance(at timestamp: Date) {
        phase = .complianceAuto
        selectedProfile = nil
        broadcastIntent = .silent
        leaseMinutes = nil
        checklist = Self.emptyChecklist
        expiresAt = nil
        appendAudit(.complianceRestored, at: timestamp)
    }

    private func requirePhase(_ expected: [RIDLabPhase]) throws {
        guard expected.contains(phase) else {
            throw RIDLabError.invalidTransition(expected: expected, actual: phase)
        }
    }

    private mutating func appendAudit(
        _ kind: RIDLabAuditKind,
        at timestamp: Date,
        checklistItem: RIDLabChecklistItem? = nil,
        checklistSatisfied: Bool? = nil,
        lockoutReason: RIDLabLockoutReason? = nil
    ) {
        auditEvents.append(
            RIDLabAuditEvent(
                sequence: nextAuditSequence,
                timestamp: timestamp,
                kind: kind,
                phase: phase,
                profile: selectedProfile,
                broadcastIntent: broadcastIntent,
                checklistItem: checklistItem,
                checklistSatisfied: checklistSatisfied,
                leaseMinutes: leaseMinutes,
                lockoutReason: lockoutReason
            )
        )
        nextAuditSequence &+= 1
        if auditEvents.count > Self.maximumAuditEventCount {
            auditEvents.removeFirst(auditEvents.count - Self.maximumAuditEventCount)
        }
    }
}
