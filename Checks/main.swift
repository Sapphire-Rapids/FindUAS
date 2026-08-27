import CDJIUSBBridge
import FindUASCore
import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("CHECK FAILED: \(message)\n".utf8))
        exit(1)
    }
}

do {
    check(dji_usb_bridge_protocol_self_test() == 1, "fixed DJI USB protocol self-test")
    check(FindUASProtocol.isCompatibleAdvertisementName("FindUAS Device"), "FindUAS advertisement name")
    check(FindUASProtocol.isCompatibleAdvertisementName("finduav device"), "case-insensitive FindUAV advertisement name")
    check(!FindUASProtocol.isCompatibleAdvertisementName("DJI-TEST-AIRCRAFT"), "aircraft advertisement is not a receiver")

    var legacy = BLEFrameAssembler()
    let legacyPrefixFrames = try legacy.feed(Data(#"{"uas"#.utf8))
    check(legacyPrefixFrames.isEmpty, "split Legacy prefix")
    let legacyFrames = try legacy.feed(Data(#"Id":"ABC","uavLatitude":1.2}"#.utf8))
    check(legacyFrames.count == 1, "Legacy frame count")
    check(legacyFrames.first.flatMap { String(data: $0, encoding: .utf8) } == #"{"uasId":"ABC","uavLatitude":1.2}"#, "Legacy assembly")

    var escapedLegacy = BLEFrameAssembler()
    let escapedFrames = try escapedLegacy.feed(Data(#"\0\0{"message":"brace: } and quote: \"","uasid":"ESCAPED"}{"uasid":"SECOND"}"#.utf8))
    check(escapedFrames.count == 2, "back-to-back Legacy frames with escaped delimiters")

    var noisyLegacy = BLEFrameAssembler()
    var noise = Data(repeating: 0, count: 516)
    noise.append(Data(#"{"uasid":"AFTER-NOISE"}"#.utf8))
    let noisyFrames = try noisyLegacy.feed(noise)
    check(noisyFrames.count == 1, "idle FF01 noise is ignored")

    let json = #"{"uasid":"TEST-UAS-V2"}"#
    let encoded = try FindUASBLEProtocol.encode(json: json, mode: .v2)
    check(Array(encoded.prefix(3)) == [0x08, 0x17, 0x30], "V2 header")
    check(encoded[3] == UInt8(Data(json.utf8).count + 2) && encoded[4] == 0, "V2 little-endian length")
    check(Array(encoded.suffix(2)) == [0x3F, 0x55], "V2 tail")
    var v2 = BLEFrameAssembler()
    let v2PrefixFrames = try v2.feed(Data(encoded.prefix(4)))
    check(v2PrefixFrames.isEmpty, "split V2 prefix")
    let v2Frames = try v2.feed(Data(encoded.dropFirst(4)))
    check(v2Frames == [Data(json.utf8)], "V2 reassembly")

    var idleThenV2 = BLEFrameAssembler()
    let separateIdleFrames = try idleThenV2.feed(Data(repeating: 0, count: 516))
    check(separateIdleFrames.isEmpty, "separate idle FF01 packet is ignored")
    let afterIdleFrames = try idleThenV2.feed(encoded)
    check(afterIdleFrames == [Data(json.utf8)], "V2 frame after idle packet does not use stale Data indices")

    var consecutiveV2 = BLEFrameAssembler()
    var twoEncodedFrames = encoded
    twoEncodedFrames.append(encoded)
    let consecutiveFrames = try consecutiveV2.feed(twoEncodedFrames)
    check(consecutiveFrames == [Data(json.utf8), Data(json.utf8)], "consecutive V2 frames use relative Data indices")

    let nested = #"{"MonitorInfo":{"Name":"TEST-RECEIVER","SN":"TEST-RX-001","Ch":6},"UAVInfo":{"RID_Standard":"TEST-STANDARD","Reg":"TEST-REG-001","ID":"TEST-UAS-NESTED","Type":"Quadcopter","ID_Type":"Serial","Lat":30.1,"Lon":104.2,"Height":80,"AltGeo":512.5,"AltBaro":510.2,"H_Speed":8.5,"V_Speed":1.1,"Trk":175,"Sta":2,"coordinateSystem":"WGS-84","horizontalAccuracy":3,"verticalAccuracy":4,"speedAccuracy":1,"timestampAccuracy":0.1},"OperatorInfo":{"Lat":30.2,"Lon":104.3,"Operator Height":495.5,"Phone":"PHONE-TEST-ONLY"},"GPS":{"Fix_Type":3,"HDOP":0.8,"AltGeo":500.5,"Spkm":31.2,"Spkn":16.8,"Utc_Time":"102030","Utc_Date":"270826","NSat":12}}"#
    let telemetry = TelemetryDecoder().decode(Data(nested.utf8))
    check(telemetry.count == 1, "telemetry count")
    check(telemetry[0].monitorName == "TEST-RECEIVER", "monitor aliases")
    check(telemetry[0].operatorLongitude == 104.3, "operator aliases")
    check(telemetry[0].operatorAltitude == 495.5, "operator height alias")
    check(telemetry[0].operatorRegistrationPhone == "PHONE-TEST-ONLY", "explicit proprietary operator phone")
    check(telemetry[0].ridStandard == "TEST-STANDARD", "nested RID standard")
    check(telemetry[0].registrationID == "TEST-REG-001", "nested registration ID")
    check(telemetry[0].altitudeGeometric == 512.5 && telemetry[0].altitudeBarometric == 510.2, "dual aircraft altitude")
    check(telemetry[0].gpsAltitudeGeometric == 500.5, "GPS geometric altitude")
    check(telemetry[0].gpsSpeedKmh == 31.2 && telemetry[0].gpsSpeedKnots == 16.8, "GPS speed aliases")
    check(telemetry[0].gpsUTCTime == "102030" && telemetry[0].gpsUTCDate == "270826", "GPS UTC aliases")
    check(telemetry[0].coordinateSystem == "WGS-84", "coordinate system")
    check(telemetry[0].horizontalAccuracy == 3 && telemetry[0].timestampAccuracy == 0.1, "accuracy fields")
    check(telemetry[0].gpsSatelliteCount == 12, "GPS aliases")

    let unavailableValues = #"{"UAVInfo":{"ID":"SENTINELS","Lat":0,"Lon":0,"AltGeo":-1000,"Trk":361},"OperatorInfo":{"Lat":0,"Lon":0,"Operator Height":-1000}}"#
    let sanitized = TelemetryDecoder().decode(Data(unavailableValues.utf8))
    check(sanitized.first?.latitude == nil && sanitized.first?.longitude == nil, "unknown aircraft coordinates are removed")
    check(sanitized.first?.operatorLatitude == nil && sanitized.first?.operatorLongitude == nil, "unknown operator coordinates are removed")
    check(sanitized.first?.altitudeGeometric == nil && sanitized.first?.operatorAltitude == nil, "unknown altitude sentinels are removed")
    check(sanitized.first?.heading == nil, "unknown heading sentinel is removed")

    let receiveTime = Date(timeIntervalSince1970: 2_000_000_000)
    let uptimeTimestamp = #"{"MonitorInfo":{"Name":"RX","SN":"M"},"UAVInfo":{"ID":"UPTIME","T_Stamp":12},"OperatorInfo":{}}"#
    let uptimeTelemetry = TelemetryDecoder().decode(Data(uptimeTimestamp.utf8), receivedAt: receiveTime)
    check(uptimeTelemetry.first?.eventTime == nil, "relative Remote ID timestamp is not treated as Unix time")
    check(uptimeTelemetry.first?.lastSeen == receiveTime, "target freshness uses local receive time")

    let absoluteTimestamp = #"{"UAVInfo":{"ID":"EPOCH","eventTimeMs":1700000000000}}"#
    let absoluteTelemetry = TelemetryDecoder().decode(Data(absoluteTimestamp.utf8), receivedAt: receiveTime)
    check(absoluteTelemetry.first?.eventTime == Date(timeIntervalSince1970: 1_700_000_000), "absolute firmware timestamp is preserved")

    var session = TelemetrySession(targetLifetime: 120)
    let idleResult = try session.ingest(Data(repeating: 0, count: 516), receivedAt: receiveTime)
    check(idleResult.framesAssembled == 0 && idleResult.activeTargets.isEmpty, "idle FF01 block produces no target")
    let liveFrame = #"{"MonitorInfo":{"Name":"RX-1","SN":"M001"},"UAVInfo":{"ID":"LIVE-TARGET","Lat":30.1,"Lon":104.2,"T_Stamp":12},"OperatorInfo":{"Lat":30.2,"Lon":104.3}}"#
    let liveResult = try session.ingest(Data(liveFrame.utf8), receivedAt: receiveTime)
    check(liveResult.framesAssembled == 1, "end-to-end FF01 frame assembly")
    check(liveResult.targetsDecoded == 1, "end-to-end FF01 target decode")
    check(liveResult.activeTargets.first?.uasID == "LIVE-TARGET", "active target is published")
    check(liveResult.activeTargets.first?.lastSeen == receiveTime, "relative device timestamp cannot expire a fresh target")
    check(!session.prune(olderThan: receiveTime.addingTimeInterval(-120)), "fresh target survives pruning")
    check(session.prune(olderThan: receiveTime.addingTimeInterval(121)), "expired target is eventually pruned")

    let configuration = DeviceConfiguration(
        channels: [1, 6, 11], channelStayTime: 250, vibrate: true, sound: false, flashLight: true
    )
    let roundTrip = DeviceConfiguration.decode(Data(try configuration.updateJSON().utf8))
    check(roundTrip == configuration, "configuration JSON round trip")

    let capturedConfiguration = Data(#"{"sound":true,"flashLight":true,"vibrate":false,"channelStayTime":2,"batteryPercent":82,"channel":[6,149]}"#.utf8)
    let captured = DeviceConfiguration.decode(capturedConfiguration)
    check(captured?.channels == [6, 149], "captured device channels")
    check(captured?.batteryPercent == 82, "captured device battery")
    check(captured?.sound == true && captured?.flashLight == true, "captured device flags")

    check(RIDLabProfile.allCases.count == 10, "Remote ID lab exposes every validation profile")
    var lab = RIDLabSession()
    check(lab.phase == .complianceAuto, "Remote ID lab starts in compliance-auto")
    check(lab.broadcastIntent == .silent, "Remote ID lab starts with a silent intent")
    check(lab.sourceCapability.backend == .noRFBackend, "Remote ID lab identifies the no-RF backend")
    check(lab.sourceCapability.supportsDryRun, "no-RF backend supports dry-run")
    check(!lab.sourceCapability.canTransmitRemoteID, "no-RF backend cannot transmit Remote ID")
    check(!lab.sourceCapability.canWriteDevice, "no-RF backend cannot write a device")
    check(!lab.sourceCapability.canChangeDeviceRegion, "no-RF backend cannot change a device region")

    let labStart = Date(timeIntervalSince1970: 1_800_000_000)
    try lab.beginPrecheck(profile: .euIntegrated, at: labStart)
    check(lab.phase == .precheck && lab.selectedProfile == .euIntegrated, "lab enters profile precheck")
    do {
        try lab.stage(leaseMinutes: 5, at: labStart)
        check(false, "staging without checklist gates must fail")
    } catch let error as RIDLabError {
        guard case .missingChecklistItems(let items) = error else {
            check(false, "staging without gates reports missing checklist items")
            throw error
        }
        check(items.count == RIDLabChecklistItem.allCases.count, "every preflight gate is required")
    }
    do {
        try lab.stage(leaseMinutes: 4, at: labStart)
        check(false, "lease below five minutes must fail")
    } catch let error as RIDLabError {
        check(error == .invalidLeaseMinutes(4), "short lease validation error")
    }
    do {
        try lab.stage(leaseMinutes: 16, at: labStart)
        check(false, "lease above fifteen minutes must fail")
    } catch let error as RIDLabError {
        check(error == .invalidLeaseMinutes(16), "long lease validation error")
    }

    for item in RIDLabChecklistItem.allCases {
        try lab.setChecklistItem(item, satisfied: true, at: labStart)
    }
    try lab.setBroadcastIntent(.broadcast, at: labStart)
    check(lab.allChecklistItemsSatisfied, "all lab preflight gates can be satisfied")
    check(lab.broadcastIntent == .broadcast, "broadcast is captured only as a staged intent")
    try lab.stage(leaseMinutes: 15, at: labStart)
    check(lab.phase == .staged && lab.leaseMinutes == 15, "bounded lab lease is staged")
    do {
        try lab.setBroadcastIntent(.silent, at: labStart)
        check(false, "broadcast intent cannot change after staging")
    } catch let error as RIDLabError {
        check(
            error == .invalidTransition(expected: [.precheck], actual: .staged),
            "staged intent is immutable"
        )
    }

    let activationTime = labStart.addingTimeInterval(10)
    try lab.activateDryRun(at: activationTime)
    check(lab.phase == .activeDryRun, "staged lab scenario activates only as dry-run")
    check(
        lab.expiresAt == activationTime.addingTimeInterval(15 * 60),
        "active dry-run has a bounded expiration"
    )
    check(!lab.expire(at: activationTime.addingTimeInterval(15 * 60 - 1)), "lease does not expire early")
    check(lab.expire(at: activationTime.addingTimeInterval(15 * 60)), "lease expires at its deadline")
    check(lab.phase == .complianceAuto, "lease expiry restores compliance-auto")
    check(lab.selectedProfile == nil && lab.broadcastIntent == .silent, "expiry clears staged scenario state")
    check(lab.auditEvents.contains { $0.kind == .leaseExpired }, "lease expiry is audited")

    try lab.beginPrecheck(profile: .usModule, at: labStart)
    for item in RIDLabChecklistItem.allCases {
        try lab.setChecklistItem(item, satisfied: true, at: labStart)
    }
    try lab.stage(leaseMinutes: 5, at: labStart)
    try lab.activateDryRun(at: labStart)
    lab.stop(at: labStart)
    check(lab.phase == .complianceAuto && lab.expiresAt == nil, "Stop restores compliance-auto")

    try lab.beginPrecheck(profile: .japan, at: labStart)
    for item in RIDLabChecklistItem.allCases {
        try lab.setChecklistItem(item, satisfied: true, at: labStart)
    }
    try lab.stage(leaseMinutes: 5, at: labStart)
    try lab.beginRollback(at: labStart)
    check(lab.phase == .rollback, "explicit rollback state is observable")
    try lab.completeRollback(at: labStart)
    check(lab.phase == .complianceAuto, "completed rollback restores compliance-auto")

    lab.enterLockout(reason: .manualSafetyInterlock, at: labStart)
    lab.stop(at: labStart)
    check(lab.phase == .lockout, "Stop cannot bypass a safety lockout")
    try lab.resetLockout(at: labStart)
    check(lab.phase == .complianceAuto, "explicit reset clears lockout")

    try lab.beginPrecheck(profile: .raw, at: labStart)
    for offset in 0..<150 {
        try lab.setChecklistItem(
            .controlledTestArea,
            satisfied: offset.isMultiple(of: 2),
            at: labStart.addingTimeInterval(TimeInterval(offset))
        )
    }
    check(
        lab.auditEvents.count == RIDLabSession.maximumAuditEventCount,
        "redacted in-memory audit is bounded"
    )

    let expectedRegions: [(DJIRegulatoryRegion, String, UInt16)] = [
        (.australia, "AU", 36),
        (.china, "CN", 156),
        (.france, "FR", 250),
        (.germany, "DE", 276),
        (.japan, "JP", 392),
        (.singapore, "SG", 702),
        (.unitedArabEmirates, "AE", 784),
        (.unitedKingdom, "GB", 826),
        (.unitedStates, "US", 840),
    ]
    for (region, alpha2, numeric) in expectedRegions {
        check(region.alpha2 == alpha2 && region.isoNumeric == numeric, "DJI ISO region mapping \(alpha2)")
        check(DJIRegulatoryRegion(alpha2: alpha2.lowercased()) == region, "case-insensitive alpha-2 region parse")
        check(DJIRegulatoryRegion(isoNumeric: numeric) == region, "numeric region parse")
    }
    check(DJIRegulatoryRegion(alpha2: "ZZ") == nil, "unknown alpha-2 region is rejected")
    check(DJIRegulatoryRegion(isoNumeric: 999) == nil, "unknown numeric region is rejected")

    let originalRegionSnapshot = DJIRegionSnapshot(
        flightControllerArea: .region(.china),
        airlinkSkyCountry: .region(.china),
        airlinkGroundCountry: .region(.china)
    )
    check(originalRegionSnapshot.usbSurfacesAgree, "FC, Sky, and Ground agreement is explicit")
    check(originalRegionSnapshot.agreedUSBRegion == .china, "agreed USB region is exposed only on agreement")
    let recoveryJournal = DJIRegionRecoveryJournal(
        original: originalRegionSnapshot,
        target: .unitedStates,
        processSessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        createdAt: labStart,
        leaseExpiresAt: labStart.addingTimeInterval(60)
    )
    let targetRegionSnapshot = DJIRegionSnapshot(
        flightControllerArea: .region(.unitedStates),
        airlinkSkyCountry: .region(.unitedStates),
        airlinkGroundCountry: .region(.unitedStates)
    )
    let partialRegionSnapshot = DJIRegionSnapshot(
        flightControllerArea: .region(.china),
        airlinkSkyCountry: .region(.unitedStates),
        airlinkGroundCountry: .region(.china)
    )
    let thirdPartyRegionSnapshot = DJIRegionSnapshot(
        flightControllerArea: .region(.china),
        airlinkSkyCountry: .region(.japan),
        airlinkGroundCountry: .region(.china)
    )
    let unavailableRegionSnapshot = DJIRegionSnapshot(
        flightControllerArea: .region(.china),
        airlinkSkyCountry: .unavailable,
        airlinkGroundCountry: .region(.china)
    )
    check(
        classifyDJIRegionReconciliation(current: originalRegionSnapshot, journal: recoveryJournal) == .alreadyRestored,
        "reconciliation recognizes the original vector"
    )
    check(
        classifyDJIRegionReconciliation(current: targetRegionSnapshot, journal: recoveryJournal) == .targetStillActive,
        "reconciliation recognizes the complete target vector"
    )
    check(
        classifyDJIRegionReconciliation(current: partialRegionSnapshot, journal: recoveryJournal) == .partialTargetState,
        "reconciliation recognizes a partial transaction"
    )
    check(
        classifyDJIRegionReconciliation(current: thirdPartyRegionSnapshot, journal: recoveryJournal) == .thirdPartyState,
        "reconciliation refuses an unrelated third value"
    )
    check(
        classifyDJIRegionReconciliation(current: unavailableRegionSnapshot, journal: recoveryJournal) == .unavailable,
        "reconciliation refuses incomplete readback"
    )
    print("FindUASCoreChecks: all checks passed")
} catch {
    FileHandle.standardError.write(Data("CHECK FAILED WITH ERROR: \(error)\n".utf8))
    exit(1)
}
