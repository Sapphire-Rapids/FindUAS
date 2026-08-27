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
| 通用 Remote ID 开关 | 本应用明确不实现：尚未发现并验证通用 setter，法国 EID 不能冒充 FAA/EU/JP/CN 的总开关 |
| 法国 EID | 只有 FR-gated 固定状态 GET；没有 setter；不可用不等于关闭 |
| 地区事务 | 尚未上线：独立研究工具已闭合 FC 与 Sky 的单次事务，Ground 请求未获 ACK；应用仍无 writer，也没有稳定设备对绑定 |
| FindUAS 接收器卡片 | 只读显示连接、FF01/组帧/解码/拒绝计数、存活目标与包装模式 |

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

当前最有希望的稳定开关路线不是这两个参数，而是 DJI 官方定义的 FlySafe `RID_UNLOCK` 签名许可。
官方资料把它列为许可证类型 6，等级 1/2 分别对应欧盟/中国，并要求经过 DJI 账号下载、飞控序列号
匹配、推送/拉取和许可启停。研究工具正在恢复当前只读许可证清单路线；在确认 Mini 5 Pro 存在真实许可、
可以严格读回并能在起桨后由独立接收器验证之前，应用不会伪造许可、调用上传/启停命令，或把它冒充
已经可用的 Remote ID 开关。

首次实机核验发现，旧版 `0x11/0x11` 许可证清单请求在飞机直连和 RC 2 转发两路都超时；紧接着的
阳性对照仍能分别读回 FC area=`CN` 与 Sky/Ground=`CN`。这说明设备与 USB 路由在线，但该旧查询
入口不适用于当前产品，不能据此声称“清单为空”。下一步是闭合当前 DJI Fly/MSDK 的实际拉取协议。

静态分析进一步确认，MSDK 5.18 的现代实现会先取得飞控序列号，再通过 FlySafe JNI/session 查询整个
`FlysafeLicenseGroup`；它的公开 API/结果模型不是旧版逐索引模型，并能表达 `RID_UNLOCK`。但精确
wire message 仍藏在 native 排队任务中，尚不能排除内部复用同一数值命令。DJI Fly 1.21.10 只能确认通用许可证同步/查询/启停子系统仍被打包，
尚无 type-6 专用 UI 或服务器 entitlement 证据；可反编译的 1.21.4 界面只识别 type 0–4，会把 type 6
当作未知项。因此当前仍没有可安全交付的实机 RID 开关。

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
- [docs/DJI_RC2_RF_POWER_RESEARCH.md](docs/DJI_RC2_RF_POWER_RESEARCH.md)：DJI Fly/RC 2 的地区码、
  FCC/CE 法规档案与 O4 射频功率控制面的以只读为主研究；记录的有界 country 事务不包含功率写入，
  仓库也不提供可执行功率修改包；
- [docs/DJI_RID_FIRMWARE_RESEARCH.md](docs/DJI_RID_FIRMWARE_RESEARCH.md)：`wa150`/`rc331` 的
  Assistant 2 版本清单、`wa150` 目标密钥边界、已验签的 `rc331/0205` Android OTA、已验证外层但
  内层 PRAK/TBIE 仍封闭的 `rc331/0200`，以及当前官方 DJI Fly native 的 RID 参数/只读传输证据；
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
