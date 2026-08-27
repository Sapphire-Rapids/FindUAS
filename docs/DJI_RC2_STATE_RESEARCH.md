# DJI RC 2 / DJI Fly state research

This note records independently recovered implementation details relevant to answering three
questions. Most live checks were read-only; the explicitly authorized device-setting experiments
were bounded FC-area and Sky/Ground country transactions described below:

1. How does DJI Fly decide that Remote ID is working normally?
2. How does DJI Fly decide that a DJI account is correctly logged in?
3. How do configured height/distance values differ from the runtime 30/50 m account restriction?

This note is broader research context, not a FindUAS account, flight-limit, or aircraft-write
feature. FindUAS connects to the external BLE receiver and reports what that receiver receives; its
Compatibility Lab additionally exposes the fixed read-only FC/Sky/Ground and FR-gated EID GETs
described below. It does not log in to DJI, write an aircraft, or replace an independent Remote ID
receiver.

The separate area-code, FCC/CE policy, and O4 RF-power investigation is in
[`DJI_RC2_RF_POWER_RESEARCH.md`](DJI_RC2_RF_POWER_RESEARCH.md).
The distinction between a real aircraft control and a safe receiver compatibility-test profile is
specified in [`REMOTE_ID_COMPATIBILITY_TESTING.md`](REMOTE_ID_COMPATIBILITY_TESTING.md).

## Evidence levels and scope

- **Direct**: visible in DJI Fly/SDK bytecode or verified against the current hardware with
  read-only traffic or the explicitly identified bounded area/country transactions.
- **Corroborated**: static implementation and official DJI documentation agree.
- **Unverified**: a native command or aircraft-firmware behavior still needs a redacted capture.

No account token, UID, aircraft identifier, exact coordinate, extracted APK, or vendor binary is
stored in this repository. No account, binding, Remote ID, EID, radio-power, flight-limit, or
receiver setting was written. A separate research harness temporarily changed FC area and Sky
country from CN to US and restored each to CN with matching ACK plus fresh readback. One authorized
Ground US request was transmitted without a matching ACK; the fresh readback remained CN, so no
restore write or retry was sent. Two final independent probes reported FC/Sky/Ground all CN.

## Remote ID: what “working” means inside DJI software

### DJI Fly reads an aircraft self-report

The DJI Fly model path is:

```text
aircraft RID/EID subsystem
  → RidWorkingStatusPushMsg
  → KeyRidWorkingStatusPush
  → V1RemoteIDGenKt.v1RemoteIDWorkingStatus()
  → RemoteIDModel.workingStatus
  → DJI Fly checklist/status UI
```

There is no Wi-Fi or BLE scanner in this path. A normal DJI Fly status is a pre-flight/self-test
and aircraft-reported state; it is not independent proof that another receiver can receive the
over-the-air Remote ID messages.

At the application/JNI object boundary, `RidWorkingStatusPushMsg` is serialized in this order:

```text
u8 isEidSupport
u8 isRidSupport
u8 isEidNormal
u8 isRidNormal
int32 LE areaCode byte length
areaCode bytes
int32 LE failResion
int32 LE failReason
```

That is **not** the raw DUML payload layout. Current official native handler analysis closes the
aircraft push itself as exactly seven bytes on command set `0x11`, command `0x1C`:

| Raw position | Meaning recovered from the native handler |
| --- | --- |
| little-endian `u16` bits 1 / 0 | EID supported / RID supported |
| little-endian `u16` bits 9 / 8 | EID normal / RID normal |
| bytes 2--5 | signed 32-bit value passed to `GetAreaCodeStrByValue(int)` |
| byte 6 | one failure byte copied into both `failResion` and `failReason` |

Both higher-level failure fields must still be retained for API compatibility, but this build
derives both from the same raw byte. DJI Fly's FlyModel wrapper exposes the final `failReason`,
while the MSDK 5.18.0 artifact's retained US industrial strategy reads the misspelled
`failResion`. The exact area-number-to-country table remains unresolved, so a listener must report
the signed raw area value rather than guess an ISO code.

### Public MSDK working states

| Value | `RemoteIdWorkingState` |
| ---: | --- |
| `0` | `IDLE` |
| `1` | `WORKING` |
| `2` | `OPERATOR_LOCATION_LOST_ERROR` |
| `3` | `FIRMWARE_ERROR` |
| `4` | `NO_BROADCAST` |
| `5` | `NOT_SUPPORTED` |
| `65535` | `UNKNOWN_ERROR` |

Only `WORKING` explicitly claims that broadcasting is active. It is still a software/aircraft
self-report rather than an independent RF observation.

The MSDK 5.18.0 aircraft-provided artifact retains the following US industrial mapping after a
leading stub return. It is strong structural evidence, not proof that this exact artifact executes
the unreachable body at runtime:

