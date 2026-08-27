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
| EASA operator registration | product 139 registers `OperatorRegistrationNumber` String GET/SET/delete on `0x03/0x78` | writes or removes OPID identity data; it is not a broadcast Boolean |
| FlySafe `RID_UNLOCK` license | managed European or China license type | a retained, stubbed delegate branch suggests that a matching enabled license would produce `NO_BROADCAST` |
| RID cloud-control V2 | selects region/product data and sends it to the flight controller | no direct working-state or broadcast override was found |
| EU C0 coexistence policy | enables the C0 RID mode only for cloud-selected countries and C0 aircraft | automatic regulatory policy, not a user/debug override |
| RID broadcast-effect policy | writes a product-specific signal bitmap/quality value | tunes broadcast behavior; bit semantics are not yet recovered |

The current DJI Fly 1.21.10 native plus all readable 1.21.4 business DEX were also swept for an
ordinary cross-region control. No Boolean master switch spanning France EID, EASA OPID/C0, Japan
DIPS, FAA/US, and China OID was found. `EidOpen`/`EidClose`/`EidIsOpen` remain declarations without
a closed current handler, product registration, caller, or gate. `EIDBroadcastEnable` belongs to
the MSDK France-industry delegate rather than the consumer DJI Fly/WA150 path. All four stop at
generated/shared metadata in the current app: current `libsdk_jni.so` contains none of their exact
names, handlers, or UAV139 characteristics. These names are not applicable fallback controls for
the current Fly 1.21.10/product-139 investigation.

### Recovered French EID native request

The MSDK 5.18 native mapping for the narrow French EID setting is FLYC command set `0x03`, command
ID `0x77`. Its one-byte request payloads are:

| Operation | Request payload |
| --- | --- |
| Read state | `0x02` |
| Set EID off | `0x00` |
| Set EID on | `0x01` |

Current DJI Fly 1.21.10 address-level analysis further closes the product-139 path: the final
effective registration is the UAV139 free `EIDSwitchGet/Set` handler pair, while the UAV77 entries
are duplicate fallback. The request constructor's static default receiver is type 18/index 4
(`0x92`), sender type is 2 with a runtime sender index, timeout is 500 ms, and retry count is 0.
A runtime single-HostID Characteristics override can still replace the static receiver.

Those are native DJI Fly provider facts, not properties of the current adjacent-ABI raw Binder
prototype. The recovered `Pack` Parcelable omits `maxRetryCnt`; the service reconstructs the field
with default value 2, so a nominal retry-0 GET may be sent up to three times. The prototype also
uses DUML encryption selector 0 while DJI Fly's product-139 native request selects 3. Descriptor,
UID1000 and transaction-1 success cannot resolve either mismatch. The transaction-4 France-EID
artifact therefore remains **DO NOT RUN** even if the earlier environment gates pass.

For a matching response, byte 0 is the command status and bit 0 of byte 1 is the reported EID
state. A set operation is not verified by its acknowledgement alone: it must be followed by the
`0x02` read and an explicit state comparison. Missing, short, mismatched, or unsuccessful
responses mean **unavailable**, never `off`.

This command is specifically the supported-product French Electronic ID switch behind
`KeyEIDSwitch`/`setElectronicIDEnabled()`. It is not a generic Remote ID broadcast switch and must
not be mapped to FAA Remote ID, the general EU direct-identification path, Japan, China, or a
global aircraft RID control.

The first 2026-08-27 direct-aircraft attempt used an older target assumption and is superseded as a
route test. On 2026-08-28, after correcting the product-139 static default to `0x92`, exactly one
read-only clear GET `[02]` was sent on each of two explicit experimental routes: aircraft direct USB
and RC 2 USB. Neither returned a canonical CRC/sequence/reverse-route `0x03/0x77` ACK. The only valid
result is `unavailable` on those two artificial routes; this is not evidence that EID is off,
unsupported, or unreachable through DJI Fly's private in-process session. No `0x00` or `0x01`
request was sent, there was no retry/address scan, and writes remain prohibited unless a matching
official GET first establishes support, live route and baseline and a separate authorized procedure
defines readback and restoration.

### Recovered EASA OPID string request

Current DJI Fly 1.21.10 registers product 139's `OperatorRegistrationNumber` String key with the
free GET/SET handlers for FLYC `0x03/0x78`. The action distinguishes three operations:

