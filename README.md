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
| 通用 Remote ID 开关 | 本应用明确不实现：已恢复的 FlySafe type-6 许可启停协议仍无当前机型实机接受、真实许可、回滚与空口验证，法国 EID 也不能冒充 FAA/EU/JP/CN 的总开关 |
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

后续历史语料复核找到了更好的无 Root 观察面：RC 2 本机 `40007` broker 的一组真实、严格 CRC
通过的旧实机数据里出现过 2 帧 `0x11/0x1C`，并同时包含 FlySafe 的 `0x03/0x09` 与 `0x03/0x42`
push。因此下一步是在 RC 2 上做单连接、长时间、完全只读且
先去敏再输出的 RID 状态监听器，而不是先 Root 或反复短连抓全量遥测。该证据来自另一机型，仍需在
Mini 5 Pro 起桨实验中与独立接收器同步复核。

这个观察器的 research-only Android 原型现已完成：默认关闭，只能在 Info 页手动 Start/Stop；由
前台服务维持一次只读连接，切回 DJI Fly 后仍可运行；端口忙、断流或失败即停止，不自动重连，也不
取得 socket 输出流。23 项定向 JVM 测试和 debug APK 构建均通过，但尚未安装或接触实机。原型位于
独立的第三方研究 clone，源码和 APK 都不会并入本 MIT 仓库；当前结论仍只是“观察面已实现”，不是
“Mini 5 Pro 已动态验证”，更不是 RID 开关。

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