```text
!isRidSupport                                  → NOT_SUPPORTED
isRidSupport && isRidNormal && failResion == 0 → WORKING
isRidSupport && !isRidNormal && failResion == 0→ IDLE
failResion == 1                                → OPERATOR_LOCATION_LOST_ERROR
failResion == 2                                → FIRMWARE_ERROR
other non-zero failResion                      → UNKNOWN_ERROR
```

That strategy sets `isBroadcastRemoteIdEnabled` directly from `isRidNormal`.

The US consumer strategy instead maps Device Health information codes:

| Information code | Working state |
| --- | --- |
| `0x1B080003` | `WORKING` |
| `0x1B080001`, `0x161000B4` | `OPERATOR_LOCATION_LOST_ERROR` |
| `0x161000B5`, `0x1B080002` | `FIRMWARE_ERROR` |

The same retained implementation would report `IDLE` when the flight controller is disconnected
and `NO_BROADCAST` when the applicable RID unlock/license state is open. Retained European and
Japanese strategies additionally derive `WORKING` from imported Operator or UA registration data.
These structures still demonstrate that DJI has multiple region/product interpretations, but their
exact runtime use requires a matching non-stub runtime build.

### DJI Fly diagnostics

The recovered UI diagnostics include:

| Diagnostic | UI behavior |
| --- | --- |
| `30331` | Remote ID functionality normal |
| `30332` | Operator location unavailable; red and unable to take off |
| `30333` | Remote ID link/firmware error; red and unable to take off |
| `30334` | Operator location unavailable; warning-level handling |

The `30332`/`30334` paths use roughly two seconds of stability filtering, preventing a brief
position fluctuation from immediately changing the warning state.

### A robust test requires two independent levels

1. **Onboard/self-test level**: RID is supported, the applicable DJI strategy reports `WORKING`,
   and no blocking RID diagnostic is active.
2. **Independent RF level**: after the aircraft begins broadcasting (some DJI aircraft start only
   after the motors run), a separate receiver observes and decodes the required Remote ID message
   set with fresh aircraft and control-station data.

DJI's own US FAQ distinguishes the DJI Fly PFST/status from checking another device for an
`RID-` network followed by the 20-character Remote ID serial number. FindUAS should call the first
state “aircraft-reported normal” and reserve “broadcast verified” for the second level.

### Debug, development, and authorized exception mechanisms

No generic local `force RID working` or `disable RID` debug boolean was found. The mechanisms that
do exist have narrower scopes:

| Mechanism | Actual scope | Why it is not a generic RID switch |
| --- | --- | --- |
| `setUASRemoteIDAreaStrategy()` | selects the MSDK regional delegate and feature interpretation | retained 5.18.0 logic checks the real area and rejects mismatches, with extra China restrictions |
| internal Japanese registration SN mock | substitutes the SN sent to the Japanese registration web page in develop builds | does not write working status, PFST, or broadcast state |
| French `EIDSwitch` | enables/disables the French EID standard on supported products; its native `0x03/0x77` request format is now recovered | not the common FAA/EU/China/Japan RID broadcast control |
| FlySafe `RID_UNLOCK` license | managed European or China license type | a retained, stubbed delegate branch suggests that a matching enabled license would produce `NO_BROADCAST` |
| RID cloud-control V2 | selects region/product data and sends it to the flight controller | no direct working-state or broadcast override was found |
| EU C0 coexistence policy | enables the C0 RID mode only for cloud-selected countries and C0 aircraft | automatic regulatory policy, not a user/debug override |
| RID broadcast-effect policy | writes a product-specific signal bitmap/quality value | tunes broadcast behavior; bit semantics are not yet recovered |

### Recovered French EID native request

The MSDK 5.18 native mapping for the narrow French EID setting is FLYC command set `0x03`, command
ID `0x77`. Its one-byte request payloads are:

| Operation | Request payload |
| --- | --- |
| Read state | `0x02` |
| Set EID off | `0x00` |
| Set EID on | `0x01` |

For a matching response, byte 0 is the command status and bit 0 of byte 1 is the reported EID
state. A set operation is not verified by its acknowledgement alone: it must be followed by the
`0x02` read and an explicit state comparison. Missing, short, mismatched, or unsuccessful
responses mean **unavailable**, never `off`.

This command is specifically the supported-product French Electronic ID switch behind
`KeyEIDSwitch`/`setElectronicIDEnabled()`. It is not a generic Remote ID broadcast switch and must
not be mapped to FAA Remote ID, the general EU direct-identification path, Japan, China, or a
global aircraft RID control.

On 2026-08-27, while the current aircraft reported the CN area, a direct-aircraft, read-only
`0x03/0x77` request with payload `0x02` produced no matching response. The only valid result for
this product/region state is therefore `unavailable`; it is not evidence that EID is off. No
`0x00` or `0x01` request was sent, and writes remain prohibited unless a matching successful GET
first establishes support and a separate authorized procedure defines readback and rollback.