| Operation | Request body |
| --- | --- |
| GET | `[02]` |
| DELETE | `[01]` |
| SET a valid 20-character value | `[00][10][first 16 validated bytes]` |

The GET ACK begins `[result,length,data...]`; SET/DELETE return a result. The application validates
the 20-character operator registration with its area-code and Luhn mod-36 rules before SET. This
closes a product-139 identity-data route, not a Remote ID transmitter enable/disable route. Its
runtime Characteristics may still override the static destination, and no live OPID request was
sent as part of this static finding.

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
discarded. Upload `0x11/0x10` remains excluded. The current MSDK binary independently confirms that
license enable uses `0x11/0x12`, but that static mapping is not permission to send it. No license
may be forged, replayed, uploaded, or toggled until a genuine RID record, exact readback, rollback,
and motor-on external RF test plan have all been established.

The bounded live check did not receive a matching response to `0x11/0x11` through either direct
aircraft USB or the RC 2 proxy. This was not a general link failure: immediately afterward the
direct path returned FC area `CN`, while the RC 2 path returned Sky and Ground country `CN`, all with
the established `0x80` response type. Do not interpret the license timeouts as an empty inventory.
They show only that the fixed hand-built transaction received no matching response in either tested
session. Because current V2 also uses a one-byte index, static schema alone cannot identify whether
the missing prerequisite was version support, route/session selection, payload detail, or target
availability.

That current MSDK 5.18 outer route is now closed. `pullFlyZoneLicensesFromAircraft` first obtains
the flight-controller serial and then follows:

```text
queryFCLicensesJni
  -> native_QueryLicenseFromFC(productId, deviceId)
  -> ModuleMediator::QueryLicenseFromFC
  -> queued native task
  -> whole FlysafeLicenseGroup result
```

The group model has an explicit RID-license collection and level field. Current native static
analysis now closes the remaining transport layer:

- query `PackType 0x38` maps directly to tuple `11 11 00 01`, i.e. cmdset `0x11`, cmdid `0x11`,
  unknown third byte 0, and a separated ACK result byte;
- V2 uses one-byte indexes, while V3/V4 request group info with `00 01` and page with
  `00 (index << 1)`;
- support and version gates choose V2/V3/V4, and product/version can change the receiver route;
- V3/V4 parse protobuf group/license messages and a separate per-license status bitmap;
- set-enable `PackType 0x39` maps directly to `11 12 00 01`; its V2/V3/V4 builders and ACK result
  parser are statically recovered but have not been exercised on this aircraft.

The Java API's whole-group result is therefore compatible with a native paginated wire session;
it is not compatible with feeding modern bodies to the old fixed-record parser. Product/device
values select the module and route but are not serialized into the recovered query payload. No
modern query or enable frame has yet been sent through a proven current session, and no genuine
type-6 record or RF effect has been observed.

Current DJI Fly 1.21.10's `libflightrestrictcore.so` also identifies why a raw endpoint retry is
not a valid substitute for the official session. Its device object begins with unlock version
unknown (`0xff`) and support false, then updates those caches from registered area and whitelist
pushes. The recovered current behavior is:

| Current-session input | Cached result |
| --- | --- |
| area push `0x03/0x09` | top two bits of the little-endian version field select V2/V3/V4 generation 0/1/2; value 3 remains unknown |
| whitelist push `0x03/0x42` | modern first byte 10+ is supported unless `0xff`; the older long layout reads byte 3; a short old layout leaves state unchanged |
| product 139 with version 0/1/2 | version sessions initially choose `0x03`/`0xb1`, then the product-tree not-found branch overrides the final receiver to `0x92` |

The query manager returns before transmission when support is false or version is still unknown.
A complete registration-chain audit shows that `Setup`, `RegisterDevicePush`, the actual provider,
and `SessionMgr` only install local callbacks: they send no subscribe/GET packet and replay no
historical push. The `Subscribe*` names are local listener-ID counters, and the public query getter
only reads the cache. No safe active trigger has been recovered, so these command IDs must not be
converted into guessed requests.
A strict 20-second passive dual listener validated 122 direct-aircraft frames and 81 RC 2 frames,
but saw neither target push. No USB writes were made. This leaves both caches and the receiver route
unknown; it does not mean the aircraft reported `unsupported`, because these are registered
current-session pushes and may require an official lifecycle or a state transition.

### Current official `RID_UNLOCK` account-to-FC chain

