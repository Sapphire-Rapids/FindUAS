/// Stable identifiers for the Remote ID configuration and status surfaces that
/// have been distinguished by the current research. These are catalog entries,
/// not device commands.
public enum RIDConfigurationSurfaceID: String, CaseIterable, Hashable, Sendable {
    case workingStatus
    case ridCapability
    case regionSnapshot
    case franceEID
    case easaOperatorID
    case japanDIPS
    case chinaUOM
    case chinaUOMStatus
    case euC0
    case flySafeType6
    case cloudControlV2
    case legacyDetection
    case syntheticSource
}

/// The strongest truth label the current build can attach to a catalog entry.
/// A label describes evidence/access maturity; it never grants write access.
public enum RIDConfigurationTruthClass: String, CaseIterable, Hashable, Sendable {
    case liveReadOnly
    case passive
    case staticLocked
    case managed
    case opaque
    case legacy
    case synthetic

    public var displayName: String {
        switch self {
        case .liveReadOnly: "实机只读"
        case .passive: "仅被动状态"
        case .staticLocked: "静态证据 · 锁定"
        case .managed: "受管理流程"
        case .opaque: "不透明"
        case .legacy: "旧协议"
        case .synthetic: "独立合成源"
        }
    }
}

public enum RIDConfigurationSurfaceScope: String, Hashable, Sendable {
    case aircraftOrController
    case externalSyntheticSource

    public var displayName: String {
        switch self {
        case .aircraftOrController: "飞机 / 遥控器侧"
        case .externalSyntheticSource: "外部受控信号源"
        }
    }
}

/// A display-safe, payload-free description of one RID-related surface.
/// `canWriteDevice` is deliberately computed and cannot be enabled by catalog data.
public struct RIDConfigurationSurface: Identifiable, Equatable, Sendable {
    public let id: RIDConfigurationSurfaceID
    public let title: String
    public let subtitle: String
    public let truthClass: RIDConfigurationTruthClass
    public let scope: RIDConfigurationSurfaceScope
    public let truthSummary: String

    public var canWriteDevice: Bool { false }

    fileprivate init(
        id: RIDConfigurationSurfaceID,
        title: String,
        subtitle: String,
        truthClass: RIDConfigurationTruthClass,
        scope: RIDConfigurationSurfaceScope = .aircraftOrController,
        truthSummary: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.truthClass = truthClass
        self.scope = scope
        self.truthSummary = truthSummary
    }
}

/// Truth-labelled RID catalog for this exact build. It contains no command IDs,
/// raw payloads, credentials, keys, license material, or writer capability.
public enum RIDConfigurationCatalog {
    public static let safetyBoundaryText =
        "只读目录 · 当前构建不写飞机、遥控器或接收器"

    public static let privacyBoundaryText =
        "仅显示能力类别和证据边界；不显示原始载荷、凭据、密钥或许可内容。"

    public static let scopeBoundaryText =
        "这是精选显示目录；App 云上报 gate、云质量参数和仅名称调试命令因不构成可操作 RID 配置而有意排除。"

    public static let currentBuild: [RIDConfigurationSurface] = [
        RIDConfigurationSurface(
            id: .workingStatus,
            title: "RID Working Status",
            subtitle: "机载自报工作状态",
            truthClass: .passive,
            truthSummary: "目录只记录此被动状态面；当前页面不主动订阅。没有合格事件时保持未知，机载正常也不等于空口已验证。"
        ),
        RIDConfigurationSurface(
            id: .ridCapability,
            title: "RID Regional Capability",
            subtitle: "地区协议支持位",
            truthClass: .passive,
            truthSummary: "官方 owner 只会随工作状态自然推送支持位；当前页面不主动订阅，不能从国家码推导，也不表示空口已验证。"
        ),
        RIDConfigurationSurface(
            id: .regionSnapshot,
            title: "Region / Country Snapshot",
            subtitle: "FC、Sky 与 Ground 地区快照",
            truthClass: .liveReadOnly,
            truthSummary: "当前固定 USB GET 只读 FC、Sky 与 Ground；RC policy 保持未知，国家码也不是 RID 协议选择器。"
        ),
        RIDConfigurationSurface(
            id: .franceEID,
            title: "France EID",
            subtitle: "法国电子识别状态",
            truthClass: .staticLocked,
            truthSummary: "应用仅在 FC area 为 FR 时尝试窄范围状态 GET，但两条实机路由尚无规范 ACK，当前只能显示不可用，绝非通用 RID。"
        ),
        RIDConfigurationSurface(
            id: .easaOperatorID,
            title: "EASA OPID",
            subtitle: "欧洲操作人登记数据面",
            truthClass: .staticLocked,
            truthSummary: "静态证据表明它是登记数据而非广播开关；当前构建没有运行时读取或写入接口。"
        ),
        RIDConfigurationSurface(
            id: .japanDIPS,
            title: "Japan DIPS",
            subtitle: "日本登记与状态面",
            truthClass: .managed,
            truthSummary: "它包含非原子的登记凭据，只能经官方认证 owner 管理；当前没有实机读回/恢复闭环，禁止记录、编辑或删除。"
        ),
        RIDConfigurationSurface(
            id: .chinaUOM,
            title: "China UOM",
            subtitle: "中国实名与运行识别面",
            truthClass: .staticLocked,
            truthSummary: "当前版本的静态路由与回复解析已闭合，但实机基线、恢复、持久性与空口映射尚未闭合，因此仍锁定。"
        ),
        RIDConfigurationSurface(
            id: .chinaUOMStatus,
            title: "China UOM Real-name Status",
            subtitle: "条件加载的实名认证状态",
            truthClass: .staticLocked,
            truthSummary: "只读状态 key 仅在运行时能力清单接纳后出现；同步动作涉及账户与网络且没有 setter，不能包装成广播开关。"
        ),
        RIDConfigurationSurface(
            id: .euC0,
            title: "EU C0",
            subtitle: "C0 认证与地区策略输入",
            truthClass: .staticLocked,
            truthSummary: "当前只有静态策略证据，实机元数据不可用；读取前置条件和回滚均未闭合，写入锁定。"
        ),
        RIDConfigurationSurface(
            id: .flySafeType6,
            title: "FlySafe type-6",
            subtitle: "账号与飞控绑定的签名许可",
            truthClass: .managed,
            truthSummary: "当前没有真实记录、目标接受、完整读回/恢复或独立 RF 证据，因此不提供控制。"
        ),
        RIDConfigurationSurface(
            id: .cloudControlV2,
            title: "Cloud-control V2",
            subtitle: "按地区与产品选择的策略数据",
            truthClass: .opaque,
            truthSummary: "结构、读回与当前产品样本均未闭合；目录不会猜测、重放或显示其内容。"
        ),
        RIDConfigurationSurface(
            id: .legacyDetection,
            title: "Legacy Detection / DroneID",
            subtitle: "旧产品状态与身份线索",
            truthClass: .legacy,
            truthSummary: "历史行为不能映射为当前 WA150 标准 Remote ID 配置，也不构成可用开关。"
        ),
        RIDConfigurationSurface(
            id: .syntheticSource,
            title: "Synthetic RID Source",
            subtitle: "独立外部测试信号源",
            truthClass: .synthetic,
            scope: .externalSyntheticSource,
            truthSummary: "与 DJI 设备面严格分离；当前只有 no-RF 场景元数据，不会产生无线信号。"
        ),
    ]
}