### Other development and authorized-exception paths

DJI Fly does contain a separate internal-only area injection route through
`key_country_code_local_forever_debug` and the native area-code manager. Normal synchronization can
then propagate an area to the flight controller and Sky/Ground radio surfaces. It is not a pure
Remote ID selector: it can affect FlySafe and radio regulatory policy at the same time, has no
supported production UI, and does not prove the emitted Remote ID wire format. It is therefore a
protocol research finding, not a proposed FindUAS control. Separate bounded experiments verified
the FC-area and Sky-country setters and their restoration. The Ground attempt did not obtain a
matching ACK or change the subsequent CN readback. They did not exercise DJI Fly's injection
preference or write RC-policy, radio-power, or Remote ID surfaces. The narrower
`debug_area_code_switch` only gates part of device synchronization and is not a country selector.

DJI documents the area-strategy setter as useful during development. Static analysis of the
official 5.18.0 provided artifact shows that the retained implementation maps the strategy to an
area code, compares it with the reported real area, allows the appropriate EU-region equivalence,
and blocks transitions into or out of the China strategy. It changes the SDK delegate; it is not
evidence that an application can freely change the aircraft's real regulatory region.

The internal `RidInnerManager` contains a boolean and `JAPAN_RID_MOCK_SN`. Its only recovered
consumer replaces the aircraft SN in the Japanese web-registration initialization path when the
application is in its internal/develop state. No link to `KeyRidWorkingStatusPush`, `isRidNormal`,
PFST, or over-the-air transmission was found.

The official FlySafe model includes `RID_UNLOCK`. DJI's published Cloud API assigns it license type
6 and defines level 1 as EU RID unlock and level 2 as China RID unlock. The documented MSDK trust
flow requires DJI-account login, server download of signed licenses, filtering against the flight
controller serial, push/pull synchronization, and explicit enable/disable of the selected license.
The retained default-delegate body, located after a leading stub return, accepts only an enabled
license matching the current area strategy and would then report broadcasting disabled and state
`NO_BROADCAST`. The consumer delegate-selection path has no general Mini 5 Pro exclusion. This is
the strongest current candidate for a stable, managed laboratory exception, but it is still static
evidence: no type-6 license has yet been observed on this aircraft and no RF behavior has been
verified.

An older DJI-Link command model independently exposes aircraft license inventory through plaintext
ADS-B/FlySafe `0x11/0x11` with a one-byte record index. The reply contains total count,
enabled/valid state, type, and level; privacy-bearing license content is unnecessary and must be
discarded. Neighboring `0x11/0x10` uploads a license and `0x11/0x12` changes enabled state. Only the
read command is allowed in the current work-only probe. No license may be forged, replayed, uploaded,
or toggled until a genuine RID record, exact readback, rollback, and motor-on external RF test plan
have all been established.

The bounded live check did not receive a matching response to `0x11/0x11` through either direct
aircraft USB or the RC 2 proxy. This was not a general link failure: immediately afterward the
direct path returned FC area `CN`, while the RC 2 path returned Sky and Ground country `CN`, all with
the established `0x80` response type. Do not interpret the license timeouts as an empty inventory.
They instead show that this legacy query is unavailable on the current live route and make recovery
of DJI Fly/MSDK's current queued-task wire transport the next read-only step.

That current MSDK 5.18 outer route is now closed. `pullFlyZoneLicensesFromAircraft` first obtains
the flight-controller serial and then follows:

```text
queryFCLicensesJni
  -> native_QueryLicenseFromFC(productId, deviceId)
  -> ModuleMediator::QueryLicenseFromFC
  -> queued native task
  -> whole FlysafeLicenseGroup result
```

The group model has an explicit RID-license collection and level field. This is structurally
different from a one-byte legacy record index and an 80-byte record; the formats must never share a
parser. Native dispatch checks a mediator readiness bit, and product/device values participate in
the query. The queued task's exact transport, message ID, payload, ACK, and product/version gates
remain unresolved, so no modern raw command has been guessed or sent.

The DJI Fly UI/account evidence must also stay versioned. The protected official 1.21.10 artifact
retains generic account-license/aircraft-license UI and JNI symbol names, but currently provides no
recovered type-6-specific UI, download, or consumer-entitlement proof. The closest executable
public prior version, 1.21.4, recognizes only license types 0--4 and 255; numeric type 6 becomes
`UNKNOWN` and can fall through to polygon parsing/labels. Its generic license switch cannot be
identified as an RID switch. In that prior flow, login plus network gates server refresh of signed
account licenses. Reading the FC inventory and displaying its enable state are not directly gated
by account login, while import is gated by exact group-SN/current-FC-SN matching and the native
current-device context.

