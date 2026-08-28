import Combine
import FindUASCore
import SwiftUI

/// Main-actor adapter for the pure, in-memory `RIDLabSession` state machine.
/// This type deliberately owns no Bluetooth, USB, network, file, or RF handle.
@MainActor
final class RIDLabController: ObservableObject {
    @Published private(set) var session = RIDLabSession()
    @Published private(set) var errorMessage: String?

    private var expiryTimer: AnyCancellable?

    init() {
        expiryTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                var updated = self.session
                if updated.expire(at: now) {
                    self.session = updated
                    self.errorMessage = nil
                }
            }
    }

    func selectProfile(_ profile: RIDLabProfile) {
        mutate { session in
            if session.phase == .precheck {
                session.stop()
            }
            try session.beginPrecheck(profile: profile)
        }
    }

    func setBroadcastIntent(_ intent: RIDLabBroadcastIntent) {
        mutate { session in
            try session.setBroadcastIntent(intent)
        }
    }

    func setChecklistItem(_ item: RIDLabChecklistItem, satisfied: Bool) {
        mutate { session in
            try session.setChecklistItem(item, satisfied: satisfied)
        }
    }

    func stage(leaseMinutes: Int) {
        mutate { session in
            try session.stage(leaseMinutes: leaseMinutes)
        }
    }

    func activateDryRun() {
        mutate { session in
            try session.activateDryRun()
        }
    }

    func stop() {
        var updated = session
        updated.stop()
        session = updated
        errorMessage = nil
    }

    func resetLockout() {
        mutate { session in
            try session.resetLockout()
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func mutate(_ operation: (inout RIDLabSession) throws -> Void) {
        var updated = session
        do {
            try operation(&updated)
            session = updated
            errorMessage = nil
        } catch let error as RIDLabError {
            errorMessage = error.userFacingDescription
        } catch {
            errorMessage = "无法更新仅本机演练状态。"
        }
    }
}

struct AdminLabView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var bluetooth: BluetoothManager
    @EnvironmentObject private var ridLab: RIDLabController
    @EnvironmentObject private var djiUSB: DJIUSBReadOnlyMonitor

    @State private var requestedLeaseMinutes = 5
    @State private var showActivationConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            SafetyBoundaryBar()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    aircraftBoundaryCard
                    ridConfigurationCatalogCard
                    receiverDiagnosticsCard
                    scenarioCard
                    auditCard
                }
                .padding(20)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("兼容性实验室")
        .confirmationDialog(
            "开始仅本机演练？",
            isPresented: $showActivationConfirmation,
            titleVisibility: .visible
        ) {
            Button("开始 Dry-run") { ridLab.activateDryRun() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只启动有时限的内存状态机和脱敏审计日志；不会发射 Remote ID，也不会写入 DJI 飞机、遥控器或 FindUAS 接收器。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("管理员实验室（安全预览）")
                    .font(.largeTitle.bold())
                Text("为外部受控信号源准备验证场景；当前构建只有 no-RF dry-run 后端。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            LabPhaseBadge(phase: ridLab.session.phase)
        }
    }

    private var aircraftBoundaryCard: some View {
        GroupBox("DJI USB · 实机只读") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("固定 USB GET 状态", systemImage: "cable.connector")
                        .font(.headline)
                    Spacer()
                    if djiUSB.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button("读取设备状态") { djiUSB.refresh() }
                        .disabled(djiUSB.isRefreshing)
                }

                Text("点击读取后，Mac 会向已观测的 DJI USB VID/PID 路由发送固定 GET。它不读取序列号，不能证明仍是同一对设备；也不是 FindUAS 接收器扫描飞机。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let error = djiUSB.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                if let snapshot = djiUSB.snapshot {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        usbStatusRow("飞机 USB · 2ca3:0020", present: snapshot.aircraftPresent)
                        usbStatusRow("遥控器 USB · 2ca3:1021", present: snapshot.controllerPresent)
                        observedStatusRow("飞控 area", value: snapshot.flightControllerArea)
                        observedStatusRow("Sky country", value: snapshot.skyCountry)
                        observedStatusRow("Ground country", value: snapshot.groundCountry)
                        observedStatusRow("RC / DJI Fly policy", value: .unavailable("当前没有可信的只读路由"))
                        observedStatusRow("法国 EID", value: snapshot.franceEID)
                    }

                    Text("读取时间：\(snapshot.capturedAt.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if !djiUSB.isRefreshing {
                    Text("尚未读取 DJI USB 状态。")
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("通用 Remote ID")
                        Label("未实现", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("本应用不实现：尚未发现并验证通用 setter；法国 EID 不能冒充通用开关")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GridRow {
                        Text("地区事务")
                        Label("无 writer", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text("应用 writer 未上线；Sky 研究闭环已验证，Ground SET 与稳定设备对绑定仍未验证")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Label(
                    "读取结果中的“不可用”不是“关闭”。下方配置文件仍只是 no-RF 演练，不会写飞机、遥控器或接收器。",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var ridConfigurationCatalogCard: some View {
        GroupBox("RID 配置面目录 · 只读") {
            VStack(alignment: .leading, spacing: 12) {
                Label(RIDConfigurationCatalog.safetyBoundaryText, systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)

                Text(RIDConfigurationCatalog.privacyBoundaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text(RIDConfigurationCatalog.scopeBoundaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(RIDConfigurationCatalog.currentBuild) { surface in
                        RIDConfigurationSurfaceCard(surface: surface)
                    }
                }

                Text("分类表示当前证据与访问成熟度，不表示某项功能已开启。外部合成源与 DJI 设备面严格分离。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private func usbStatusRow(_ label: String, present: Bool) -> some View {
        GridRow {
            Text(label)
            Text(present ? "已发现" : "未发现")
                .foregroundStyle(present ? .green : .secondary)
            Text("")
        }
    }

    @ViewBuilder
    private func observedStatusRow(_ label: String, value: DJIUSBObservedValue) -> some View {
        GridRow {
            Text(label)
            Text(value.displayValue)
                .font(.body.monospaced())
            Text(value.detail ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var receiverDiagnosticsCard: some View {
        GroupBox("FindUAS 接收器 · 只读诊断") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ReceiverStateBadge(state: bluetooth.state)
                    Spacer()
                    Text("存活目标：\(app.visibleDrones.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                    GridRow {
                        LabeledContent("FF01 数据包", value: "\(bluetooth.telemetryPacketCount)")
                        LabeledContent("组装帧", value: "\(bluetooth.assembledTelemetryFrameCount)")
                    }
                    GridRow {
                        LabeledContent("解码目标", value: "\(bluetooth.decodedTargetCount)")
                        LabeledContent("拒绝帧", value: "\(bluetooth.rejectedTelemetryFrameCount)")
                    }
                    GridRow {
                        LabeledContent("FF01 包装", value: bluetooth.detectedProtocolMode?.rawValue ?? "尚未识别")
                        LabeledContent("接收器配置写入", value: "本页不执行")
                    }
                }
                .monospacedDigit()

                Text("这些计数来自现有接收器会话，仅作为独立观测证据；演练状态不会发布到实时目标、历史记录、地图、告警或白名单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }

    private var scenarioCard: some View {
        GroupBox("受控验证场景") {
            VStack(alignment: .leading, spacing: 14) {
                if let error = ridLab.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("关闭") { ridLab.clearError() }
                            .buttonStyle(.borderless)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("验证配置文件")
                        Picker("验证配置文件", selection: profileSelection) {
                            Text("请选择…").tag("")
                            ForEach(RIDLabProfile.allCases, id: \.rawValue) { profile in
                                Text(profile.displayName).tag(profile.rawValue)
                            }
                        }
                        .labelsHidden()
                        .disabled(!canEditPrecheck)
                    }

                    GridRow {
                        Text("外部信号源期望状态")
                        Picker("外部信号源期望状态", selection: broadcastIntentSelection) {
                            ForEach(RIDLabBroadcastIntent.allCases, id: \.rawValue) { intent in
                                Text(intent.displayName).tag(intent.rawValue)
                            }
                        }
                        .labelsHidden()
                        .disabled(ridLab.session.phase != .precheck)
                    }

                    GridRow {
                        Text("安全租约")
                        Stepper(
                            "\(requestedLeaseMinutes) 分钟",
                            value: $requestedLeaseMinutes,
                            in: RIDLabSession.allowedLeaseMinutes
                        )
                        .disabled(ridLab.session.phase != .precheck)
                    }
                }

                Label(
                    expectedSourceExplanation,
                    systemImage: ridLab.session.broadcastIntent == .broadcast
                        ? "antenna.radiowaves.left.and.right.slash"
                        : "speaker.slash"
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("安全预检")
                        .font(.headline)
                    ForEach(RIDLabChecklistItem.allCases, id: \.rawValue) { item in
                        Toggle(item.displayName, isOn: checklistBinding(for: item))
                            .disabled(ridLab.session.phase != .precheck)
                    }
                }

                Divider()

                sessionSummary

                HStack(spacing: 10) {
                    Button("暂存演练") {
                        ridLab.stage(leaseMinutes: requestedLeaseMinutes)
                    }
                    .disabled(!canStage)

                    Button("开始仅本机演练") {
                        showActivationConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ridLab.session.phase != .staged)

                    Button("停止并回滚", role: .destructive) {
                        ridLab.stop()
                    }
                    .disabled(!canStop)

                    if ridLab.session.phase == .lockout {
                        Button("解除本机锁定") { ridLab.resetLockout() }
                    }
                }
            }
            .padding(4)
        }
    }

    @ViewBuilder
    private var sessionSummary: some View {
        switch ridLab.session.phase {
        case .complianceAuto:
            Label("尚未暂存验证场景。先选择配置文件并完成全部安全预检。", systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        case .precheck:
            let remaining = ridLab.session.missingChecklistItems.count
            Label(
                remaining == 0 ? "安全预检已完成，可以暂存。" : "仍有 \(remaining) 项安全预检未确认。",
                systemImage: remaining == 0 ? "checkmark.circle" : "circle.dashed"
            )
            .foregroundStyle(remaining == 0 ? .green : .secondary)
        case .staged:
            Label("场景已暂存，但尚未开始；不会发射或写入设备。", systemImage: "pause.circle")
                .foregroundStyle(.orange)
        case .activeDryRun:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label(
                    "仅本机演练运行中 · 剩余 \(remainingLease(at: context.date))",
                    systemImage: "play.circle.fill"
                )
                .foregroundStyle(.blue)
            }
        case .rollback:
            Label("正在恢复合规自动状态。", systemImage: "arrow.uturn.backward.circle")
                .foregroundStyle(.orange)
        case .lockout:
            Label("状态机已安全锁定；当前后端仍没有 RF 或设备写入能力。", systemImage: "lock.shield.fill")
                .foregroundStyle(.red)
        }
    }

    private var auditCard: some View {
        GroupBox("脱敏审计日志 · 仅内存") {
            VStack(alignment: .leading, spacing: 8) {
                Text("不记录 UAS ID、账号、序列号、坐标、凭据、原始帧或自由文本；退出应用后不会保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if ridLab.session.auditEvents.isEmpty {
                    ContentUnavailableView(
                        "尚无演练事件",
                        systemImage: "list.bullet.clipboard",
                        description: Text("选择验证配置文件后，会在这里显示状态机事件。")
                    )
                    .frame(minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(ridLab.session.auditEvents.reversed()), id: \.sequence) { event in
                            AuditEventRow(event: event)
                            if event.sequence != ridLab.session.auditEvents.first?.sequence {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }

    private var profileSelection: Binding<String> {
        Binding(
            get: { ridLab.session.selectedProfile?.rawValue ?? "" },
            set: { rawValue in
                guard let profile = RIDLabProfile(rawValue: rawValue) else { return }
                ridLab.selectProfile(profile)
            }
        )
    }

    private var broadcastIntentSelection: Binding<String> {
        Binding(
            get: { ridLab.session.broadcastIntent.rawValue },
            set: { rawValue in
                guard let intent = RIDLabBroadcastIntent(rawValue: rawValue) else { return }
                ridLab.setBroadcastIntent(intent)
            }
        )
    }

    private func checklistBinding(for item: RIDLabChecklistItem) -> Binding<Bool> {
        Binding(
            get: { ridLab.session.checklist[item] == true },
            set: { ridLab.setChecklistItem(item, satisfied: $0) }
        )
    }

    private var canEditPrecheck: Bool {
        ridLab.session.phase == .complianceAuto || ridLab.session.phase == .precheck
    }

    private var canStage: Bool {
        ridLab.session.phase == .precheck && ridLab.session.allChecklistItemsSatisfied
    }

    private var canStop: Bool {
        switch ridLab.session.phase {
        case .precheck, .staged, .activeDryRun, .rollback: true
        case .complianceAuto, .lockout: false
        }
    }

    private var expectedSourceExplanation: String {
        switch ridLab.session.broadcastIntent {
        case .silent:
            "“无信号”只是未来外部信号源的期望状态；当前 no-RF 后端本来就不会发射。"
        case .broadcast:
            "“播报 Remote ID”只暂存未来外部信号源的期望状态；当前 no-RF 后端不会产生任何无线信号，也不会控制 DJI。"
        }
    }

    private func remainingLease(at date: Date) -> String {
        guard let expiresAt = ridLab.session.expiresAt else { return "—" }
        let seconds = max(0, Int(expiresAt.timeIntervalSince(date).rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SafetyBoundaryBar: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.green)
            Text("不发射无线电 · 不写飞机 / 遥控器 / 接收器")
                .font(.callout.weight(.semibold))
            Spacer()
            Text("NO-RF DRY-RUN")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.green.opacity(0.08))
    }
}

private struct LabPhaseBadge: View {
    let phase: RIDLabPhase

    var body: some View {
        Label(phase.displayName, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var icon: String {
        switch phase {
        case .complianceAuto: "checkmark.shield"
        case .precheck: "checklist"
        case .staged: "pause.circle"
        case .activeDryRun: "play.circle.fill"
        case .rollback: "arrow.uturn.backward.circle"
        case .lockout: "lock.shield.fill"
        }
    }

    private var color: Color {
        switch phase {
        case .complianceAuto: .green
        case .precheck: .secondary
        case .staged, .rollback: .orange
        case .activeDryRun: .blue
        case .lockout: .red
        }
    }
}

private struct ReceiverStateBadge: View {
    let state: BluetoothManager.State

    var body: some View {
        Label(state.rawValue, systemImage: state == .connected ? "checkmark.circle.fill" : "circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(state == .connected ? .green : state == .failed ? .red : .secondary)
    }
}

private struct RIDConfigurationSurfaceCard: View {
    let surface: RIDConfigurationSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(surface.title)
                        .font(.headline)
                    Text(surface.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                RIDConfigurationTruthBadge(truthClass: surface.truthClass)
            }

            Text(surface.truthSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Label(
                    surface.scope.displayName,
                    systemImage: surface.scope == .externalSyntheticSource
                        ? "testtube.2"
                        : "airplane"
                )
                Label("无设备写入", systemImage: "lock.fill")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct RIDConfigurationTruthBadge: View {
    let truthClass: RIDConfigurationTruthClass

    var body: some View {
        Text(truthClass.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }

    private var color: Color {
        switch truthClass {
        case .liveReadOnly: .green
        case .passive: .teal
        case .staticLocked: .secondary
        case .managed: .orange
        case .opaque: .purple
        case .legacy: .brown
        case .synthetic: .blue
        }
    }
}

private struct AuditEventRow: View {
    let event: RIDLabAuditEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("#\(event.sequence)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 44, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.displayName)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(event.timestamp, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }

    private var detail: String {
        var parts = [event.phase.displayName]
        if let profile = event.profile { parts.append(profile.displayName) }
        if event.kind == .broadcastIntentUpdated { parts.append(event.broadcastIntent.displayName) }
        if let item = event.checklistItem, let satisfied = event.checklistSatisfied {
            parts.append("\(item.displayName)：\(satisfied ? "已确认" : "未确认")")
        }
        if let leaseMinutes = event.leaseMinutes { parts.append("租约 \(leaseMinutes) 分钟") }
        if let reason = event.lockoutReason { parts.append(reason.displayName) }
        return parts.joined(separator: " · ")
    }
}

private extension RIDLabAuditKind {
    var displayName: String {
        switch self {
        case .precheckStarted: "开始安全预检"
        case .checklistUpdated: "更新安全检查"
        case .broadcastIntentUpdated: "更新外部信号源期望"
        case .staged: "暂存演练"
        case .dryRunActivated: "开始仅本机演练"
        case .rollbackStarted: "开始回滚"
        case .complianceRestored: "恢复合规自动"
        case .leaseExpired: "租约到期"
        case .lockoutEntered: "进入安全锁定"
        case .lockoutReset: "解除安全锁定"
        }
    }
}

private extension RIDLabLockoutReason {
    var displayName: String {
        switch self {
        case .manualSafetyInterlock: "手动安全联锁"
        case .sourceStateMismatch: "信号源状态不一致"
        case .rollbackFailed: "回滚失败"
        }
    }
}

private extension RIDLabError {
    var userFacingDescription: String {
        switch self {
        case let .invalidTransition(expected, actual):
            let expectedText = expected.map(\.displayName).joined(separator: "、")
            return "当前状态为“\(actual.displayName)”，此操作仅允许在“\(expectedText)”执行。"
        case let .invalidLeaseMinutes(minutes):
            return "租约 \(minutes) 分钟无效；仅允许 5–15 分钟。"
        case let .missingChecklistItems(items):
            return "仍有 \(items.count) 项安全预检未确认。"
        }
    }
}
