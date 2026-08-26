# FindUAS

[![macOS CI](https://github.com/Sapphire-Rapids/FindUAS/actions/workflows/ci.yml/badge.svg)](https://github.com/Sapphire-Rapids/FindUAS/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

一个面向 macOS 的非官方、开源 FindUAS 接收器客户端。它通过蓝牙连接接收器，显示附近无人机
广播的 Remote ID 遥测，并可读取或修改接收器配置。

> [!IMPORTANT]
> 本项目适用于 **FindUAS（[finduas.com](https://finduas.com)）配套的接收器设备**：蓝牙广播名为
> `FindUAS Device` 或 `FindUAV Device`，并提供 GATT 服务 `00FF`。它不是 DJI、Autel 等无人机
> 的直连客户端，也不是 FindUAS 官方软件。

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

## 使用

1. 打开应用并允许蓝牙访问。
2. 进入“设备”，点击“扫描附近蓝牙”。这一步是让 **Mac 查找接收器**，不是让接收器扫描飞机。
3. 找到 `FindUAS Device` 或 `FindUAV Device` 后点击“连接接收器”。
4. 在“实时监测”和“地图”查看 Remote ID，在目标列表中点击“详情”查看完整字段。
5. 在“设置”查看协议与配置；写入 FF02 前核对信道和驻留时间。

接收器连上以后会按自身信道配置持续监听飞机的 Remote ID，不需要再点一次扫描。飞机是否开始
广播 Remote ID 由飞机固件和运行状态决定；部分机型只在电机启动后广播。

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

应用不包含账户、遥测上传或分析服务。历史记录仅写入本机的 Application Support 目录，但其中
可能包含无人机和操作者的精确坐标，文件当前不加密。请只在你拥有或获准操作的接收器上使用，
并遵守当地关于无线电、隐私和 Remote ID 数据的法律。

本软件不是飞行安全、避障、执法或身份认定系统。安全问题及敏感报告请参阅
[SECURITY.md](SECURITY.md)。

## 开发与协议

- [AGENTS.md](AGENTS.md)：给人类与 coding agent 的交接约束、常见坑和发布清单；
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：数据流、模块职责、持久化与扩展边界；
- [docs/PROTOCOL.md](docs/PROTOCOL.md)：独立整理的 BLE 互操作说明；
- [docs/DJI_RC2_STATE_RESEARCH.md](docs/DJI_RC2_STATE_RESEARCH.md)：DJI Fly/RC 2 对 Remote ID、
  账号同步与运行时飞行限制状态的只读研究；不属于 FindUAS 产品集成；
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