`IsEuCeEnableC0Rid` does have a recovered business caller. `UAVC0EuRidCloudControlLogic` reads the
`EU_BUCKET_COEXIST_C0_RID` cloud namespace, checks whether the current area is in its
`country_list`, and combines that result with the aircraft's CE class being C0 before writing the
key through `EuCeCertificationModel`. This is an automatic EU C0 coexistence policy, not a generic
RID debug switch. The current official DJI Fly 1.21.10 native library contains the corresponding
FC parameter name `EU_CE_enable_c0_rid_0`, whose established DJI hash is `0xF80992FE`, plus the
F7/F8/F9/FA hash-parameter transport. Corrected image-base-aware analysis directly pairs the Key
and parameter with `GetConfigValueHandler<BoolMsg>` / `SetConfigValueHandler<BoolMsg>`. `BoolMsg`
does not prove a one-byte wire value; the current product's F7 metadata still must establish type
and size, and the parameter must not be probe-written.

A second business path, `UAVRidBroadcastEffectCloudControlLogic`, reads
`RID_BROADCAST_EFFECT_ICLOUD_CONTROL`, selects product-specific `u8_type_bitmap` and
`u8_signal_quality` values, and writes an encoded value to `CccBroadcastSignalQuality`. Negative
bitmaps become zero; non-negative values retain their low four bits. Signal quality is retained
only in the inclusive 0--18 range and otherwise becomes zero. The final value is
`(bitmap << 8) | quality`. This proves that some RF-effect parameters are cloud/product controlled.
The bitmap meanings are still unknown, and no evidence connects this key to a local force-working
or disable-RID toggle. Generated lifecycle and injection classes register this and the other RID
background logics on aircraft connect/disconnect, so these are active business paths rather than
unused definitions. The same current official native library pairs this Key with the FC parameter
name `ccc_broadcast_signal_quality_0`, hash `0xD7757AD2`, and IntMsg get/set config handlers.
`IntMsg` likewise does not establish the wire width. The mapping is closed for this native build,
but it does not reveal the bitmap semantics or promote the field to an enable switch.

## DJI account: what “correctly logged in” means

The implementation has three separate layers. A single green account UI state does not prove all
three.

### Layer 1: cached local session

`UAVAccountCenterService.isLogin()` ultimately reads a manager boolean initialized from whether
the locally stored `key_account_token` string is non-empty. That check does not contact the server,
does not require a non-empty UID, and does not prove that the aircraft received the UID.

The account UI's login callback also sets its local boolean to true without validating
`MemberInfo.mUid`. A malformed or incomplete cached session can therefore look logged in locally.

### Layer 2: server token validation

When network connectivity becomes available, the background account logic submits the token to:

```text
apis/apprest/v1/validate_token
```

- business `code == 0`: accept the token and refresh the local expiry;
- non-zero business code: clear account data and broadcast logout;
- transport/parse failure: clear the session only when its local expiry has already passed.

Successful login and successful validation both save `now + 7,776,000,000 ms`, which is 90 days.
This matches DJI support documentation stating that a screen remote/app can log out after more
than 90 days without networking.

### Layer 3: UID synchronization to the flight system

`WriteUuidLogicV1` listens to account and flight-controller connection state. When the controller
connects it sets the app identity, then sends the account UID through the flight-limit subsystem:

```text
KeyAppFlag = UAV_APP
KeyFCUUIDSetting = MemberInfo.mUid
```

The app-identity write occurs whenever the flight controller connects and does not depend on login
state. The UUID write does depend on a non-empty account UID. The same UID is also sent to Beacon
and GLS paths. An empty UID suppresses the FC UUID write. A failed FC write retries once per second
with an effectively unbounded retry count; success and failure are logged, but are not connected to
the top-bar not-logged-in diagnostic.

Although `KeyFCUUIDSetting` is declared get/set/listen capable, the recovered normal DJI Fly path
does not read it back and compare it with the current account UID after a successful set. The exact
write-key mapping and aircraft-firmware acceptance predicate remain unverified. A separate legacy
read-only status command has now been verified on the connected flight controller, as described
below.

Additional read-only keys expose more of the aircraft-side state:

| Key | Access | Interpretation |
| --- | --- | --- |
| `FCHasWrittenUUID` | get/listen | whether the FC has a UUID |
| `FCAllUUIDSetting` | get/listen | timestamped UUID history in the recovered parser |
| `FCWhiteListUnlimitEnable` | get/listen | FlySafe/GEO whitelist state, not the account-limit path |

