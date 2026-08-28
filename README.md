# FindUAS

[![macOS CI](https://github.com/Sapphire-Rapids/FindUAS/actions/workflows/ci.yml/badge.svg)](https://github.com/Sapphire-Rapids/FindUAS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一个面向 macOS 的非官方、开源 FindUAS 接收器客户端。它通过蓝牙连接接收器，显示附近无人机
广播的 Remote ID 遥测，并可读取或修改接收器配置。

> [!IMPORTANT]
> 本项目适用于 **FindUAS（[finduas.com](https://finduas.com)）配套的接收器设备**：蓝牙广播名为
> `FindUAS Device` 或 `FindUAV Device`，并提供 GATT 服务 `00FF`。它不是 DJI、Autel 等无人机
> 的受支持控制客户端，也不是 FindUAS 官方软件。“兼容性实验室”另含一组实验性的固定 DJI USB
> 只读诊断；没有通用命令入口，也不能写飞机或遥控器。

> [!NOTE]
> DJI RC 2 / Mini 5 Pro 的规范研究档案已迁移到独立仓库
> [DJI-RC2-Mini5Pro-Research](https://github.com/Sapphire-Rapids/DJI-RC2-Mini5Pro-Research)。
> 本仓库现有 DJI 文档保留为历史快照和接收器兼容性上下文；后续的新 claim、纠正、工件身份与
> coding-agent 交接记录以独立仓库为准。

## 下载

预编译的 Apple Silicon 版本见
[GitHub Releases](https://github.com/Sapphire-Rapids/FindUAS/releases/latest)。首次打开时可能需要在
Finder 中右键应用并选择“打开”，然后在“系统设置 → 隐私与安全性 → 蓝牙”中允许 FindUAS。

预编译包使用 ad-hoc 签名，尚未经过 Apple Developer ID 签名与公证。源码构建不限制 CPU 架构，
但发布页当前只提供经过测试的 `arm64` 包。

## 已验证状态

在真实 `FindUAS Device` 接收器上验证过：

- 扫描、连接及服务/特征发现；
- 订阅 `FF01`（遥测）和 `FF02`（配置）；
- 自动识别 Legacy 裸 JSON 和 V2 封装；
- 读取真实 FF02 配置通知及带响应配置写入；
- 起桨状态下接收并解码真实的非空 FF01 V2 Remote ID 遥测；
- 目标详情、历史记录和无效协议哨兵值清洗。

现场验证中，接收器持续发送约 358 字节的 V2 遥测帧，应用连续组装、解码目标且无拒绝帧。
为保护设备所有者隐私，仓库不保存或发布现场飞行器标识及坐标。

## 功能

- 扫描全部附近 BLE 广播，并突出显示兼容接收器；
- 连接服务 `00FF`，读取/订阅 `FF01` 和 `FF02`；
- Legacy 与 V2 自动组帧、遥测字段兼容解析；
- 实时目标列表、无人机/操作者地图标记；
- 实时及历史目标详情与一键复制；
- 本地 JSONL 历史记录、白名单和新目标系统告警音；
- 显示接收器电量、信道、驻留时间和告警开关；
- 写入 FF02 前二次确认及输入范围校验；
- 提供隔离的“兼容性实验室”安全预览，可演练验证档案、预检、短租约和回滚流程；
- 在实验室中以 truth label 列出 RID 配置/状态面；所有条目均为只读说明，设备写入能力固定为 false；
- 不写入用途尚未确认的 `FF03`。

### 已知遥测字段

| 类别 | 字段 |
| --- | --- |
| 身份 | UAS ID、实名登记标识、Remote ID 标准、飞机类型、ID 类型、制造商与型号 |
| 飞机 | 经纬度、相对/几何/气压高度、水平/垂直速度、航向、运行与紧急状态 |
| 操作手 / 控制站 | 经纬度、高度、位置类型 |
| 定位质量 | 坐标系、水平/垂直/速度/时间精度、GPS Fix、HDOP、卫星数与 UTC 信息 |
| 接收器 | 名称、序列号/UUID、信道、温度与 RSSI |

接收器未提供的字段显示为“—”。固件使用的 `0,0`、`-1000 m`、`361°` 等无效哨兵值会在
进入地图和历史记录前被清除。

## 系统要求

- macOS 14 或更高版本；
- 蓝牙权限；
- 地图中的本机位置功能需要位置权限；
- 构建需要 Xcode Command Line Tools 或完整 Xcode，以及 Swift 6 工具链。

实验性的 DJI USB 只读诊断还需要可动态加载的 `libusb-1.0`（例如 `brew install libusb`）。缺少它
不会影响 FindUAS 蓝牙接收器功能；DJI 卡片会明确显示“缺少 libusb 运行库”。

## 使用

1. 打开应用并允许蓝牙访问。
2. 进入“设备”，点击“扫描附近蓝牙”。这一步是让 **Mac 查找接收器**，不是让接收器扫描飞机。
3. 找到 `FindUAS Device` 或 `FindUAV Device` 后点击“连接接收器”。
4. 在“实时监测”和“地图”查看 Remote ID，在目标列表中点击“详情”查看完整字段。
5. 在“设置”查看协议与配置；写入 FF02 前核对信道和驻留时间。

接收器连上以后会按自身信道配置持续监听飞机的 Remote ID，不需要再点一次扫描。飞机是否开始
广播 Remote ID 由飞机固件和运行状态决定；部分机型只在电机启动后广播。

## 管理员实验室（安全预览）

侧栏“兼容性实验室”中的页面标题为“管理员实验室（安全预览）”。它用于先把地区兼容性测试的
操作流程、失败保护和审计边界做正确，**当前不是 Remote ID 发射器，也不是 DJI 调参工具**。
页面始终显示：

> 不发射无线电 · 不写飞机 / 遥控器 / 接收器

演练动作只修改本机内存；DJI 卡片另有独立的固定 USB 只读状态：

| 控件 | 实际效果 |
| --- | --- |
| 验证配置文件 | 选择字段与地区语义的只读测试元数据；不会改变设备地区 |
| 播报意图 | 只记录未来信号源场景为“无信号”或“播报”；不会开关飞机或产生 RF |
| 五项安全检查与 5–15 分钟租约 | 全部通过后才允许进入本机 dry-run；不是 RF 发射授权 |
| 暂存演练 | 只推进本机状态机，不访问 USB、蓝牙或网络 |
| 开始仅本机演练 | 启动有期限的内存态演练及脱敏审计；不会产生 Remote ID 广播 |
| 停止并回滚 | 立即停止演练并回到自动合规状态；租约到期也会自动回滚 |
| 读取 DJI 设备状态 | 固定 GET 读取设备存在、FC area、Sky/Ground country；FC 为 FR 时才读取法国 EID |
| RID 配置面目录 | 精选显示并区分实机只读、仅被动、静态锁定、受管理、不透明、旧协议及独立合成源；它不是控件，全部条目都显示“无设备写入”，未列入项会明确说明排除边界 |
| 通用 Remote ID 开关 | 本应用明确不实现：已恢复的 FlySafe type-6 许可启停协议仍无当前机型实机接受、真实许可、回滚与空口验证，法国 EID 也不能冒充 FAA/EU/JP/CN 的总开关 |
| 法国 EID | 只有 FR-gated 固定状态 GET；没有 setter；不可用不等于关闭 |
| 地区事务 | 尚未上线：独立研究工具已闭合 FC 与 Sky 的单次事务，Ground 请求未获 ACK；应用仍无 writer，也没有稳定设备对绑定 |
| FindUAS 接收器卡片 | 只读显示连接、FF01/组帧/解码/拒绝计数、存活目标与包装模式 |

目录只呈现能力分类与当前边界，不复制协议载荷或研究工件；其事实依据与后续纠正以
[DJI-RC2-Mini5Pro-Research](https://github.com/Sapphire-Rapids/DJI-RC2-Mini5Pro-Research)
为准。

2026-08-27 的实机只读结果为：飞机与 DJI RC 2 的已观测 VID/PID 路由均可见，FC area、Sky
country、Ground country
均为 `CN`，RC / DJI Fly policy 不可读；当前 FC 不是 `FR`，应用不会发送法国 EID 查询。独立研究
探针在 CN 状态直接查询该窄 EID 命令时没有收到匹配响应，因此只能记作 `unavailable`，不能解释成
“关闭”。DJI 官方
[MSDK 5.18.0 支持产品列表](https://developer.dji.com/doc/mobile-sdk-tutorial/en/?pbc=D3IDBfR5&pm=custom)
未列出这个组合。USB 中出现产品名称不等于建立了受支持的 MSDK 控制通道，因此应用不会用猜测的
私有命令去写 Remote ID、地区、国家码或射频功率。

该只读桥不读取 USB 字符串或序列号，`open_device_with_vid_pid` 只选择第一个匹配路由。因此这些
读数不能充当稳定的飞机+遥控器设备对身份，更不能作为未来写入授权。

同日另一个不属于 App 的一次性研究工具，在用户逐面明确授权后完成了 FC area 与 Sky country 的
`CN→US→CN` 写入、ACK、GET 和恢复闭环。Ground 只发送一次 US 请求，未收到严格匹配 ACK，随后
GET 仍为 `CN`，因此没有发送恢复写或重试。结束后连续两轮独立只读结果均为
FC/Sky/Ground=`CN`。这些结果只验证协议状态，不证明 Remote ID、频道或 O4 发射功率发生变化，
也没有放宽上面的应用边界。

关闭 Assistant 2 并释放 USB 后，研究工具又验证了两件事。第一，当前 DJI Fly 中出现的两个
RID policy 参数名，在这台 Mini 5 Pro 上均未返回可用的 F7 参数元数据；同一路由读取高度/距离
参数成功，因此它们不能作为这台飞机的稳定 RID 开关，更没有进行 F9 写入。第二，已闭合
`0x11/0x1C` 的七字节 RID/EID 自报状态布局，并在飞机与 RC 2 两端完成静止、未起桨的严格只读
基线；两路都未观察到该 push。这个基线不能证明“不支持”，因为状态可能需要官方订阅或状态变化，
且用户确认该机型只有起桨后才开始实际播发 RID。外部监测设备当时离线，所以没有空口结论。

后续历史语料确实在 RC 2 `40007` 数据中找到过严格 CRC 通过的 `0x11/0x1C`
RID 状态帧以及 FlySafe `0x03/0x09`/`0x03/0x42` push，但后续静态审计推翻了“可安全并行监听”
的前提。相邻官方 RC331 `10.00.0700/0205` 的 `dji.json` 与 `libduml_frwk.so`
表明 `40007`/`40009` 默认是单活动 fd 服务器；第二个 TCP 客户端即使不写任何字节，也可能
关闭并替换 DJI Fly 已有连接。因此历史 observer v0.1–v0.4 已经撤回，**不得安装或启动**；
它们的解码器和测试只保留为离线研究资产。精确 `07.00.0100` 实现仍待读取，但这种不确定性不能
用来承担中断飞控链路的风险。

当前同包安全替代为 `com.finduas.ridobserver` v0.10（versionCode 10，versionName
`0.10.0-research`）。它仍是独立的 work-only Android 只读准入探针，不是 FindUAS macOS 的
产品能力，也不是 RID 状态监听器、Remote ID 开关或地区切换工具。它不申请 Android 权限，只有
一个 launcher Activity，不含 service、receiver、provider 或 native library，也不包含 socket、
`40007`/`40009`、DUML、`Parcel`、DJI 应用协议 Binder 事务、进程执行、文件持久化、网络发送或
agent/library attach/load 路径。

v0.10 保留 v0.8 的只读环境清单，并只读取自身 `/proc/self/maps` 与该进程实际映射的
`libart.so`。ART 判定要求两次完全相同的 maps 快照、严格且页对齐的 start/end/offset、无溢出且
不越过文件的 coverage、非零设备与正 inode、`lstat` + `O_NOFOLLOW` 拒绝最终 symlink、纳秒级
元数据稳定、整文件 SHA-256 与 GNU build ID。命中已知 profile 时还会核对 `Agent::Unload`
（`0x5ccfa0 + 0x100`）与 `Runtime::AttachAgent`（`0x56bfc4 + 0xebc`）两个身份区间；探针不会
解析为可调用地址、调用函数、attach 或 load。Activity 重建复用同一进程内快照，不会重复启动探针。

最终候选为 2,570,983 bytes，SHA-256
`fdad29bfb1237bc224a805d6eb5a99358a044bd226610d9f0fc33975d94b606c`。43/43 tests、Android
lint、manifest、最终 DEX、APK Signature Scheme v2 与 zipalign 均通过；21/21 对抗变异被拒绝，
两次 clean build 字节一致，独立审计无未解决 P0–P3。本轮只完成离线构建和审计，APK 尚未复制、
安装或运行于 RC 2，因此没有 v0.10 实机兼容性结论。v0.9 与 v0.8 只作为封存前代保留，不再是
当前安装或准入指令。

这里有两条必须分开的证据。历史 observer 自己的目标事件 decoder 只接受 DUML encryption
selector 为 0 的帧，因此其 payload 在 RC 2 localhost broker 边界是明文；这不证明 O4 空口为
明文。另一方面，[N3Live 固定版本
`bb254b0`](https://github.com/brendan779/N3Live/tree/bb254b0d0b1f5ac79462e9fe3ea986fc91adeec0)
读取的是 Goggles N3 USB IF4，不含 `40007`/`40009`、RID 专用 decoder 或 selector 解析；它只独立
佐证 DUML framing/CRC。其 416-command 表来自未随仓库提供的 native library 的 template 符号
抽取，只能证明命令名称/常量线索，不能证明 payload、目标地址、当前产品支持或安全写法。

当前 DJI Fly 1.21.10 还存在一条条件式、更窄的 same-owner raw GET 候选：其自带
`JNIRawData.native_SendData` 可复用已初始化的 SDK/SessionMgr，并由 callback 返回 ACK 应用
payload；对 France `03/77` 即可保留 `[protocol_result,state]`，不必新开 broker socket 或
注册 native observer。它尚未 live-admitted：productId/deviceId/senderIndex、HostID override、
product139/France/EID 身份、loader 与连接 epoch 必须从当前 subject/session 逐项验证，任一未知
都不得发送，也不能同时调用 typed GET。相邻 stock `dpad_fuli` 协议页不是替代方案：它不能
表达 selector 3，并因 `Pack` Parcel 遗漏把 retry 恢复为 2，最坏会初发后再重发两次。
最新字段复核同时纠正了早先的 retry 结论：`uav_cmd_req+0x08` 才是 retry，receiver index 在
`+0x19`；product139 构造器初值为 3，静态 EID Characteristics 的 `+0x30` 初值为 0，所以
初始 typed GET 保留 3；仅当运行期更新把该字节变为非零时才清为 0，而 typed SET 保留 3。
首个 raw GET 会明确使用 retry 0 的实验室单发策略，以减少歧义；这
不宣称与尚未闭合的 typed GET 运行时策略逐位相同。

另一个 work-only 工件是 ARM64 JVMTI V0 attach canary，SHA-256 为
`4a3867251a745ce5db6c0513c23def5c97e53a57e17f4d611621895e4e323c73`。此前缺少
`DisposeEnvironment` 的工件已撤销；修正版两次全新构建字节一致，
独立审计确认 APK 无 DEX、权限、组件或 shared UID；唯一 AArch64 library 只执行
`GetEnv(JVMTI)`、`GetVersionNumber`、`DisposeEnvironment` 和一条固定数值日志。它不枚举类、不取得 `JNIEnv`，也不含
socket、文件/属性、进程、Binder、DUML、GET 或 SET。该工件尚未复制、安装或 attach；必须先取得
v0.10 的完整实机门禁和无副作用、保留 stderr/退出码的 caller；即使 attach 成功也只证明加载/JVMTI
可达，不证明 EID/RID 支持。相邻 stock `dpad_fuli` Shell 页会自动尝试 `adb shell su` 并执行
`adb version`，还会丢 stderr/退出码，因此当前不得打开或用于 attach。

V1 France-EID semantic-anchor resolver 也只完成了离线实现与审计，最终 APK SHA-256 为
`ccdf198c83ecdd3d33a54192e2bffeb9ab89ce65289497643d16f5a00bff62b2`。它只枚举已经加载的类，
精确计数 `electronicIDBroadcastOn` 与 `electronicIDBroadcastExisted` 两个 generated thunk，并
确认它们是否共享一个 ClassLoader；随后清理引用、释放本次 JVMTI environment，只输出数字计数。
它没有加载/初始化类、访问字段、调用 Java 方法、GET/LISTEN/SET、socket、Binder 或 DUML，且从未
复制到设备、安装或 attach。V1 只证明语义锚点拓扑，必须排在 v0.10 和 V0 之后另行准入，不能证明
France EID 可读，更不能证明存在 FAA/global RID 开关。

离线的 V2.1 路由解析器也已经封存：APK SHA-256 为
`7f0159619f89f7c6a9849b1028003a1070d97988838da7a6ef027e09626ada0d`，其中唯一 ARM64
library 的 SHA-256 为
`3c2a293e167531ecc9d352c2825ad20c8f35a3e829c66aad6896d06eabad3365`。它只匹配固定三套
basename/GNU build-id/RVA/签名 profile、product139 France `EIDSwitch` 语义路由与
`Characteristics::Invalid`；private exception-boundary gate 被编译为只读常量 0，因此即使所有
前置条件成立也只会以 `EXCEPTION_BOUNDARY_UNPROVEN` 退出。两次 clean build 字节一致，独立审计
还验证了 manifest、ELF、重定位、编译内 profile 表和 gate 数据流。它不含 DEX、组件、GET、SET、
listen、send、socket 或 Binder，且从未复制、安装或 attach。该工件只用于冻结离线证据，**不得在
RC 2 上安装或加载**。

连接 epoch 的进一步审计也收紧了准入结论：正常 datalink add/remove 与工作闭包共享同一 worker，
但 `ProductMgr::OnProductDidAdd/Remove` 由 listener 同步调用，其生产线程尚未证明；HardwareLayer 的
全部变更入口也没有穷尽。因此“在 worker 队尾再次解析”最多得到 `STABLE_OBSERVED`，不是原子连接
快照。下一版必须对外层 route writer 做嵌套安全的 `active_mutators` 与单调 `connection_epoch`
计数，读端在同一闭包内双读并比较；任何可能发送的闭包还必须与所有 writer 共享读写
`route_gate`，ACK、超时、失败与回滚收尾也要凭 operation token 重新解析。覆盖率、锁顺序或线程归属任一未证实，
就保持 fail-closed，既不 GET 也不 SET。

异常边界也不能靠“包一层 `catch (...)`”草率关闭。对 NDK 27 最小 AArch64 wrapper 的离线实测
显示，除 personality 与 begin/end-catch 外还会引入 `_ZSt9terminatev`；三个 DJI library 又都允许
符号抢占，必须在运行期证明 personality、throw/catch、TLS globals 与 unwind/resume 实际绑定到同一
套 `libsdk_base.so` runtime。当前更小的候选会用 exact-build 栈内短字符串 `EIDSwitch`、栈内
`[0,4,0]` prefix、官方 abstraction lookup 和 direct string lookup，去掉 target string/CacheKey
构造及其 heap allocation；但 direct lookup 自身仍有 LSDA/shared-owner cleanup，所以仍是
**NOT ADMITTED**，不会据此解除 V2.1 固定零门。

运行时 native library 身份也补上了缺失的精确设计。对当前离线分析的官方 DJI Fly 1.21.10 APK
profile，其 manifest 声明 `extractNativeLibs=true`，三个目标条目又都是 DEFLATED；RC 2 上的 live
package 必须先完整命中该 profile，之后才允许把安装器解出的独立 ELF 文件作为候选。下一版必须同时
满足完整 ELF SHA-256、前后两次 `/proc/self/maps` 的
device/inode/offset 绑定，以及所有原始不可写 `PT_LOAD` 与当前内存逐字节一致；`apk!/`、deleted、
memfd/匿名来源、读不到文件或 maps、权限/offset/映射 epoch 漂移都会失败关闭。build ID、basename 或
内存哈希都不能降级替代。该设计尚未实现，也没有改变 V2.1 的 **DO NOT INSTALL OR ATTACH** 状态。

raw GET 的回调生命周期也完成了离线复核，并否定了旧草案的“回调后静默 100 ms”规则。ACK 回调发生在
pending 节点删除之前，timer 回调发生在复制 owner 销毁之前；`native_CancelSend()` 只异步排队清理，
返回时也不能证明不会再有已越过 Stopper 的迟到回调。未来只有在注册完成、callback 已返回且
in-flight 为 0、worker 队尾再次证明精确 pending handle 与 Stopper ID 都不存在、连接 epoch 仍稳定并
确认 native code 仍驻留后，才可接受一次 GET。任何一步不能证明都返回 `UNKNOWN`，且不重试。

为避免下一版再次把这些条件漏掉，raw GET 已经整理成固定状态机：numeric handle 之外还要有永不复用的
operation generation；任何 task/callback 指针交给 DJI 前先取得 MappingLease；SDK wrapper admission 与
helper callback in-flight 分开计数；只有 post-terminal worker fence 能提交结果。现有
`SessionMgr::IsSending` 只能在 worker 上保守证明唯一 datalink/`03/77`/receiver tuple 已不在 pending
map，不能按 handle 查询；`CallbackStopper` 又没有只读查询方法，绝不能用 `RemoveID` 冒充 probe。
因此状态机虽已精确化，live hook 仍未完成，GET 继续是 **NOT ADMITTED**。

Mac 端已经能打开 RC 2 的 ADB USB endpoints 并发送 `CNXN`，但 RC 2 没有返回 `AUTH` 或 `CNXN`；
platform-tools 37 的 legacy/libusb 后端、精确 Dr-Muh pre-auth profile 和逐项改变 version、MAXDATA、
banner、checksum 的实验都停在同一个约 15 秒超时。相邻官方 RC331 的未剥离 `adbd` 已给出精确解释：
它在启动时用 DJI production/user-lock 逻辑覆盖普通 `ro.adb.secure` 决策，并在每次 `CNXN` 后再次
检查 `ro.boot.mp_state=production && ro.boot.dbg_cnt<1`；命中时直接丢包，既不
`send_auth_request()` 也不 `send_connect()`。因此当前失败点在 RSA 之前，反复删除 key、切换 USB
调试或修改 token 之后的 AUTH 顺序都没有价值。静态代码中“首包直接公钥”只是一条尚未实机发送、
可能弹窗并持久化授权的假设，不是成功结论；详见
[docs/RC2_ADB_HANDSHAKE_RESEARCH.md](docs/RC2_ADB_HANDSHAKE_RESEARCH.md)。

上述实验没有取得 shell，也没有执行 `adb install`。USB 父子拓扑还确认当时出现的 45 GB 与 256 GB
存储都属于飞机，而不是 RC 2；一次误放到飞机机身存储的 APK 在精确哈希复核后已单独删除并安全
卸载该卷。后来用户用 RC 2 原生处理的 microSD 成功安装了 DJI 签名的 PackageInstaller/FileManager
helpers 和较早 observer，证明了无需 Root/ADB 的人工更新路径。当前下一步是在取得单独实机 staging
授权后，用 v0.10 同包覆盖旧版并回传 `COMPLETE` 的完整诊断页；在完成覆盖前不得点击旧版 Start。
2026-08-28 13:11 CST 重新接线后，Mac 同时看见飞机 `2ca3:0020` 与 RC 2 `2ca3:1021`，但 RC 2
的 ADB 仍为 `offline`，且当时没有任何外接存储卷挂载。此前出现的 45 GB 与 256 GB 卷已经确认都
属于飞机，今后也不得把 RC 2 APK 复制到这些飞机卷。

`rid_broadcast_effect_icloud_control` 也完成了一次匿名最小云查询：命名空间存在，但当前返回只包含
产品 158/159 的全零广播效果配置，产品 139/WA150 不在响应中。这进一步排除了把该字段直接当成
Mini 5 Pro 总开关的做法，但不能排除账号、国家或灰度条件下出现不同配置。

另一个 `dji_fly_rid_cloud_control_v2` 名字同样不是现成开关：它按地区与 ProductType 139 选择
不透明 hex 策略，并经通用 `0xDD` 云控通道写入；`block_device` 命中只回退到 `DEFAULT` 策略。
该 key 只写不可回读，当前也没有 WA150 payload 样本、内部 schema 或与 RID 空口效果的对应关系。

当前最有希望的稳定开关路线不是这两个参数，而是 DJI 官方定义的 FlySafe `RID_UNLOCK` 签名许可。
官方资料把它列为许可证类型 6，等级 1/2 分别对应欧盟/中国，并要求经过 DJI 账号下载、飞控序列号
匹配、推送/拉取和许可启停。当前 MSDK 5.18 的原生查询与启停传输已经完成静态闭合，但还没有在
Mini 5 Pro 上读到真实 type-6 许可或验证固件接受。在确认许可可以严格读回、启停可自动恢复，并能在
用户手动起桨后由独立接收器验证之前，应用不会伪造许可、调用上传/启停命令，或把它冒充已经可用的
Remote ID 开关。

DJI 当前 FlySafe 网站确有中国大陆和海外两种 RID 申请入口，但两者都有账号资格条件，并由服务器的
`support_unlock_type=Rid` 产品能力决定设备是否可选；公共页面没有给出 Mini 5 Pro 的资格结果。
因此“官网存在入口”仍不等于这台 WA150 能获签或能被飞控接受，项目也不会绕过资格或伪造许可。

固件路线也做过实际的离线副本实验：修改 WA150 `0802` 的一字节加密 payload 后，公开可计算的
payload SHA-256 与 `encr_cksum` 可以重算到一致，但 `plain_cksum` 无法验证，RSA-PSS 覆盖区已经改变，
且当前固定公开语料库中没有匹配的 PRAK/STUE 解密与签名材料。临时产物已删除、从未传输或刷写。
这说明“修校验”不等于“得到可刷 RID 补丁”；当前最关键的固件前提仍是合法且可校验的 `0802`
明文与完整签名/恢复链。

0600/0700 两版 `0802` 的完整密文差分也已排除明显的 AES-CTR 密钥流复用：包装后的 scramble
值不同，约 679.3 MB 公共范围内没有相同的对齐 16/32 字节块，XOR 统计符合独立高熵数据。
因此不能靠“旧版密文 XOR 新版密文”恢复 RID 代码或配置。

2026-08-27 又复核了当前公开上游、可枚举 forks 与新披露资料，仍没有 WA150 `0802` 的可复现
解密、生产重签、设备 key 导出或安全刷回路径。两条 Mini 5 Pro 新 CVE 只列到 `01.00.0600`，且
没有公开源码/PoC 或明文回读证据；新出现的 `0xDA Remote ID` dissector 则源自旧 AeroScope 隐私位，
不能彻底停播、可能被重置，也没有 WA150 标准 RID 验证。因此不会为追逐这些线索降级或刷写。

首次实机核验发现，旧式一字节 `0x11/0x11` 许可证清单请求在飞机直连和 RC 2 转发两路都超时；紧接着的
阳性对照仍能分别读回 FC area=`CN` 与 Sky/Ground=`CN`。这说明设备与 USB 路由在线，但只证明那组
手写事务在当时没有收到匹配响应，不能据此声称“清单为空”或“设备不支持 V2”。现代实现复用相同
数值端点，并显示 support/version、payload、receiver route、session 和 parser 都可能决定结果；尚未
实机确认 Mini 5 Pro 使用哪一版以及超时发生在哪一层。

静态分析进一步确认，MSDK 5.18 会先取得飞控序列号，再通过 FlySafe JNI/session 查询整个
`FlysafeLicenseGroup`。当前二进制自己的映射表把 query `PackType 0x38` 直接映射为 `0x11/0x11`，
把 set-enable `PackType 0x39` 映射为 `0x11/0x12`；V2/V3/V4 的请求布局、能力/版本门控、ACK
result byte、protobuf/status parser 和启停结果解析也已恢复。DJI Fly 1.21.10 仍只能确认通用许可证
同步/查询/启停子系统被打包，尚无当前飞机的 type-6 专用 UI、服务器 entitlement 或空口效果证据；
可反编译的 1.21.4 界面只识别 type 0–4，会把 type 6 当作未知项。因此当前仍没有可安全交付的实机
RID 开关。

DJI Fly 1.21.10 的 FlySafe observer 链也已完整复核：它只在本地登记 area/whitelist/database push，
不发送订阅或 GET，也不会在新 listener 注册后重放历史帧。若 runtime product 确为 139，正式许可查询
最终由官方 `PackManager` 把 receiver 选为 `0x92`，三种已知版本都一样；在 support/version push 未
真实出现前，不能手写请求、猜版本或轮询 receiver。

France EID 的地址级静态链也已闭合：product 139 最终使用 UAV139 free handlers，`0x03/0x77`
GET body 为 `[02]`、SET body 为 `[00]`/`[01]`，默认 receiver 为 type 18/index 4（packed
`0x92`），canonical GET/SET ACK 分别为 `[result,state]` 与 `[result]`。macOS 固定只读桥已据此
修正旧的 `0x03` 目标，并把 EID ACK 严格限制为精确两字节和 clear response `{0x80,0xC0}`；仍只在
FC 明确读回 FR 时查询，且没有 setter。飞机直连和 RC 2 USB 两条人工 clear-wire GET 均未收到
canonical ACK，因此只说明这两条实验 USB route 不成立，不能否定官方 private DJI Fly runtime
route，也不能把静态 France EID 支持宣称为当前实机可用。

同一轮静态审计还闭合了 product 139 已注册的 EASA
`OperatorRegistrationNumber` 字符串 GET/SET：它使用 `0x03/0x78`，并有明确 delete 操作。这是
operator registration/OPID 数据面，不是 RID 播报 Boolean。对 DJI Fly 1.21.10 native 与可读
1.21.4 业务层的完整扫描没有找到能跨 France EID、EASA OPID/C0、Japan DIPS、FAA/US 与 China
OID 生效的普通 Boolean 总开关；`EidOpen`/`EidClose`/`EidIsOpen` 只有未闭合的旧 key 声明，
`EIDBroadcastEnable` 则属于 MSDK 的 France industry 路径。四者在当前包里最强的正证据都止于
generated/shared key metadata；当前 `libsdk_jni.so` 没有对应名称、handler 或 UAV139
characteristic，均不能视为 Fly 1.21.10/WA150 可用替代控制。

官方 transport owner 内确有比 Java Boolean 更早的只读取证点：product-139 `0x03/0x77` GET
response 在 converter 之前仍保留 raw `[result,state]`，native 也有 pending matcher 之前的
all-command observer。前者尚无获准的无侵入 live probe，后者的 add/remove/遍历没有闭合锁、线程
串行化、C++ ABI、observer ID 和卸载生命周期；两者都**尚未获得实机准入**，也都不会自行发送 GET。

要真正测试其他监测设备的空口兼容性，后续需要独立的受控信号源适配器，例如经验证的
[OpenDroneID Linux transmitter](https://github.com/opendroneid/transmitter-linux)、
[OpenDroneID nRF transmitter](https://github.com/opendroneid/transmitter-nrf) 或
[ArduRemoteID](https://github.com/ArduPilot/ArduRemoteID) 硬件。任何真实适配器都必须增加硬件身份/
能力握手、物理 RF 联锁、短租约、急停与超时回滚，并在屏蔽箱、传导环境或获准实验室中用独立
接收仪器确认实际发射内容。候选开源实现本身不等于已验证合规。

设计细节与地区档案边界见
[docs/REMOTE_ID_COMPATIBILITY_TESTING.md](docs/REMOTE_ID_COMPATIBILITY_TESTING.md)。

## 构建与检查

```sh
./scripts/check.sh
./scripts/build-app.sh
```

成品生成在 `dist/FindUAS.app`，并经过 `plutil`、ad-hoc 签名及签名校验。也可以只构建可执行文件：

```sh
swift build -c release --product FindUAS
```

`dist/`、`.build/` 和 ZIP 包不会提交进仓库。Release 附件由干净的 `dist/FindUAS.app` 单独生成，
不包含研究过程中提取的厂商资源或真实飞行数据。

## Remote ID 标准说明

截至 2026 年 5 月，中国现行运行识别标准为
[GB 46750—2025《民用无人驾驶航空器系统运行识别规范》](https://www.caac.gov.cn/XXGK/XXGK/BZGF/BZGF_GJBZ/202601/t20260120_229783.html)。
它规定的广播数据包括航空器标识/登记标识、航空器和控制站位置、速度、高度、状态、时间戳与
精度等。民航局的[标准解读](https://www.caac.gov.cn/XXGK/XXGK/ZCJD/202601/t20260120_229793.html)
明确说明，运行识别报送信息不涉及姓名、电话、住址等用户个人信息。

部分 FindUAS 接收器固件仍会在遥测 JSON 中报告 `RID_Standard: GB42590-2023`。本项目原样展示
设备报告值，不把它改写成其他标准名称。`GB 42590—2023` 的正式名称是《民用无人驾驶航空器
系统安全要求》，与现行运行识别规范不是同一份标准。

电话不是标准 Remote ID 消息元素。本应用只会显示接收器 JSON 中明确存在的厂商私有电话字段，
不会根据 UAS ID 猜测号码，也不会连接实名登记数据库查询个人信息。

## 隐私与安全

应用不包含账户、遥测上传或分析服务。`telemetry.jsonl` 会把完整 `DroneTelemetry` 写入本机
Application Support：可能包含 UAS/登记标识、接收器标识、厂商私有电话、飞机与操作者精确坐标
及其他遥测；文件当前不加密、不自动轮转，也没有自动保留期限。白名单 UAS ID 另存于
`UserDefaults`，直到用户移除或清理应用数据。请只在你拥有或获准操作的接收器上使用，并遵守当地
关于无线电、隐私和 Remote ID 数据的法律。

本软件不是飞行安全、避障、执法或身份认定系统。安全问题及敏感报告请参阅
[SECURITY.md](SECURITY.md)。

## 开发与协议

- [AGENTS.md](AGENTS.md)：给人类与 coding agent 的交接约束、常见坑和发布清单；
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：数据流、模块职责、持久化与扩展边界；
- [docs/PROTOCOL.md](docs/PROTOCOL.md)：独立整理的 BLE 互操作说明；
- [docs/DJI_RC2_STATE_RESEARCH.md](docs/DJI_RC2_STATE_RESEARCH.md)：DJI Fly/RC 2 对 Remote ID、
  账号同步、运行时飞行限制状态及明确授权的有界地区实验研究；不属于 FindUAS 产品能力；
- [docs/RC2_ADB_HANDSHAKE_RESEARCH.md](docs/RC2_ADB_HANDSHAKE_RESEARCH.md)：RC 2 v07 的脱敏 USB/
  ADB 实机矩阵与相邻 `adbd` 生产锁静态根因；不包含 Root、解锁或固件修改步骤；
- [docs/DJI_RC2_RF_POWER_RESEARCH.md](docs/DJI_RC2_RF_POWER_RESEARCH.md)：DJI Fly/RC 2 的地区码、
  FCC/CE 法规档案与 O4 射频功率控制面的以只读为主研究；记录的有界 country 事务不包含功率写入，
  仓库也不提供可执行功率修改包；
- [docs/DJI_RID_FIRMWARE_RESEARCH.md](docs/DJI_RID_FIRMWARE_RESEARCH.md)：`wa150`/`rc331` 的
  Assistant 2 版本清单、`wa150` 目标密钥边界、已验签的 `rc331/0205` Android OTA、已验证外层但
  内层 PRAK/TBIE 仍封闭的 `rc331/0200`、受 PRAK/STUE 保护的 `0806/DONG` 次级模块、不可刷写
  完整性样本、Assistant 明文回读否定结果、Sparrow2 加载信任链，以及当前官方 DJI Fly/MSDK 的
  RID 参数、许可查询与启停静态协议证据；
  不属于应用功能，仓库不包含厂商固件、APK、提取分区、下载器、升级器、Root 工具或 Remote ID
  关闭补丁；
- [docs/REMOTE_ID_COMPATIBILITY_TESTING.md](docs/REMOTE_ID_COMPATIBILITY_TESTING.md)：Remote ID
  开关、DJI 地区策略和各地区接收兼容性测试的边界、当前 no-RF 安全预览与外部受控信号源方案；
  验证配置文件不会改变飞机、遥控器、接收器的地区或发射状态；
- [CONTRIBUTING.md](CONTRIBUTING.md)：贡献与硬件报告流程；
- [CHANGELOG.md](CHANGELOG.md)：用户可见变更。

协议核心位于 `Sources/FindUASCore`，未依赖 Apple 框架，可作为后续 Windows/WinRT 客户端的
参考。欢迎提交 Issue 或 Pull Request；报告协议问题时请先删除 UAS ID、精确坐标、电话号码等
敏感信息。

## 商标与关联声明

“FindUAS”“FindUAV”以及相关设备名称属于其各自权利人。本仓库仅用这些名称说明兼容性，与
`finduas.com` 及设备供应方没有隶属、授权或背书关系。仓库不包含从官方 APK 提取的图标、音频、
无人机型号库、反编译源码或官方二进制文件。

## License

[MIT](LICENSE) © 2026 Sapphire-Rapids