The DJI Fly UI/account evidence must stay versioned. Current static analysis of official DJI Fly
1.21.10 now closes the native account-to-FC license architecture; it does **not** close Mini 5 Pro
entitlement or type-6 runtime behavior. `LicenseUnlockLocalManager` obtains the current official-app
token, then uses these two requests:

```text
GET api/v4/mobile/user
GET api/v4/mobile/unlock_license_groups
```

The license-groups request has no body. It is submitted through DJI Fly's own network provider with
the official user-token/client/timestamp/signature headers; this repository must not extract,
reimplement, log, or proxy the app's embedded signing material. An empty token fails before the
server request. A successful user response supplies `user_id`; user information and each returned
license-group JSON object are cached locally. The public 1.21.4 Java flow additionally corroborates
an exact group-`sn`/current-FC-serial match before import; the current 1.21.10 native retains both
fields but its protected Java layer is not available for a line-for-line comparison. A cached group
proves neither current entitlement nor that the FC imported it.

Each server group contains signed onboard data rather than enough client-side fields to mint a
license. Current 1.21.10 selects that data as follows:

| FC unlock generation | Server data selected |
| --- | --- |
| V2 / version `0` | `onboard_license_v2` |
| V3 / version `1` | target-specific entry from `onboard_license_v3` |
| V4 / version `2` | target-specific entry from `onboard_license_v4` |

V3/V4 additionally enforce the target key and minimum target index. The selected Base64-decoded
signed blob is passed through the official upload session; DJI Fly does not reconstruct it from
the visible `unlock_licenses[]` JSON fields. The current native manager closes all of these paths:

```text
FetchAndUploadLicenseData(groupId, deviceId)
  -> FetchLicenseData(groupId, unlockVersion, targetIndex)
  -> UploadLicenseData(deviceId, signedOnboardBlob)

QueryFCLicenseInfo(deviceId)
  -> version-specific V2/V3/V4 FC inventory session

SetEnable(deviceId, enabled, licenseId)
  -> version-specific V2/V3/V4 license-state session

FetchLicenseDataAndEnableLicense(deviceId, groupId, licenseId)
  -> FetchAndUploadLicenseData(...)
  -> only after upload success: SetEnable(deviceId, true, licenseId)
```

That final upload-then-enable path is explicit in the callback implementation, not inferred from
its name. It remains an architecture finding, not permission to upload or toggle a license.
Inventory query itself has no visible account-login boolean gate, but FC-side signature, SN,
user-ID, validity, and version checks can still reject import or enable.

There is an important parser boundary. DJI Fly 1.21.10's generated `UnlockLicense.proto` models and
native JSON type switch cover only types 0--4; they contain no generated `LicenseDataRID`, so its
visible model cannot reliably label type 6 or recover its level. The closest executable public
prior version, 1.21.4, likewise recognizes only types 0--4/255 and can mislabel type 6. In contrast,
MSDK 5.18 explicitly models type 6 `RID_UNLOCK`, protobuf oneof field 7, and levels 1 `EUROPEAN` and
2 `CHINA`. MSDK supplies the missing semantic schema, but it is not proof that DJI Fly 1.21.10's
protected UI or the Mini 5 Pro runtime consumes that schema. A generic license label or switch must
therefore never be presented as an RID control.

DJI's current public FlySafe front end separately proves that official RID applications exist:
Mainland China uses a Government-account `rid` form with `rid_level=2`, while the overseas path
uses an EuropeanFcc-account `abroad-rid` form with `rid_level=1`. Both filter logged-in server
product rows by `support_unlock_type` containing exact value `Rid` and bind the selected product
and FC serial. No logged-in Mini 5 Pro capability row has been obtained, so eligibility remains
unknown until a qualified account receives the server list. The overseas terms also exclude a UAS
carrying an EU 2019/945 class-identification label; this condition must not be bypassed or falsified.

The next live decision is deliberately only two stages, with de-identified yes/no or enum output:

1. In the user's official logged-in context, answer only whether a Mini 5 Pro product row exists and
   whether its `support_unlock_type` contains `Rid`.
2. In the current FC session, answer only whether FlySafe license support is present, which unlock
   generation is active (`V2`/`V3`/`V4`/unknown), whether inventory contains type 6, and, only when
   it does, its level/valid/enabled baseline. A license ID may exist only in process memory.