The legacy midware parser places the read paths under FLYC `Detection` (`0xDA`) as `GetUUID=8`,
`GetIsSetUUID=9`, `GetAllUUID=11`, and `GetUAVAppFlag=12`. The two boolean subcommands have now been
verified read-only through both the RC 2 bridge and the aircraft's direct USB interface. The
privacy-sensitive `GetUUID` and `GetAllUUID` commands were deliberately not sent, and no real UID
was queried or stored. Static material does not yet prove that legacy subcommand 12 and the modern
KeyValue `KeyAppFlag` share the same backing state.

The `IsFakeUuidSupport` key is also get/listen only. DJI Fly injects the fixed compatibility UUID
only when the connected aircraft reports that capability. No local preference, developer screen,
or account option was found that can set it.

The hidden developer settings screen controls display-equipment mode and a 1–20 detection-distance
parameter. It has no login, UID, or 30/50 m override. A generic cloud gray-test service can bucket
devices by UUID hash modulo ten, but no caller connects it to account login, `FCUUIDSetting`, or
diagnostic `3000003` in the recovered source.

MSDK 5.18.0 also retains a concrete `updateLoginInfoForCSDK()` method that is absent from the
public `IUserAccountManager` interface. Its retained bytecode forwards account fields to the system
information manager; the normal login path separately updates local `LoginInfo`, persistence, and
listeners. It is therefore not equivalent to forcing the account manager into a logged-in state.
Because the provided artifact contains leading stub returns, this is static structural evidence,
not a runtime claim.

No writable debug/override switch for the unauthenticated 30 m height / 50 m distance restriction
was found.

### Why diagnostic 3000003 is insufficient

The UI `WriteUuidLogic` combines only:

```text
flightControllerConnected && !localIsLogin
```

When true, `TopBarTipModel` constructs `UAVDiagnosticsImpl(3000003)` inside the app. This diagnostic
is not pushed by the aircraft and is not a `KeyFCUUIDSetting` failure acknowledgement. Consequently,
a cached token with an empty UID, or a UID that continually fails to reach the flight controller,
can avoid `3000003`.

DJI documentation states that operating without a logged-in account produces a 30 m height and
50 m distance restriction. Static code also places the FC UUID key in the flight-limit component
and contains a product-specific compatibility branch proving that the aircraft-side limit system
consumes a UUID. The exact aircraft-firmware predicate has not yet been recovered.

### Practical three-layer verdict

| Layer | Minimum evidence | Verdict |
| --- | --- | --- |
| Local session | non-empty token, `isLogin == true`, non-empty UID | DJI Fly has a usable local identity |
| Online account | most recent `validate_token` returned `code == 0`, expiry not passed | DJI server recently accepted the token |
| Flight system | for current-account sync, compare the FC UUID with the current UID in memory and require equality | aircraft holds the identity of the current account |

“Account correctly logged in” should be reported only when all applicable layers pass. The current
DJI Fly `3000003` warning covers only the first layer. `FCHasWrittenUUID == true` alone may be a
historical UUID and proves only that the FC holds some identity, not that it matches the current
account.

## 2026-08-27 bounded hardware validation

### Two independently visible DJI USB devices

The Mac simultaneously enumerated the RC 2 and the connected aircraft as separate DJI USB
devices. Sensitive product strings, aircraft identifiers, serial numbers, and coordinates were
excluded from every capture and from this repository.

The RC 2 (`2ca3:1021`, `KATMAI-IDP`) exposes:

- interface 0: vendor DUML bulk, OUT `0x01`, IN `0x81`;
- interface 1: MTP/PTP;
- interface 2: an ADB-shaped interface. An earlier snapshot reported `offline`; the latest
  read-only run deliberately did not start a host ADB server, attempt a handshake, or authorize a
  key, so current ADB usability was not tested.

The aircraft (`2ca3:0020`) exposes RNDIS, mass-storage, and several vendor bulk interfaces. Passive
traffic and matching query replies verify interface 4, OUT `0x04` / IN `0x85`, as a direct FC DUML
path on this aircraft. This is stronger evidence than descriptor naming alone.

### Verified offline controller platform, without root

The official adjacent `rc331/10.00.0700/0205` module was downloaded outside this repository and
matched its exact size, official MD5, and local SHA-256. A public `PRAK-2020-01` verification pass,
without force, passed the IMaH v2 header signature and both stored/plain chunk checksums. The inner
object is a signed Android OTA whose update-engine metadata enumerates 29 A/B partitions. Only
selected partitions were extracted for static inspection.

This OTA is the Android/Qualcomm base system, not DJI Fly. Its `/dji_apk` directory is empty, so the
embedded RC 2 package is not present there. The exact `0200` body has since been outer-verified and
identified as a separately protected `flyapp`/FLYA image: every tested public PRAK and TBIE variant
fails its inner signature or plaintext checksum. That is a key/trust-boundary result, not a reason
to force-decrypt or root the controller.

