# DJI RC 2 / DJI Fly state research

This note records independently recovered, read-only implementation details relevant to answering
two questions:

1. How does DJI Fly decide that Remote ID is working normally?
2. How does DJI Fly decide that a DJI account is correctly logged in?

It is research context, not a FindUAS product feature. FindUAS connects to the external BLE
receiver and reports what that receiver receives; it does not log in to DJI, control an aircraft,
or replace an independent Remote ID receiver.

## Evidence levels and scope

- **Direct**: visible in DJI Fly/SDK bytecode or verified against the current RC 2 with read-only
  traffic.
- **Corroborated**: static implementation and official DJI documentation agree.
- **Unverified**: a native command or aircraft-firmware behavior still needs a redacted capture.

No account token, UID, aircraft identifier, exact coordinate, extracted APK, or vendor binary is
stored in this repository. No setting, account, binding, or Remote ID state was changed during this
research.

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

The raw push is serialized in this order:

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

Both failure fields must be retained. DJI Fly's FlyModel wrapper exposes the final `failReason`,
but the official MSDK 5.18.0 US industrial strategy reads the misspelled `failResion`. Treating the
first value as disposable loses information used by another official DJI path.

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

For the MSDK US industrial strategy, the raw mapping is:

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

The common delegate reports `IDLE` when the flight controller is disconnected and
`NO_BROADCAST` when the applicable RID unlock/license state is open. European and Japanese
strategies additionally derive `WORKING` from imported Operator or UA registration data. There is
therefore no single failure-code table shared by every region and product family.

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

The same UID is also sent to Beacon and GLS paths. An empty UID suppresses the FC write. A failed
FC write retries once per second with an effectively unbounded retry count; success and failure
are logged, but are not connected to the top-bar not-logged-in diagnostic.

Although `KeyFCUUIDSetting` is declared get/set/listen capable, the recovered normal DJI Fly path
does not read it back and compare it with the current account UID after a successful set. The exact
native/DUML mapping and aircraft-firmware acceptance predicate remain unverified.

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
| Flight system | UID set succeeded; preferably read back and equals the local UID | aircraft received the current account identity |

“Account correctly logged in” should be reported only when all applicable layers pass. The current
DJI Fly `3000003` warning covers only the first layer.

## Remaining read-only work

1. Recover the native/DUML mapping for `KeyFCUUIDSetting`, `KeyEIDSwitch`, and aircraft binding.
2. Determine whether a read-only FC UUID getter is usable on the RC 2 path and whether it returns a
   raw UID, a presence flag, or a derived value.
3. Recover the RC 2 GNSS-to-RID operator-location injection path and validate the candidate native
   command without changing state.
4. Compare a redacted DJI Fly RID state push with a simultaneous independent receiver capture.
5. Keep product/region strategies separate when interpreting the two failure fields.

## Primary sources

- [DJI MSDK V5 `IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
- [DJI MSDK V5.18.0 aircraft-provided artifact](https://repo1.maven.org/maven2/com/dji/dji-sdk-v5-aircraft-provided/5.18.0/dji-sdk-v5-aircraft-provided-5.18.0.jar)
- [DJI FAA Remote ID FAQ](https://repair.dji.com/help/content?customId=01700007747&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)
- [DJI account/offline-limit support note](https://repair.dji.com/help/content?customId=en-us03400011758&pbc=mF6h4ZTt&spaceId=34)
- [DJI Mobile SDK V5 sample repository](https://github.com/dji-sdk/Mobile-SDK-Android-V5)

Community reverse-engineering repositories were used to locate candidate native symbols and old
protocol context, but unverified command mappings are deliberately not presented here as facts.