If stage 1 is negative, stage 2 cannot establish the official entitlement. If support/version is
unknown, the inventory query fails, inventory has no genuine type 6, or provenance is not official,
the procedure stops with **no setter**. No token, Cookie, serial, signed blob, full license ID, or
raw frame may be exported. Only after both stages pass may a separately authorized work-only
transaction use GET baseline -> one SET -> GET verify -> restore SET -> GET restore, followed by
independent RF validation after user-initiated motor start.

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

A bounded anonymous read-only request to DJI Fly's current cloud-control endpoint requested only
this namespace, used a synthetic installation UUID, and sent no account token or aircraft serial.
The server returned a successful response with two configuration entries, keyed by products 158
and 159; both had zero bitmap and zero quality. Product 139/WA150 was absent. The probe strictly
distinguishes a missing product from a zero value and retained no raw response. This is a useful
current negative result for Mini 5 Pro, not a universal exclusion: account cohorts, rollout,
country, firmware, and installation identity may change a conditional cloud response. It also
does not authorize a client-side cloud-data writer.

The older-named `dji_fly_rid_cloud_control_v2` namespace is a different path again. Its recovered
schema is `country_and_device_type` containing rows with `country_code`, opaque hex `data`, and a
`block_device` list. The current product input is exactly `ProductType.value()`; therefore
WA150/UAV139 is compared as numeric 139. A match in an area's `block_device` list does **not**
disable RID or skip the operation: it selects the `DEFAULT` row's opaque data. Only a missing or
empty default results in no write. The selected non-empty value is wrapped as
`CloudControlData(18,4,data)` and sent through the set-only `KeyCloudControlData` surface.

Current 1.21.10 native analysis closes that generic writer further: it dynamic-casts the value,
hex-decodes `data`, builds generic cloud-control command `0xDD` with the supplied receiver
type/index, and sends the set pack. The same handler is referenced by product,
flight-restriction, and battery-authentication abstractions, so neither command `0xDD` nor tuple
`(18,4)` identifies an RID switch by itself. There is no GET/listen readback, no recovered payload
schema or signature rule, no live WA150 area/default sample, and no mapping from its ACK to
`RidWorkingStatusPush` or over-the-air broadcast. Cloud, area, ProductType, and reconnection can
all select or replay a value. This is a high-confidence product/region policy selector plus opaque
transport hook, not a stable on/off control.

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

The RC 2 localhost broker provided stronger historical evidence than those USB receive windows. A
pinned RC 2/Avata capture from `127.0.0.1:40007` contains 759 strict
CRC-valid inner DUML frames, including two `0x11/0x1C`, twelve `0x03/0x09`, and four
`0x03/0x42` frames. This proves that a normal RC 2 app can receive `RidWorkingStatusPush` and the
two FlySafe support/version cache inputs from that broker on at least one real product/session. It
does not prove the current Mini 5 Pro forwards the same pushes, and it does not prove that a second
client can safely coexist with DJI Fly. Subsequent static recovery of adjacent official RC331
`10.00.0700/0205` `dji.json` and `libduml_frwk.so` shows `40007` and `40009` default to a single
active accepted fd: a newcomer may close and replace the old fd even if it never writes. Therefore
the second-client localhost-observer architecture is retired and neither port is an admissible live
observation path. `8902` remains a different length-delimited stream and must not be fed to a DUML
parser.