Separately, DJI's current official Android phone-distribution APK (`1.21.10`) supplies a clean
same-generation `libsdk_jni.so` research boundary. It contains the RID keys above, the two named FC
parameters, and the FLYC `0x03/0xF7` metadata GET, `0x03/0xF8` value GET, and `0x03/0xF9` write
plus `0x03/0xFA` reset transports. This closes the general native-family gap while leaving exact
embedded-RC version parity unresolved. The APK and native library remain outside the repository.

The adjacent controller product table maps `wa150` to drone type 139, and the current native
UAV139 abstraction dynamically installs both RID-policy FCConfig mappings. Its F8 callback parses
`[batch_status][hash:u32le][value:cached_size]...`; F9 builds
`[hash:u32le][value:cached_size]...`, and its success callback checks only the first ACK status
byte. Size/type come from the initialized FC config cache. This closes an application-side mapping,
not aircraft availability: a zero F9 ACK would still require F8 readback, working-status change,
and independent RF confirmation.

The selected vendor image contains the preinstalled `com.dpad.fuli` development assistant. It uses
`android.uid.system` and its internal command UI forwards entered text to `Runtime.exec(...)`.
System UID is not root UID 0; the app's attempt to run `adb shell su` is not evidence that `su`
succeeds. The same app exposes updater/recovery, Type-C, FTM, SDR, MCU, and log controls. None was
launched on the live controller, and adjacent-package presence does not prove the current live
build contains the same app.

The live rootless view remains narrower: standard MTP/PTP returned 14 directories and zero files,
with no DJI Fly APK or `dpad-test` path. Assistant's visible all-log route reaches backend
`GetLogList` and `ExportAllLog` methods that are explicit unsupported stubs; its separate data-
export mode was not entered because that would change device service state. No developer app,
shell, ADB authorization, root, unlock, transfer, reboot, or flash was exercised.

Targeted base-OTA inspection did not identify an explicit RID/UAS-ID platform service or DJI user
`account`/`login` service. Its activation, certificate, TEE, RPMB, and crypto-state paths are device
trust mechanisms, not evidence of user-account state. The current phone APK can now answer
same-generation static questions; the live embedded DJI Fly/aircraft runtime remains the target
for exact RC behavior and account/RID timing. The DJI-modified `adbd` also overrides ordinary `ro.adb.secure` behavior
with a production/user-lock gate, so debug-friendly build properties are not proof of an open root
shell.

Root and bootloader unlock are not required for the next research step and are rejected for the
current controller. AOSP specifies a data wipe and changed Verified Boot state for lock-state
transitions. A public single-device RC 2 report also records persistent DJI TEE/application failure
and a later non-booting state after unlock/root work. That is risk evidence, not proof of a universal
outcome or an eFuse mechanism.

### RC bridge addressing and aircraft link

In DUML, `APP` is device type `0x02`; device type `0x0A` is `PC`. On the current RC 2 firmware and
IF0 USB bridge instance, inbound flight-controller pushes use PC instance 5 (`0xAA`) as their
receiver. An outbound FC query sourced from plain PC `0x0A` did not receive a bridged reply, while
using `0xAA` as its source produced a matching FLYC reply. This is a hardware observation for the
current bridge instance, not a universal RC 2 addressing rule. Direct aircraft-interface queries
use PC address `0x0A`.

A 15-second passive RC 2 capture contained 32 FLYC `GetPushCommon` frames (`0x03/0x43`) in addition
to the RC heartbeats. The aircraft interface independently carried the same `0x03/0x43` family.
This proves that the aircraft-to-RC flight-controller link and both read paths were present during
the current test; the earlier no-reply result was an addressing error, not evidence that the link
or parameters were absent.

### UUID/app state: identical replies on both paths

Only two allow-listed `FLYC Detection` (`0x03/0xDA`) status subcommands were sent. The reply layout
is `[subcommand, ccode, flag]`:

| Read-only query | RC 2 bridge | Direct aircraft | Interpretation |
| --- | --- | --- | --- |
| `GetIsSetUUID=9` | `ccode=0`, `flag=0` | `ccode=0`, `flag=0` | `has_uuid=false` |
| legacy `GetUAVAppFlag=12` | `ccode=0`, `flag=0` | `ccode=0`, `flag=0` | legacy flag reports false |

These are flight-controller reports, independently confirmed over two transports. They do **not**
by themselves prove that the RC 2's local account is logged out or that its server token is
invalid. They do prove that this FC currently reports no written UUID and that legacy subcommand 12
reports false, with neither result being a bridge-routing artifact. The apparent tension with DJI
Fly's modern `KeyAppFlag` write-on-connect path remains unresolved: the legacy flag may use a
different backing state, or the modern write may not have executed, persisted, or applied on this
firmware.

### Configured limits are not the effective 30/50 m layer

Read-only hash queries also returned the same values over both transports:

| Setting | Hash | Current | FC metadata |
| --- | ---: | ---: | --- |
| height limit | `0x0371238A` | 500 m | unsigned 16-bit; min 20, max 500, default 120 |
| distance limit | `0x425C0A94` | 5000 m | unsigned 16-bit; min 15, max 8000, default 5000 |
| distance-limit enabled | `0x7ECE6D19` | false | boolean; min 0, max 1, default 0 |

All replies had return code zero. These normal configuration values coexist with `has_uuid=false`
and a false legacy app flag. Therefore, **if** a 30 m / 50 m cap is active in this state, it is not
expressed by these three values and must be a separate runtime/effective-limit/reason-status layer.
This observation does not prove that the cap was active during the test.

The decompiled long form of `DataOsdGetPushHome` (`0x03/0x44`) exposes a direct test:

- `payload[0x24] & 0x1f` is `HeightLimitStatus`; value `10` is `LIMIT_BY_REALNAME`;
- little-endian float32 at `payload[0x25..0x28]` is the effective height limit;
- state bits at `payload[0x14]` report height-limit and distance-limit reached;
- the separate `DistanceLimitedReason` key defines `REAL_NAME_LIMIT=2`.

Bounded passive windows while the aircraft was not flying contained `0x03/0x43` but no long
`0x03/0x44`, so this run neither proves nor disproves an effective 30/50 m cap. No motors were
started and none of the flight-limit settings was changed.

### Bounded area/country transactions and the remaining region surfaces

The authoritative FC area getter reported CN (ISO numeric 156). Under explicit laboratory
authorization, a one-shot setter changed only that FC value to US (840); immediate readback
reported US. The original CN value was then restored, and a final readback reported CN. This
establishes a reversible `CN -> US -> CN` closed loop for the FC area field on the current
aircraft. It does not establish a complete DJI region change and does not show that Remote ID or
radio behavior changed.

Under a later, surface-specific authorization, both airlink routes first had to return CN on two
consecutive GETs. Sky then accepted exactly one fixed US country SET with a strictly matching ACK;
the immediately following GET returned US. One CN restore SET also produced a matching ACK and the
next GET returned CN. Ground transmitted exactly one fixed US SET, but no strictly matching ACK
arrived in the response window. The following safe GET still returned CN, so the harness sent no CN
restore and did not retry US. This is a successful Sky closed loop and an inconclusive Ground
attempt with no observable or durable applied state, not evidence that Ground universally rejects
or lacks the setter.

After restoration, separate read-only country queries reported:

| Surface | Final observation |
| --- | --- |
| FC area | CN, restored and verified |
| Sky/airlink country | CN |
| Ground/airlink country | CN |
| RC/DJI Fly policy country | unavailable / unknown |

Sky was temporarily written and restored; Ground received one forward request, after which the
immediate and two final GETs reported CN. No observable or persistent Ground change was established,
and the RC/DJI Fly policy surface could not be read through the available route. Consequently, these
surface-specific checks still are **not a synchronized region switch**. Two independent final probes
reported FC/Sky/Ground all CN. The external FindUAS receiver was offline, so there was also no
independent RF observation with which to test whether any Remote ID message, transport, regional
format, channel set, or transmit power changed.

### RID status remains a subscription/RF validation problem

`KeyRidWorkingStatusPush` is get/listen-only and can be resolved at the Java/native API boundary to
the complete key tuple `(product=0, component=4, index=0, subcomponent=65534,
subindex=65534, identifier="RidWorkingStatusPush")`. A current official DJI Fly native library now
maps it to ADS-B/RID command set `0x11`, command `0x1C`. The current native handler consumes exactly
seven raw bytes using the flag, area-value, and failure-byte layout above. DJI-Link's committed DJI Fly 1.21.4 telemetry table independently corroborates
the route and US bit 0, Cloud bit 10, EU bit 11, and France bit 13, with product fallbacks. The
command is now a strong static subscription target, but it is still a
push/status source rather than a setter. Its
absence from a passive IF4 window is not evidence that RID is unsupported: the stream may start
only after `UAVKeyManager.listen(...)` establishes a subscription or after an aircraft state
transition.

After Assistant's USB services were closed, a strict read-only listener completed one 15-second
aircraft baseline and one 20-second concurrent aircraft/RC 2 baseline with the motors stopped.
Across the concurrent run it validated 158 aircraft frames and 82 RC 2 frames, but neither path
contained a `0x11/0x1C` candidate. No raw payload, UAS ID, location, or serial was retained. This is
a valid quiet baseline, not a negative capability result; the external detector was offline and
the user reports that this aircraft begins actual RID transmission only after motor start.