N3Live was separately audited at pinned revision
[`bb254b0`](https://github.com/brendan779/N3Live/tree/bb254b0d0b1f5ac79462e9fe3ea986fc91adeec0).
N3Live reads Goggles N3 USB IF4, not the RC-local broker. Its parser treats DUML byte 8 as an opaque
`cmd_type`, accepts CRC-valid synthetic selector values 0 through 7, and has no selector decoder,
decryptor or key path. Separately, the historical RC observer's RID/FlySafe semantic decoders require
selector 0, so those admitted payloads are plaintext **at the RC-local broker boundary**. This says
nothing about O4 radio confidentiality: an RC service may already have authenticated, decrypted or
translated the air link. The retired observer's aggregate CRC-valid counter could still include
frames with a nonzero selector.

N3Live's 416-command table is generated from demangled
`dji_cmd_base_req<...>` template symbols in a separate SDK library that is not committed or hashed
in the repository. It is a name/constant inventory rather than a call graph; it does not establish
request/ACK layout, an executed send/parse path, target route, RC 2 or Mini 5 Pro implementation,
policy gates, or a safe setter. Its `0x03/0x77`, `0x03/0x78`, and
`0x11/0x4B` entries corroborate names only; their exact meanings come from the independent current
binary analysis above.

Two Android artifacts must not be conflated. A roughly 52 MB debug APK built from a third-party
research clone included unrelated Auto-FCC/DUML features and broad components such as a boot
receiver, accessibility service, package-install/log/Wi-Fi capabilities, and was rejected for RC 2
installation. It is not the observer candidate, was not installed, and neither that clone nor its
APK belongs in this repository.

A separate, independently written observer v0.1–v0.4 was roughly 2.3 MB and had narrow permissions,
strict parsing, no output stream and no reconnect. Those properties remain valid as offline parser
facts, but the builds are now withdrawn because `connect()` itself may take ownership of the single
broker fd. They must not be installed or started. Reconnect/backoff and an input-only label do not
repair the architecture.

The safe in-place replacement is v0.7 under the same package/signature. Its isolated release source
set has no permissions, service, socket, broker-port constants, DUML, `Parcel`, DJI protocol Binder
application transaction, external Activity launch or process execution. It performs only a
user-triggered read-only inventory of the `protocol` Binder descriptor plus fixed-package UID,
process visibility, signer, ABI, component, installed/native-library paths, observer-view DAC/
SELinux access, readable expected-library hashes, `ro.debuggable`, and upgrade-marker facts. Its
schema, run ID, timestamps and local clipboard copy do not broaden that boundary. It is a work-only
admission probe, not a status listener or RID control, and does not belong in the MIT app.

The next work-only artifact is an ARM64-only JVMTI V0 attach canary (APK SHA-256
`4a3867251a745ce5db6c0513c23def5c97e53a57e17f4d611621895e4e323c73`). Two clean builds are
byte-identical. Independent manifest/ZIP/ELF/disassembly audit confirms no DEX, Android permission,
component or shared UID; its single AArch64 library exports only `Agent_OnAttach` and executes only
`GetEnv(JVMTI)`, `GetVersionNumber`, `DisposeEnvironment` and one fixed numeric log. It deliberately
has no `GetLoadedClasses`, `JNIEnv`, class/method inspection, socket, file/property, process, Binder, DUML,
GET or SET path. It has not been copied, installed or attached. Do not stage it until the complete
v0.7 result and a separately audited side-effect-free caller close live debug/ABI/package/helper/
SELinux and actual target-load-path gates; even a success would prove only loader/JVMTI reachability,
not EID/RID support. The previous non-disposing build is revoked.

The ARM64 JVMTI V1 France-EID semantic-anchor resolver is also an offline-only work artifact. Its
final APK SHA-256 is
`ccdf198c83ecdd3d33a54192e2bffeb9ab89ce65289497643d16f5a00bff62b2`; two clean builds and the
post-fix audit agree. It enumerates already-loaded classes once, matches exactly the generated
`electronicIDBroadcastOn` and `electronicIDBroadcastExisted` thunk signatures, verifies their
shared-ClassLoader cardinality, deletes all references/allocations, disposes the per-call JVMTI
environment, and emits numeric counts only. It does not load or initialize a class, access a field,
invoke Java, or use GET/LISTEN/SET, socket, Binder, or DUML. It has never been copied, installed, or
attached. V1 must remain after the v0.7 and V0 admission gates; success would prove only semantic
anchor topology, not EID readability or any RID switch.

The same-owner native route also has a potential raw-EID-ACK observation surface, but it has not
passed live admission. In current `libsdk_jni.so`, product-139's `0x03/0x77` response lambda still
holds the correlated raw `[protocol_result,state]` before its converter folds every nonzero result
into `Boolean(false)`. A native all-command observer is called before the pending matcher and could
therefore see an ACK later consumed by DJI Fly. Static recovery did not find locking around its
add/remove/map iteration, however, and receive-worker serialization, `std::__ndk1::function` ABI,
observer-ID collision, callback removal, and agent-unload lifetime remain open. No live
breakpoint/probe/hook or dynamic registration is admitted, and this surface sends neither GET nor
SET by itself.

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

1. Obtain a legitimate current-session SDK/FlySafe inventory result through a path that reuses the
   official transport owner. First overwrite any historical observer with v0.7 and require its exact
   live package/UID/signature/ABI/debuggable/SELinux/Binder gates. Do not open a second `40007` or
   `40009` connection, infer unsupported from absence, scan receiver addresses, guess adjacent
   commands, or reuse the legacy record parser for modern protobuf data.
2. Use current official DJI Fly 1.21.10 for handler-level static mapping. Export the live
   controller's package-manager public base/split APKs only if exact embedded-build parity is
   needed. Do not repeat the exhausted public-key sweep over `0200`, and do not root or unlock it.
3. Capture the long `0x03/0x44` home push and read `DistanceLimitedReason` while the user observes
   the effective limit, without starting motors on the user's behalf.
4. Reuse the completed strict `0x11/0x1C` parser only behind an official/system-identity or
   in-process observation path that does not create a second broker client. Retain only redacted
   parsed fields plus both higher-level failure names and HMS 30331--30334. First capture one real
   Mini 5 Pro frame to confirm command type, sender, receiver, and the seven-byte layout. Do not
   expose raw capture or fall back to localhost reconnects.
5. Compare that redacted onboard RID status with a simultaneous independent receiver capture after
   the user initiates motor start.
6. After v0.7 gates and after a separately audited, side-effect-free, result-preserving UID1000
   caller exists, use the transaction-1 Binder check only to classify
   manager liveness; it does not admit a `Pack`. Recover the exact live manager/callback/Parcelable
   ABI and prove that a candidate path preserves native selector 3 and retry 0 before considering a
   France-EID Binder GET. The current adjacent-ABI tx4 artifact loses `maxRetryCnt` (defaulting to 2)
   and uses selector 0, so it must not run. Prefer a reviewed in-process DJI Fly subject getter if
   the no-op attach canary passes. Any accepted GET must still produce a canonical `KeyEIDSwitch`
   `0x03/0x77` result/state, keep aircraft/session binding explicit, and remain France-only. Do not
   use `40009` as a tap.
7. Recover the RC 2 GNSS-to-RID operator-location injection path without exposing coordinates.
8. Continue the aircraft-firmware path only from the verified `0802` trust boundary documented in
   [DJI_RID_FIRMWARE_RESEARCH.md](DJI_RID_FIRMWARE_RESEARCH.md). Obtain a lawful read-only plaintext
   view before doing a 0600/0700 file-level diff; do not force-extract `STUE` ciphertext. The full
   encrypted-payload comparison found no usable cross-version AES-CTR key-stream reuse, so do not
   repeat ciphertext XOR or guessed-crib scans without new key/counter evidence.

## Primary sources

- [DJI FlySafe current site](https://fly-safe.dji.com/)
- [DJI FlySafe RID application bundle](https://flysafe-public.djicdn.com/js/unlock-request.5439c983.js)
- [DJI RID Unlocking Terms of Use](https://terra-1-g.djicdn.com/7a66f171a9ea4821836288ecd68e13f3/%E5%8D%8F%E8%AE%AE%E6%9D%A1%E6%AC%BE/RID%20Unlocking%20Terms%20of%20Use_EN.html)
- [DJI MSDK V5 `IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
- [DJI MSDK V5 `IFlyZoneManager` / `RID_UNLOCK`](https://developer.dji.com/api-reference-v5/android-api/Components/IFlyZoneManager/IFlyZoneManager.html)
- [DJI Cloud API FlySafe license schema and `RID_UNLOCK` levels](https://developer.dji.com/doc/cloud-api-tutorial/en/api-reference/dock-to-cloud/mqtt/dock/dock3/flysafe.html)
- [DJI MSDK V5.18.0 aircraft-provided artifact](https://repo1.maven.org/maven2/com/dji/dji-sdk-v5-aircraft-provided/5.18.0/dji-sdk-v5-aircraft-provided-5.18.0.jar)
- [DJI FAA Remote ID FAQ](https://repair.dji.com/help/content?customId=01700007747&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)
- [DJI account/offline-limit support note](https://repair.dji.com/help/content?customId=en-us03400011758&pbc=mF6h4ZTt&spaceId=34)
- [DJI Fly official download page](https://www.dji.com/downloads/djiapp/dji-fly)
- [DJI Mobile SDK V5 sample repository](https://github.com/dji-sdk/Mobile-SDK-Android-V5)
- [Pinned RC 2 `40007` DUML stream map](https://github.com/danusha2345/SkylabFCCfree/blob/aa024985bf1556ab9c3b12f3d0f2305f63b021f5/docs/DUML_STREAM_MAP.md)
- [Pinned legacy RID cloud-control selector body](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/component/bglogic/UAVRidCloudControlLogic.java)
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