The safest onboard check is an official-runtime read-only listener for
`KeyRidWorkingStatusPush`/`IUASRemoteIDManager`, retaining both `failResion` and `failReason`, plus
HMS 30331--30334. Even `WORKING` or `isRidNormal=true` is only aircraft self-report; a simultaneous
independent receiver capture after user-initiated motor start remains necessary to prove RF
broadcast. A normal macOS Bluetooth device list is not sufficient for this check because broadcast
Remote ID need not appear as an ordinary connectable BLE peripheral. The external receiver was
offline during the area/country experiments, so they provide no over-the-air Remote ID evidence.

## Remaining work

Unless an item explicitly enters a separately authorized, capability-gated set/readback procedure,
the remaining probes are read-only.

1. Recover only the queued task/message builder behind MSDK 5.18
   `ModuleMediator::QueryLicenseFromFC`, or obtain a legitimate current-session SDK inventory
   result. Determine its exact transport, message ID, request/ACK framing, and product/version
   gates without guessing adjacent raw commands or reusing the legacy record parser.
2. Use current official DJI Fly 1.21.10 for handler-level static mapping. Export the live
   controller's package-manager public base/split APKs only if exact embedded-build parity is
   needed. Do not repeat the exhausted public-key sweep over `0200`, and do not root or unlock it.
3. Capture the long `0x03/0x44` home push and read `DistanceLimitedReason` while the user observes
   the effective limit, without starting motors on the user's behalf.
4. Use the completed strict `0x11/0x1C` parser as the reference for an official-runtime
   subscription experiment, retaining only redacted parsed fields plus both higher-level failure
   names and HMS 30331--30334. First capture one real Mini 5 Pro frame to confirm command type,
   sender, receiver, and the seven-byte layout on this product.
5. Compare that redacted onboard RID status with a simultaneous independent receiver capture after
   the user initiates motor start.
6. On an explicitly supported product/region, confirm the recovered `KeyEIDSwitch` `0x03/0x77`
   GET response before considering any authorized set/readback test. Keep aircraft/session binding
   explicit and do not conflate this France-only EID surface with ordinary RID.
7. Recover the RC 2 GNSS-to-RID operator-location injection path without exposing coordinates.
8. Continue the aircraft-firmware path only from the verified `0802` trust boundary documented in
   [DJI_RID_FIRMWARE_RESEARCH.md](DJI_RID_FIRMWARE_RESEARCH.md). Obtain a lawful read-only plaintext
   view before doing a 0600/0700 file-level diff; do not force-extract `STUE` ciphertext.

## Primary sources

- [DJI MSDK V5 `IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
- [DJI MSDK V5 `IFlyZoneManager` / `RID_UNLOCK`](https://developer.dji.com/api-reference-v5/android-api/Components/IFlyZoneManager/IFlyZoneManager.html)
- [DJI Cloud API FlySafe license schema and `RID_UNLOCK` levels](https://developer.dji.com/doc/cloud-api-tutorial/en/api-reference/dock-to-cloud/mqtt/dock/dock3/flysafe.html)
- [DJI MSDK V5.18.0 aircraft-provided artifact](https://repo1.maven.org/maven2/com/dji/dji-sdk-v5-aircraft-provided/5.18.0/dji-sdk-v5-aircraft-provided-5.18.0.jar)
- [DJI FAA Remote ID FAQ](https://repair.dji.com/help/content?customId=01700007747&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)
- [DJI account/offline-limit support note](https://repair.dji.com/help/content?customId=en-us03400011758&pbc=mF6h4ZTt&spaceId=34)
- [DJI Fly official download page](https://www.dji.com/downloads/djiapp/dji-fly)
- [DJI Mobile SDK V5 sample repository](https://github.com/dji-sdk/Mobile-SDK-Android-V5)
- [AOSP Verified Boot device state](https://source.android.com/docs/security/features/verifiedboot/device-state)
- [AOSP Verified Boot flow](https://source.android.com/docs/security/features/verifiedboot/boot-flow)
- [Android `ApplicationInfo` public APK paths](https://developer.android.com/reference/android/content/pm/ApplicationInfo)
- [Independent exact `rc331/0205` corroboration](https://github.com/danusha2345/SkylabFCCfree/commit/51ef14244cbd2e9346db67fd9dd15e08e30750e8)
- [RC 2 single-device risk report](https://github.com/whitelewi1-ctrl/dji-rc2-research/commit/fc5949acfe8196e2faccf96615821b62fbe60804)
- [RC331 FLYA public-key boundary report](https://github.com/o-gs/dji-firmware-tools/issues/467)
- [DJI-Link 1.21.4 parameter wire analysis](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/reverse_docs/PARAM_WIRE.md)
- [DJI-Link 1.21.4 Remote ID telemetry table](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/reverse_docs/TELEMETRY_TABLE.txt)

Community reverse-engineering repositories were used to locate candidate native symbols and old
protocol context, but unverified command mappings are deliberately not presented here as facts.
