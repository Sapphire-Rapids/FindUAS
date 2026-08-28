# Remote ID compatibility testing and region profiles

Last reviewed: 2026-08-28

This note answers two related but materially different questions:

1. Can DJI RC 2 / DJI Fly expose a Remote ID on/off or region control?
2. Can FindUAS provide a safe switch and region selector for receiver compatibility testing?

The short answer is **no** to a general aircraft-broadcast switch and **yes** to an isolated,
offline compatibility-test mode. A test profile must never be presented as changing the aircraft,
remote controller, receiver, radio country code, channel plan, or transmit power. A separate
2026-08-27 research harness verified reversible FC-area and Sky-country transactions. Its single
Ground request had no matching ACK and the next GET remained CN. Those narrow hardware results are
not capabilities of the FindUAS application and are not a Remote ID or complete-region switch.

This document records research and an implementation boundary. The application now implements the
fail-closed **control-plane safety preview** described below. It is a local dry run only: the
per-frame evidence validator, synthetic replay pipeline, and real RF source adapter remain future
work.

## Decision summary

| Proposed control | Evidence and meaning | Product decision |
| --- | --- | --- |
| Disable ordinary aircraft Remote ID | No public generic DJI switch was found; US and current Chinese requirements explicitly prevent an ordinary operator disable control | Do not implement |
| French Electronic ID switch | Product-139 native FLYC `0x03/0x77` is exact: GET `[02]`, SET `[00]/[01]`, static default receiver `0x92`, GET ACK `[result,state]`, SET ACK `[result]`; two artificial direct-USB GET routes returned no canonical ACK | Report those routes as unavailable and keep it research-only; require an official private-runtime GET/ACK and never call it generic RID |
| EASA operator registration / OPID | Product 139 registers the `OperatorRegistrationNumber` String GET/SET handlers on `0x03/0x78`; the action provides GET, validated SET, and DELETE | Identity-data entry only; never label it a broadcast switch |
| Legacy/industry EID names | `EidOpen`/`EidClose`/`EidIsOpen` and industry-France `EIDBroadcastEnable` stop at generated/shared metadata in current Fly; current `libsdk_jni.so` has no corresponding handler or UAV139 characteristic | Not applicable fallback controls for current Fly 1.21.10/product 139 |
| DJI MSDK area strategy | Selects a regional SDK delegate for development; it is not proof of changing the aircraft's true region or over-the-air format | Investigate only in a separate, supported MSDK test app |
| FlySafe `RID_UNLOCK` | DJI officially defines license type 6, with level 1 for EU RID unlock and level 2 for China RID unlock. The supported flow is account login, signed-license download, FC-SN filtering, push/pull, then enable/disable; a retained delegate branch suggests a matching enabled license may produce `NO_BROADCAST` | Leading candidate for a stable, authorization-backed laboratory switch; keep read-only until Mini 5 Pro inventory/support and independent RF behavior are verified. Never synthesize or replay a license |
| EU C0 RID policy | Current official DJI Fly pairs `IsEuCeEnableC0Rid` with `EU_CE_enable_c0_rid_0` (hash `0xF80992FE`), type 0 and width 1; business logic owns it from cloud country membership plus C0 certification, while both current F7 routes returned status `03` rather than metadata | Observation-only; no F8 snapshot/rollback target or RF semantics exist, so F9 is a hard do-not-send and this is not a user switch |
| Broadcast-effect policy | Current official DJI Fly pairs `CccBroadcastSignalQuality` with `ccc_broadcast_signal_quality_0` (hash `0xD7757AD2`) and IntMsg config handlers; business logic packs bitmap/quality | Observation-only; converter type does not establish wire width, and unknown bitmap meanings make `0`/`1` unsafe on/off assumptions |
| RC 2 localhost status observer | Historical v0.1–v0.4 opened a second input-only `40007`/`40009` connection, but adjacent official framework evidence now proves these endpoints default to a single active fd and a newcomer may replace DJI Fly's connection | Withdrawn: do not install or start. Offline parsers remain research material; v0.8 replaces it in place with a no-permission/no-socket environment probe and still has no switch semantics |
| N3Live command/DUML evidence | Pinned `bb254b0`: Goggles N3 USB IF4 framing/CRC and a 416-command template-symbol inventory; N3Live has no RC-local socket, RID decoder or selector parser | Keep separate from the retired observer's selector-0 target admission; neither proves clear O4 RF, and a symbol-table entry is not payload/route/product/setter proof |
| RC 2 DJI Fly JVMTI V0 canary | Final APK SHA-256 `4a3867251a745ce5db6c0513c23def5c97e53a57e17f4d611621895e4e323c73`; ARM64-only, no DEX/permission/component/shared UID; runtime is limited to `GetEnv(JVMTI)`, `GetVersionNumber`, `DisposeEnvironment` and one fixed numeric log | Built and independently audited, never copied/installed/attached. The earlier non-disposing build is revoked. Do not stage before v0.8 and a separately audited caller close live debug/ABI/helper/SELinux/target-load gates; success would prove only attach reachability |
| RC 2 DJI Fly JVMTI V1 semantic anchors | Final APK SHA-256 `ccdf198c83ecdd3d33a54192e2bffeb9ab89ce65289497643d16f5a00bff62b2`; counts two exact already-loaded France-EID thunks and shared ClassLoader only | Offline-only, never copied/installed/attached. It invokes no Java/GET/LISTEN/SET and follows v0.8 plus V0; success proves topology only |
| Same-owner raw EID GET/ACK | Current DJI Fly's `JNIRawData.native_SendData` can reuse the initialized SDK/SessionMgr and return the ACK application payload, preserving France-EID `[result,state]`; the older pre-converter/observer tap remains a fallback | Conditional static design only. No send until live productId/deviceId/senderIndex/HostID, product139/France/EID identity, loader and connection epoch are exact; never pair it with a typed GET |
| FindUAS local dry-run control | Exercises precheck, staging, short lease, stop, rollback, lockout, and audit behavior without touching hardware | Implemented as a safety preview |
| FindUAS validation profile selector | Selects the expected fields and conditions for one versioned regional profile | Implemented as metadata and labelled “does not change device region” |
| FindUAS replay/evidence validator | Feeds synthetic or redacted FF01 data through an isolated decoder and validator | Designed, not yet implemented |
| Real receiver RF compatibility test | Requires a standards-compliant source and controlled RF setup | Separate lab phase, not an aircraft country-code change |

## Implemented administrator safety preview

The Simplified Chinese sidebar entry is **兼容性实验室** and the page title is
**管理员实验室（安全预览）**. The fixed user-facing boundary is
“不发射无线电 · 不写飞机 / 遥控器 / 接收器”. The only enabled actions stage a rehearsal, start a
local-only dry run, and stop and roll back. They mutate in-memory state only.

The pure-core model is intentionally small and fail-closed:

- `RIDLabProfile` has ten metadata-only cases: `raw`, `usStandard`, `usModule`, `euIntegrated`,
  `euAddOn`, `japan`, `china`, `uk`, `singapore`, and `franceEID`;
- `RIDLabPhase` follows `complianceAuto -> precheck -> staged -> activeDryRun`, then `rollback`
  back to `complianceAuto`; a fault enters `lockout` and requires an explicit reset;
- `RIDLabBroadcastIntent` records `silent` or `broadcast` as a future-source scenario input. Even
  `broadcast` is inert with the current backend and does not switch an aircraft or emit RF;
- `RIDLabSession` owns the selected profile, all five checklist states, a lease between 5 and
  15 minutes, expiration, and a bounded audit-event list;
- entering `activeDryRun` requires every checklist item and a valid lease; stop or expiration
  returns to `complianceAuto`, and armed state is not persisted across relaunches;
- audit events are typed phase/profile/broadcast-intent/checklist/lease records only. They are
  memory-only and have no free text, identifiers, coordinates, packets, credentials, keys, or
  registration secrets.

The current source capability is fixed to `RIDLabSourceCapability.noRFBackend`:

| Capability | Value |
| --- | --- |
| Local dry-run state machine | yes |
| Transmit Remote ID | no |
| Write aircraft/controller/receiver | no |
| Change device region | no |

The DJI aircraft/controller card keeps its Remote ID and region **write** controls locked. It also
offers an explicit refresh of a fixed read-only USB observer: device presence, FC area, Sky/Ground
country, and France EID only when FC independently reads FR. The bridge has no raw-command or
setter API. The receiver card shows read-only application/session diagnostics: connection,
live-target and FF01/assembled/decoded/rejected counts, and the detected FF01 wrapper. Neither card
creates a device-write, network, or RF control transport.

### Current DJI hardware boundary

On 2026-08-27, macOS enumeration showed the product names **DJI Mini 5 Pro** and **DJI RC 2** over
USB; no serial numbers or other persistent identifiers are recorded here. DJI's official MSDK
5.18.0 supported-product list does not include that aircraft/controller pair. USB visibility
therefore does not establish a supported MSDK control session, and FindUAS leaves the two controls
locked.

A separate, explicitly authorized research harness first performed a controlled FC-area
`CN -> US -> CN` transaction with matching ACKs and fresh readback after each write. A later
surface-specific run required two CN preflight GETs per airlink route. Sky completed one
`CN -> US -> CN` loop with matching ACKs and fresh GETs at US and CN. Ground transmitted one US
request without a matching ACK; the following GET remained CN, so the harness sent no restore SET
and did not retry. This is one FC loop, one Sky loop, and one inconclusive Ground attempt with no
observable or durable applied state—not a synchronized region switch. RC/DJI Fly policy remained unavailable/unknown, and no
Remote ID, EID, SDR-power, account, flight-limit, or receiver setting was written.

The external FindUAS receiver was offline during those experiments. No conclusion can therefore be
drawn about actual Remote ID transmission, regional packet format, transport, or RF reception.

The two policy hashes above now have a same-generation static read path in the official DJI Fly
1.21.10 native library: FLYC `0x03/0xF7` reads parameter metadata and `0x03/0xF8` reads its value;
`0x03/0xF9` writes and `0x03/0xFA` resets. FindUAS implements none of these as a generic endpoint.
A work-only probe is hard-locked to F7/F8 and those two hashes. During its first live attempt,
DJI Assistant 2 was active and `claimInterface` returned `LIBUSB_ERROR_ACCESS` before any USB
request was sent. This is consistent with USB ownership/permission contention; causation was not
independently proven. After Assistant was closed, the retry reached both live routes: each
candidate returned only the one-byte F7 status payload `0x03`, while known height/distance
parameters passed on the same RC-routed plaintext transport. The SIMPLE-encrypted control had no
matching reply. Neither candidate therefore qualified for F8 or F9 on this product.

An independent probe linked against the same fixed C bridge used by the app subsequently reproduced
the final read-only vector twice: FC=`CN`, Sky=`CN`, Ground=`CN`, RC/DJI Fly policy unavailable. Because
the UI observer gates the EID query on FC=`FR`, it will not send that request in this CN state; the
separate CN-state EID probe had already shown the request as unavailable. This distinction prevents
both unnecessary queries and the unsafe UI inference “no response = off”.

### Rootless RC 2 observer retraction and safe replacement

A third-party research clone was rejected because its approximately 52 MB APK bundled unrelated
FCC, accessibility, boot-receiver, package-install, log, and Wi-Fi capabilities. An independently
implemented v0.1–v0.4 then narrowed behavior to manual, input-only localhost observation. Its
no-output-stream, strict-parser and privacy properties were real, but they were not sufficient:
establishing the TCP connection itself can be disruptive.

Adjacent official RC331 `10.00.0700/0205` artifacts show `40007` and `40009` are TCP servers with no
protective connection-retention flag. The recovered framework's default branch accepts a newcomer,
closes the old active fd, and replaces it. Thus a second client may disconnect DJI Fly even when it
never obtains an output stream or sends a byte. Historical observer v0.1–v0.4 is withdrawn from live
use and must not be installed or started. Exact `07.00.0100` code remains unproven, but the asymmetric
transport risk requires fail-closed behavior. The old parsers and their tests remain offline-only
research artifacts.

Version 0.8 keeps package name `com.finduas.ridobserver` and the same signer solely to overwrite an
installed historical build. It is built from an isolated safe source set and requests no Android
permissions. It has one launcher Activity and no service, receiver or provider; contains no socket,
`40007`/`40009`, DUML, `Parcel`, DJI protocol Binder application transaction, external Activity
launch or process execution; and never starts a DJI component or writes a property. A manual
snapshot only checks the `protocol` Binder's liveness/descriptor and reports fixed-package UID,
process visibility, signer, ABI, component, installed/native-library paths, observer-view DAC/
SELinux access, readable expected-library hashes, `ro.debuggable`, and upgrade-marker facts. v0.8
adds fixed read-only hashes for the `dpad_fuli` APK/DEX entries, `framework.jar`/`services.jar`, and
the broker's `dji.json`/`libduml_frwk.so`, with independent package-code, framework/server-ABI and
broker verdicts. Its schema, run ID, timestamps and clipboard copy make the report auditable; they
do not broaden the probe. The 2,477,789-byte APK has SHA-256
`b67a99621440088a39d212483d2de69a47fdc26850b59ed7fecfa9e1e8c70fb1`; 24 tests, lint,
manifest/signature/zipalign and app-class DEX denylist pass, and three clean builds are identical.
Even a matching descriptor is an environment gate, not a RID state, transaction authorization or
switch.

N3Live was reviewed at pinned revision
[`bb254b0`](https://github.com/brendan779/N3Live/tree/bb254b0d0b1f5ac79462e9fe3ea986fc91adeec0).
N3Live itself reads Goggles N3 USB IF4, retains byte 8 as an opaque `cmd_type`, and has no
`40007`/`40009`, RID-specific parser, selector decoder, decryptor or key path. The separate retired
observer's target RID/FlySafe decoders accept only selector 0; that proves clear payload only at
the RC-local broker boundary and does **not** prove the O4 air link is plaintext. N3Live's generated
416-command list is a name/constant inventory extracted from an input native library that is not
committed or hashed in the repository. It is not a call graph and does not prove payload layout,
receiver route, Mini 5 Pro support, policy gates, or safe writes.

The V1 ARM64 JVMTI semantic-anchor resolver is likewise offline-only. Its final audited APK
SHA-256 is `ccdf198c83ecdd3d33a54192e2bffeb9ab89ce65289497643d16f5a00bff62b2`. It only enumerates
already-loaded classes, counts the exact `electronicIDBroadcastOn` and
`electronicIDBroadcastExisted` generated thunk signatures and their shared ClassLoader, cleans all
references/allocations, disposes its JVMTI environment, and logs numeric counts. It invokes no Java
method and has no GET/LISTEN/SET, socket, Binder, or DUML path. It has never been copied, installed,
or attached and cannot be considered until v0.8 and V0 separately pass. A success would establish
semantic-anchor topology only, not an EID getter or RID control.

Current DJI Fly also contains a narrower conditional path than native tapping:
`JNIRawData.native_SendData(productId,deviceId,...)` constructs the request inside the loaded SDK,
reuses its ProductMgr/RawMgr/SessionMgr and returns the raw ACK application payload through
`SendInterface.onReceivedData`. It can express the current France-EID object as selector 3, retry 0,
timeout 500 and body `[02]`, preserving `[protocol_result,state]` without a second broker socket or
observer-map mutation. It is not live-admissible until productId/deviceId/senderIndex/HostID,
product139/France/EID identity, ClassLoader and connection epoch are resolved from the current
subject/session; any unknown stops before send, and a typed GET must not run alongside it. The older
pre-converter point and all-command observer remain static fallbacks whose locking/thread/ABI/
lifecycle gates are still open. No GET, SET, hook or dynamic registration has been run.

The stock `dpad_fuli` Protocol page cannot substitute for that route. It exposes no selector or
retry control, leaves selector at 0, and its `Pack` Parcel omits `maxRetryCnt`, reconstructing it as
2 in system_server; `ActQueue` can therefore perform the initial send plus two retransmissions.
It must not be used for `03/77`, and its push-listen button also writes an SD-card log.

The Mac host opened the RC 2 ADB bulk endpoints and sent `CNXN`, but the controller returned neither
`AUTH` nor `CNXN`. The transport remained `offline` with platform-tools 37's legacy and libusb
backends and with platform-tools 35.0.2. Consequently no shell or `adb install` was used. Full USB
parentage then showed that the visible 45 GB and 256 GB storage LUNs both belonged to the aircraft,
not the RC 2. An interim APK copy on aircraft internal storage was deleted only after its exact hash
matched the known work artifact, and the aircraft volume was safely unmounted. The RC 2 microSD was
not exported through the current USB configuration. After the first Mac-formatted card was rejected,
the RC 2 initialized the card itself; the Mac then copied hash-matched artifacts through a separate
reader. The user successfully installed the DJI-signed PackageInstaller/FileManager updates and an
older observer APK, proving the manual no-root/no-ADB update path. The older observer must remain
stopped and be overwritten by v0.8. At the latest check the RC 2 USB device remained visible but ADB
was still `offline`; the Apple USB-C reader was connected with no visible medium, while both mounted
45 GB/256 GB volumes still belonged to the aircraft. No v0.8 hardware result has yet been collected.

The v0.8 replacement cannot log in to a DJI account, observe broker traffic, obtain or upload a
license, change a license's enabled state, or establish RF behavior. It only decides whether a later,
separately reviewed system-identity or in-process read-only probe is even eligible to be considered.

The adjacent stock `dpad_fuli` Shell page is not such a reviewed launcher. Opening it automatically
attempts `adb shell su`, writes a test command and runs `adb version`; its executor discards stderr
and exit status. It must not be opened for this work. V0/V1 require a separately audited,
side-effect-free, result-preserving UID1000 caller even if every v0.8 environment field is favorable.
Static review of all externally reachable `dpad_fuli` components found no alternate fixed-command
entry: `DevActivity` ignores extras, the Shell Activity is private and invokes the unsafe root probe,
the receiver accepts only the literal `fuli_continue`, and the exported service exposes no Binder.
Android 11 `attach-agent` also requires `SET_ACTIVITY_WATCHER`; a normal debuggable carrier or a
`/system/bin/cmd` child does not gain shell/system caller identity.

### Why a self-written switch must control an external source

DJI's official MSDK 5.18 [`IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
has no general Broadcast Remote ID enable/disable setter. Its broadcast-enabled and working-state
values are read-only status. The only public boolean transmitter control is the separately scoped
French EID function `setElectronicIDEnabled()`. Area strategy, Sky/Ground country, managed
`RID_UNLOCK`, and signal-quality cloud controls are not interchangeable with that function.

The Mac's built-in radios also cannot be used as an honest standard transmitter through public
APIs. Apple documents that
[`CBPeripheralManager.startAdvertising`](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising%28_%3A%29)
accepts only the local-name and service-UUID keys. It cannot provide the required Remote ID BLE
service data or select Bluetooth 5 coded/extended advertising; public CoreWLAN does not expose raw
Beacon vendor-IE or RID NAN injection either.

A self-written implementation must therefore be an explicitly labelled **external laboratory
transmitter**, preferably an ESP32-S3/C3 connected over USB. Its typed protocol must expose
handshake, prepare, start, state, stop, and an actual-active transport mask; it must not expose raw
radio, country, DJI, or arbitrary-device commands. Device firmware must stop BLE advertising,
remove Wi-Fi Beacon Remote ID elements, stop NAN, and enforce a hardware watchdog and absolute
lease. A STOP acknowledgement alone is insufficient: state readback plus an independent quiet
observation window are required. Existing [ArduRemoteID](https://github.com/ArduPilot/ArduRemoteID)
rate parameters do not by themselves establish that already-started BLE/Beacon transmissions have
stopped.

ArduRemoteID is GPL-2.0-or-later and must remain a separately licensed companion if reused. A clean
firmware implementation can instead build on Apache-2.0
[`opendroneid-core-c`](https://github.com/opendroneid/opendroneid-core-c) while preserving its license
and notices. Neither option controls DJI's integrated transmitter.

## “Remote ID switch” is not one control

### Ordinary Broadcast Remote ID

DJI Fly receives a working-state report from the aircraft through `KeyRidWorkingStatusPush`. It
can report `IDLE`, `WORKING`, an operator-location or firmware error, `NO_BROADCAST`, or
`NOT_SUPPORTED`. That is a status path, not a writable user preference.

No generic local `force working`, `broadcast enabled`, or `disable RID` debug Boolean was found in
the recovered DJI Fly and MSDK paths. The aircraft's self-report must also not be confused with an
independent RF observation; a separate receiver is still required to show that packets are
actually receivable.

The current DJI Fly 1.21.10 native and every readable 1.21.4 business DEX were also checked across
the known regional planes. They contain separate France EID, EASA OPID/C0, Japan DIPS, FAA/US
status, China OID/UTMISS, and FlySafe exception mechanisms, but no ordinary Boolean master switch
spanning them. Legacy `EidOpen`/`EidClose`/`EidIsOpen` declarations do not close a current handler,
product registration, caller, or gate; `EIDBroadcastEnable` is the MSDK France-industry delegate,
not the consumer DJI Fly/WA150 path. All four stop at generated/shared metadata in current Fly;
current `libsdk_jni.so` has none of their handlers or UAV139 characteristics. None is a current
product-139 fallback master switch.

The two current-DJI-Fly FC policy names are also no longer viable live switch candidates on the
tested Mini 5 Pro. With Assistant closed, strict direct-aircraft and RC-routed F7 metadata GETs for
`ccc_broadcast_signal_quality_0` and `EU_CE_enable_c0_rid_0` each returned only status byte `0x03`,
whereas known height/distance parameters succeeded through the same plaintext transport. A legacy
SIMPLE-encrypted control produced no reply. Because neither policy field supplied metadata, no
value GET or write was attempted. Their presence in DJI Fly proves a multi-product SDK mapping,
not availability on every aircraft. The UAV139/wa150 abstraction actually registers both mappings,
so `0x03` is best described as unavailable on the live FC metadata surface; it does not prove that
DJI Fly lacks the key, nor distinguish target omission from a runtime/product/permission gate.

The regulatory direction is consistent with the implementation:

- The FAA describes Standard Remote ID aircraft as continuously broadcasting after the aircraft's
  self-test and says the operator cannot disable Remote ID.
- China's GB 46750—2025 requires automatic continuous reporting while the aircraft is moving under
  its own power and says the product must not provide a transmit-disable function.
- European and Japanese rules likewise require direct identification during the applicable
  operation; they are not a basis for adding an arbitrary user off switch.

An authorized exception is different from an ordinary debug switch. Testing that needs a lawful
deviation belongs in an approved program, controlled site, or laboratory process.

### French EID is a narrow, real switch

The recovered DJI Fly path is:

```text
SettingRemoteIdSwitchViewModel
  → RemoteID.electronicIDBroadcastOn
  → V1RemoteIDGenKt.v1RemoteIDElectronicIDBroadcastOn()
  → KeyEIDSwitch
```

`KeyEIDSwitch` is declared readable, writable, and listenable. The surrounding presence logic
checks the French EID capability and area; the public DJI MSDK similarly exposes
`setElectronicIDEnabled()` under the France strategy. The exact recovered MSDK 5.18 native mapping
is FLYC command set `0x03`, command ID `0x77`:

| Operation | One-byte request payload |
| --- | --- |
| GET EID state | `0x02` |
| SET EID off | `0x00` |
| SET EID on | `0x01` |

In a matching response, byte 0 is status and bit 0 of byte 1 is the reported state. A SET must
always be followed by the `0x02` GET and an explicit comparison; an acknowledgement alone is not
state verification. Missing, short, mismatched, or unsuccessful responses are `unavailable`, not
`off`.

During the 2026-08-27 test, the current aircraft reported the CN area and a direct-aircraft,
read-only GET (`0x02`) produced no matching response. Its French EID state can therefore only be
reported as **unavailable** in the current product/region state. No OFF or ON request was sent, and
neither is allowed without a successful capability GET plus a separately authorized readback and
rollback procedure.

This narrow switch must not be generalized to FAA Remote ID, ordinary EU direct identification,
EU operator registration, Japanese registration, Chinese operation identification, or a global
RID control.

FindUAS is a BLE client for the external receiver and has no supported DJI aircraft control path.
The narrowly labelled, FR-gated fixed GET may remain as experimental read-only status; an EID
setter and any mapping from French EID to a generic Remote ID switch do not belong in the app.

### EASA OPID is a string identity route, not a switch

Current DJI Fly 1.21.10 statically closes product 139's registered
`OperatorRegistrationNumber` String GET/SET handlers on `0x03/0x78`. The request action distinguishes
GET `[02]`, DELETE `[01]`, and validated SET `[00][10][first 16 bytes]`; the application first checks
the complete 20-character input with its area-code and Luhn mod-36 rules. A GET ACK begins
`[result,length,data...]`, while SET/DELETE return a result.

This is the EASA operator-registration/OPID data plane. It can provide identity data used by a
regional RID workflow, but it is not a Boolean that enables or disables RF broadcast. The runtime
Characteristics can still override the static destination, and no live OPID transaction was
performed for this static result.

### DJI's area strategy is a development policy selector

DJI documents `setUASRemoteIDAreaStrategy(AreaStrategy)` as a way for an MSDK application to select
another area strategy during development. The official sample separates at least these behaviors:

- United States: broadcast status;
- Europe: operator registration and C-class state;
- Singapore and United Arab Emirates: operator registration;
- Japan: UA registration;
- China: real-name/UOM state;
- France: European behavior plus the EID switch.

Static analysis of the MSDK 5.18.0 artifact also retains real-area validation, EU equivalence, and
extra restrictions around transitions into or out of the China strategy. Some retained bodies
appear after stub returns, so this is structural evidence rather than a promise about every
runtime build.

The setter can therefore be useful in a dedicated MSDK development application for exercising SDK
views and registration flows. It does **not** demonstrate any of the following:

- that DJI Fly on RC 2 accepts the same override;
- that the aircraft's authoritative regulatory country changes;
- that the RF payload or transport changes;
- that an aircraft becomes a valid transmitter for another jurisdiction;
- that O4/FCC/CE power policy changes.

These claims require separate readback and independent RF evidence. FindUAS must not call an
unknown DUML command in place of the supported SDK API.

### DJI Fly also has an internal real-area injection path

This is separate from the MSDK area-strategy selector. Recovered DJI Fly code has an internal-only
preference named `key_country_code_local_forever_debug`. When the build reports itself as an
internal application and the value is non-empty, it feeds a mock country into the native area-code
manager. Normal background logic can then propagate the selected area to flight-controller,
Sky/Ground radio, and in some products Wi-Fi area-code keys.

Another internal preference, `debug_area_code_switch`, only gates part of this synchronization; it
is not itself a country selector and does not consistently isolate the flight controller.

This is strong evidence that DJI can perform an internal real-area experiment. The bounded
2026-08-27 hardware checks independently verified the FC-area and Sky-country setters and their
restoration; the Ground request did not obtain a matching ACK or change the following CN readback.
They did not activate this DJI Fly preference or synchronize FC, Sky, Ground, or RC policy as one
transaction. The mechanism
remains a poor Remote ID compatibility control for an external test tool because it crosses
multiple regulatory surfaces at once:

- flight-controller area and FlySafe policy;
- Remote ID regional behavior and registration flows;
- Sky/Ground radio country policy and possibly the available channel/power profile;
- cached and continuously synchronized state, with retry behavior on failed writes.

It has no supported production UI, its native update rules are not fully recovered, and changing
the FC field did not by itself prove which Remote ID packets were emitted. Broader synchronized
writes remain prohibited unless a separate, authorized laboratory protocol defines each surface,
exact readback, isolation, restoration, and independent RF measurement. This path must not be
implemented in FindUAS.

### `RID_UNLOCK` is the leading managed-license path, with unverified Mini 5 Pro behavior

DJI's official FlySafe model includes `RID_UNLOCK`. The official Cloud API publishes it as license
type 6 and defines level 1 as **EU RID Unlocked** and level 2 as **China RID Unlocked**. Official
MSDK documentation also closes the intended trust flow: log in to a DJI account, download the
account's signed licenses, push only licenses whose flight-controller serial matches the connected
aircraft, pull the aircraft inventory back, and use `setFlyZoneLicensesEnabled` to enable or disable
a selected license. This is therefore not a locally minted preference or a generic configuration
bit.

The current public FlySafe front end exposes separate Mainland and overseas RID application forms,
but server response `support_unlock_type` must contain `Rid` before the product is eligible, and the
request binds product information to the flight-controller serial. No public response proves
Mini 5 Pro/WA150 eligibility, signed-license issuance, or aircraft acceptance. The official chain
therefore remains account authorization and server eligibility, then a genuine FC-bound signed
license, aircraft pull/readback, bounded enable/restore, and independent motor-on RF observation.
A missing result at any stage is unavailable/unknown, not permission to synthesize a record or call
the enable endpoint blindly.

The current MSDK 5.18 artifact adds a useful but still static clue. Its retained delegate branch
after a leading stub return treats an enabled `RID_UNLOCK` license matching the current EU/China
area strategy as opened, then reports `broadcastRemoteIdEnabled=false` and state `NO_BROADCAST`.
The consumer delegate selection does not contain a general Mini 5 Pro exclusion. Neither point
proves that the provided stubbed artifact executes on this aircraft, that a RID license is already
installed, or that the RF transmitter becomes silent.

The older DJI command family provides a bounded reference for aircraft-side inventory: ADS-B/FlySafe
command set `0x11`, command `0x11`, with a one-byte record index. Its response exposes total count,
enabled/valid state, record type, and level. Research output must redact license ID, account/device
identifiers, description, timestamps, coordinates, and raw payloads. Upload command `0x10` remains
excluded. The current MSDK binary independently maps license enable to `0x11/0x12`, but neither that
command nor any raw generic path may be added to FindUAS. A future write experiment is justified
only if a genuine type-6 license is found and must use exact license identity, pre/post pull, a
bounded rollback, and independent receiver observation after motor start. Never synthesize,
modify, forge, or replay a license.

The strict work-only probe was then exercised once through both the direct-aircraft and RC 2 proxy
routes. Both fixed `0x11/0x11` requests timed out. Immediate positive controls on the same live USB
paths still returned FC area `CN` and Sky/Ground country `CN` with response type `0x80`. The timeout
therefore belongs to those fixed hand-built transactions, but it is not evidence that the aircraft
is disconnected, that its license inventory is empty, or that V2 is unsupported.

The current MSDK 5.18 pull architecture provides several possible explanations without selecting
one. Its public manager first reads the flight-controller serial, then calls
`queryFCLicensesJni`, which reaches
`native_QueryLicenseFromFC(productId, deviceId)` and `ModuleMediator::QueryLicenseFromFC`. The
result is decoded as a whole `FlysafeLicenseGroup`, while the current native session performs the
underlying pagination. Its own PackType table directly maps query `0x38` to `0x11/0x11` and
set-enable `0x39` to `0x11/0x12`; the numeric endpoints are not the missing piece.

The current contract includes a readiness gate, support/version selection, product/version receiver
route, V2 one-byte indexing or V3/V4 `00 01` group-info plus `00 (index << 1)` paging, an ACK result
byte, and version-specific record/protobuf parsers. The set-enable V2/V3/V4 builders and result
parsers are also statically recovered. These findings do not make a safe raw command: a legitimate
current session, genuine type-6 record, exact readback/rollback, target acceptance, and independent
motor-on RF observation all remain unverified.

DJI Fly evidence is narrower than the MSDK model. The protected 1.21.10 package still contains the
generic account-license and aircraft-license JNI/UI names, but no recovered current method body or
type-6-specific UI/server entitlement. The closest executable prior version, 1.21.4, recognizes
only license types 0--4 and 255; type 6 becomes `UNKNOWN` and can fall through to polygon handling.
Its generic switch must therefore not be treated as a RID switch. In that prior flow, login and
network gate server refresh of signed account licenses, while FC inventory query and enable-state
display are not directly gated by an account Boolean. Import remains FC-SN/current-device bound.

## A region is three independent test dimensions

A single “US / EU / JP / CN” menu hides three orthogonal layers:

| Layer | Examples | What FindUAS can currently prove |
| --- | --- | --- |
| Regulatory and semantic profile | US Standard vs module, EU integrated vs add-on, Japan, China | Whether the receiver's translated JSON contains observable fields during a bounded window |
| Over-the-air transport and wire format | BLE legacy, BLE 5 extended/long-range, Wi-Fi NAN, Wi-Fi Beacon, Chinese GB packet | Nothing directly; the receiver does not expose raw RF packets |
| Receiver-to-Mac wrapper | FF01 Legacy JSON or FF01 V2 framing | Full framing, decoding, merging, and UI behavior |

The current “protocol mode” in FindUAS is only the last row. It should be described as **FF01
wrapper mode** in future UI work so it cannot be mistaken for an ASTM/European/Chinese selector.

Receiver FF02 configuration currently contains only the observed channel, dwell time, vibration,
sound, and flashlight settings. Changing a Wi-Fi scan channel does not select a Remote ID standard
and does not configure BLE advertising support. FF03 remains unknown and must not be written.

## Versioned validation profiles

The safety preview uses explicit enum cases rather than executable country settings:

- `raw` — receiver output without a jurisdiction verdict;
- `usStandard` — US Standard Remote ID aircraft semantics;
- `usModule` — US broadcast-module semantics;
- `euIntegrated` and `euAddOn` — EU integrated and add-on categories;
- `franceEID` — the narrow French EID validation context, not the `KeyEIDSwitch`;
- `japan` — Japanese direct Remote ID semantics;
- `china` — GB 46750—2025 broadcast-side semantics;
- `uk` — the UK public-broadcast data surface;
- `singapore` — Singapore AS-10 semantics.

Profiles are read-only data. They may contain the standard/version, device category, field
requirements, one-of conditions, source URLs, review date, and a list of properties that the
receiver output cannot establish. They must not contain a country-code write, frequency, power,
DUML command, GATT command, or executable callback. Selecting one currently changes only the
dry-run session's metadata; it does not yet produce a compliance verdict or any packet.

### Profile differences that affect the data model

| Profile | Important observable requirements | Important limitation in the current model |
| --- | --- | --- |
| US Standard aircraft | UAS identity, aircraft position/altitude/velocity, control-station position, time mark, emergency status | Cannot prove the accepted means of compliance or RF transport from translated JSON |
| US broadcast module | UAS identity, aircraft dynamics, takeoff position/altitude, time mark | Must not be validated using the Standard-aircraft control-station/emergency rules |
| EU integrated/add-on | Operator registration, physical serial, aircraft position/height/course/speed, pilot or takeoff position, applicable emergency/category/class data | Device category and message provenance are currently flattened |
| Japan | Registration ID plus manufacturer serial, authentication, aircraft dynamics, applicable operator/takeoff data | One `uasID` cannot represent both Basic IDs; authentication evidence is missing |
| China GB 46750—2025 | Product ID, registration mark, category/class, control-station or takeoff position and height, aircraft dynamics, state, coordinate system, accuracy and millisecond time | Network reporting, raw GB packet conformance, RF performance, and dual-mode hardware cannot be proven from FF01 JSON |
| United Kingdom | Public broadcast portion of the UK operator identity, aircraft serial/dynamics, pilot position, emergency state and timestamp under the applicable CAA schedule | Never request, store, display, or validate the private/secret suffix; do not treat the EU profile as identical |
| Singapore AS-10 | EN 4709-002-derived identity and aircraft/operator position semantics | Transport, cadence and RF-power requirements need raw RF measurements, not translated JSON |

China requires special treatment. GB 46750—2025 is not ASTM or ASD-STAN with a changed region
byte. It defines its own variable-field packet and requires both broadcast and network operation
identification capabilities. The broadcast side uses at least Bluetooth 5.0+ or Wi-Fi, while the
network side uses an external communications link. A local receiver can test only the broadcast
side, and FindUAS sees only the receiver's translation of that side.

The observed receiver string `RID_Standard: GB42590-2023` is not authoritative profile evidence.
GB 42590—2023 is the Chinese UAS safety-requirements standard, while the current operation-
identification standard is GB 46750—2025. Preserve the receiver's string for diagnostics, but do
not automatically select or pass a profile from it.

## Why `DroneTelemetry` is not yet a compliance evidence model

The current normalized model is appropriate for display, but a validator needs provenance that it
intentionally discards:

- sentinel normalization cannot distinguish “present but unavailable” from “not transmitted”;
- the 120-second target merge can make an old field satisfy a new observation;
- one `uasID` cannot preserve Japan's two identities;
- alternate time encodings are converted or discarded for display;
- altitude and position aliases lose their original message/source type;
- translated JSON cannot prove authentication, raw packet encoding, cadence, RF channel, or
  transmitter performance.

Before adding profiles, introduce a non-persistent `RIDDecodeEvidence` model. It should record
field presence state, unavailable state, identity list/type, raw time form, message/source label,
and per-field last-observed time. Validation runs over a bounded observation window and reports
only:

- **observed**;
- **missing in this observation**;
- **not determinable from FF01**.

The UI must never label this result “certified”, “compliant”, or “approved”.

## Safe compatibility-test architecture

### Implemented no-RF control plane

```text
Administrator Lab UI
       │ profile / inert broadcast intent / checklist / 5–15 minute lease
       ▼
RIDLabSession ──► bounded typed audit events (memory only)
       │
       └────────► noRFBackend
                    supports dry run = yes
                    transmit RID = no
                    write device = no
                    change region = no

       ╳ BluetoothManager / USB / network / RecordStore / RF transmitter
```

This layer makes the operator workflow testable without pretending that an on-screen state is an
over-the-air state. It is also the fail-closed contract a future external source adapter must meet;
replacing the backend may add capability, but must not weaken the phase, lease, stop, rollback,
lockout, privacy, or evidence requirements.

### Planned evidence/replay plane

```text
versioned synthetic fixture or redacted capture
          │ timed FF01 notification bytes
          ▼
isolated assembler → TelemetryDecoder
                         ├─ per-frame RIDDecodeEvidence → validator window → findings
                         └─ DroneTelemetry → isolated display merge
                                                  │
                                                  ▼
                   Compatibility Test view (SIMULATED / REPLAY watermark)
```

The later replay controller must own its own framing/session state. Evidence must be created from
each raw decoded frame **before** `TelemetrySession`-style target merging and then evaluated in an
explicit observation window; it must never be reconstructed from `activeTargets`. The controller
must not publish into the live `BluetoothManager` or `AppState` path, because that path can alert,
merge with real targets, and persist history through `RecordStore`.

### Current safety-preview behavior

- The control is in the separate **兼容性实验室** view, not ordinary receiver settings.
- It defaults to `complianceAuto` and does not restore staged or active state after relaunch.
- The profile selector says “验证配置文件不会改变设备地区”.
- The broadcast-intent selector is only a staged expectation; it never claims to switch real RF.
- The permanent banner says “不发射无线电 · 不写飞机 / 遥控器 / 接收器”.
- All five checks and a 5–15 minute lease are required before the local dry run starts.
- The available actions are stage rehearsal, start local-only rehearsal, and stop/rollback.
- The DJI controls are locked and the receiver surface is read-only.

### Requirements for the planned replay/source views

- Show a permanent `SIMULATED` or `REPLAY` banner on every test target.
- Disable sound, notification, whitelist, history, map mixing, exports that look like live flights,
  and every FF02/FF03 write.
- Clear the isolated session whenever the profile or scenario changes.
- Bound file size, event count, playback speed, observation window, and total runtime; allow
  immediate cancellation.
- Permit only obviously synthetic fixture identities such as `TEST-*` and artificial coordinates
  in the repository.
- Validate only an operator ID's public broadcast portion. Never request, import, persist, display,
  or include a jurisdiction's private/secret suffix in a fixture.

### Replay format

A versioned JSON or JSONL fixture should include:

- scenario ID and `synthetic: true`;
- relative event time;
- source characteristic (`FF01` or a deliberately included `FF02` notification);
- base64 notification bytes;
- expected FF01 wrapper mode;
- selected validation profile;
- expected decode and validation findings.

Feeding bytes at the same framing entry used by `TelemetrySession` exercises the existing
assembler and decoder. A per-frame branch creates evidence before a separate display merge, so the
test can also verify merge behavior without allowing merged state to satisfy a profile. This does
not test CoreBluetooth discovery or the receiver's RF decoder.

## Test phases

### Phase 0 — implemented control-plane safety preview

Exercise every legal and illegal `RIDLabSession` transition, checklist combination, lease boundary,
expiration, stop, rollback, lockout, reset, and bounded-audit case using the no-RF backend. Assert
that no dry-run action reaches CoreBluetooth, the independent DJI USB observer, the network,
`RecordStore`, or an RF source.

This phase proves only that the operator-facing safety state machine fails closed.

### Phase 1 — deterministic offline replay

Implement the isolated evidence model, profiles, validator, fixtures, and test view. Cover complete,
missing, unavailable, and contradictory fields for every profile. Run every semantic sample through
both FF01 Legacy and V2 wrappers. Include fragmentation, concatenation, bad lengths/trailers,
oversize input, cancellation, replay, and session-reset cases.

This phase proves application behavior only.

### Phase 2 — receiver-to-Mac BLE integration

Use a separate development device as a debug-only GATT peripheral exposing service `00FF` and only
the known FF01/FF02 behavior. It should transmit `TEST-*` fixtures, auto-stop, and have no FF03 or
configuration-write implementation.

This phase can test CoreBluetooth connection and notification lifecycle. It still does not prove
that a FindUAS receiver understands a jurisdiction's over-the-air Remote ID format.

### Phase 3 — controlled RF receiver validation

Use published test vectors or a standards-conformant transmitter implementation in a shielded box,
conducted setup, or qualified laboratory. OpenDroneID can seed ASTM/ASD-STAN test sources and now
contains a separate `libopendroneidcn` implementation for GB 46750; each generator still needs
independent validation against the selected profile. Capture the external receiver's redacted FF01
output and replay it through Phase 1.

Potential hardware/software starting points include OpenDroneID's Linux and nRF transmitters and
ESP-class ArduRemoteID implementations. None is automatically trusted. A source adapter must
identify known hardware and firmware, declare its supported transports and encoders, require a
physical RF interlock, inherit the short lease and immediate stop/timeout/rollback behavior, and
fail closed on any mismatch. An independent receiver or analyzer—not the source's own status—must
confirm what was emitted.

For each profile and transport, record four separate results:

1. the source emitted the intended packet under controlled conditions;
2. the receiver observed it over RF;
3. the receiver translated the required evidence correctly;
4. FindUAS framed, decoded, and displayed that evidence correctly.

Do not radiate synthetic identities in public airspace and do not use a DJI aircraft country-code
override as a protocol generator. A country-code readback would still not prove the emitted
standard, contents, timing, or RF power.

## Minimum regression matrix

- Complete, missing, unavailable, stale, and contradictory fields per profile.
- US Standard aircraft versus broadcast module conditions.
- EU integrated versus add-on conditions.
- Japan dual Basic ID and authentication evidence.
- Chinese field-presence, coordinate-system, accuracy, timestamp, and network-side “not
  determinable” results.
- Identical semantic result through FF01 Legacy and V2 wrappers.
- Split, concatenated, noise-prefixed, 516-byte idle, malformed, and oversize notifications.
- No cross-scenario field inheritance and a deterministic virtual clock.
- Fifty synthetic targets as an application load check, explicitly not a receiver RF certification.
- Assertions that replay produces no `RecordStore` write, alert, FF02/FF03 write, or live-target
  mutation.
- Fixture privacy check allowing only synthetic IDs and coordinates.

## Open work

1. Obtain standards-derived, redistributable fixtures for each profile without committing real
   aircraft identifiers or proprietary captures.
2. Extend the decoder evidence model before implementing any profile verdict.
3. Confirm which over-the-air transports and raw message elements the receiver hardware actually
   supports; its FF01 JSON alone is insufficient.
4. Specify and implement a capability-gated external source adapter, then validate its hardware
   identity, firmware, encoder, transport, RF interlock, lease, stop, rollback, and independent
   measurement in a controlled laboratory before enabling real transmission.
5. If DJI SDK strategy or French EID behavior is still useful, first overwrite any historical
   observer with v0.8 and collect its exact live ABI/UID/signature/debuggable/SELinux/Binder gates.
   Do not open the adjacent stock `dpad_fuli` Shell page; obtain a separately audited,
   side-effect-free, result-preserving UID1000 caller before V0, V1 or a Binder transaction.
   The independently reviewed UID1000 transaction-1 check classifies only manager liveness; it does
   not admit a `Pack`. Before any Binder GET, recover the exact live manager/callback/Parcelable ABI
   and prove native selector 3 plus retry 0 are preserved. The current adjacent-ABI tx4 artifact is
   prohibited because `maxRetryCnt` is omitted/defaults to 2 and its selector is 0. Prefer a reviewed
   in-process DJI Fly subject getter after a no-op attach canary. Do not open `40007`/`40009`,
   substitute the two failed direct-USB routes, or guess a write. A later state change still
   requires baseline/readback/restore and independent RF reception.
6. Keep the O4 FCC/CE area-code investigation separate from Remote ID profiles.
7. Keep aircraft-firmware analysis separate from receiver compatibility. The verified `0802`
   boundary and next research steps are documented in
   [DJI_RID_FIRMWARE_RESEARCH.md](DJI_RID_FIRMWARE_RESEARCH.md); firmware self-report or a patched
   local file is never a substitute for independent RF evidence.

## Sources

- [DJI MSDK V5 `IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
- [DJI MSDK V5 `IFlyZoneManager` and `RID_UNLOCK`](https://developer.dji.com/api-reference-v5/android-api/Components/IFlyZoneManager/IFlyZoneManager.html)
- [DJI Cloud API FlySafe license schema and `RID_UNLOCK` levels](https://developer.dji.com/doc/cloud-api-tutorial/en/api-reference/dock-to-cloud/mqtt/dock/dock3/flysafe.html)
- [DJI MSDK 5.18.0 release notes and supported-product list](https://developer.dji.com/doc/mobile-sdk-tutorial/en/?pbc=D3IDBfR5&pm=custom)
- [DJI MSDK V5 official sample](https://github.com/dji-sdk/Mobile-SDK-Android-V5)
- [DJI Fly official download page](https://www.dji.com/downloads/djiapp/dji-fly)
- [FAA Remote ID overview](https://www.faa.gov/uas/getting_started/remote_id)
- [14 CFR § 89.110](https://www.ecfr.gov/current/title-14/chapter-I/subchapter-F/part-89/subpart-B/section-89.110)
- [FAA Remote ID executive summary](https://www.faa.gov/sites/faa.gov/files/uas/getting_started/remote_id/RemoteID_Executive_Summary.pdf)
- [Commission Delegated Regulation (EU) 2019/945, consolidated 2025-06-24](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX%3A02019R0945-20250624)
- [EASA drone operator and remote-pilot responsibilities](https://www.easa.europa.eu/en/the-agency/faqs/responsibilities-drone-operators-and-remote-pilots-open-category)
- [Japan MLIT Direct Remote ID specification](https://www.mlit.go.jp/koku/content/001582250.pdf)
- [Japan DIPS Remote ID application guide](https://www.dips-reg.mlit.go.jp/app/page/manual_5_1_en.html)
- [China GB 46750—2025 official standard PDF](https://www.caac.gov.cn/XXGK/XXGK/BZGF/BZGF_GJBZ/202601/P020260120357575326873.pdf)
- [CAAC interpretation of GB 46750—2025](https://app.caac.gov.cn/XXGK/XXGK/ZCFBJD/202601/t20260120_229793.html)
- [UK CAA Remote ID guidance](https://www.caa.co.uk/drones/open-category/moving-on-to-more-advanced-flying/remote-id-rid/)
- [Singapore CAAS Broadcast Remote Identification Specification AS-10](https://www.caas.gov.sg/docs/default-source/default-document-library/as-10_broadcast-remote-identification.pdf)
- [Singapore CAAS implementation announcement](https://www.caas.gov.sg/resources/media-and-publication/newsroom/broadcast-remote-identification-requirement-for-unmanned-aircraft-to-come-into-e/)
- [OpenDroneID Core C](https://github.com/opendroneid/opendroneid-core-c)
- [OpenDroneID Linux transmitter](https://github.com/opendroneid/transmitter-linux)
- [OpenDroneID nRF transmitter](https://github.com/opendroneid/transmitter-nrf)
- [ArduPilot ArduRemoteID](https://github.com/ArduPilot/ArduRemoteID)
- [Recovered DJI Fly EID UI path, pinned source](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/component/fpv/widget/setting/ui/safety/remoteidentify/SettingRemoteIdSwitchViewModel.java)
- [Recovered DJI Fly internal area-code path, pinned source](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/service/areacode/AreaCodeServiceImpl.java)
- [DJI MSDK V5.18.0 `aircraft-provided` artifact](https://repo1.maven.org/maven2/com/dji/dji-sdk-v5-aircraft-provided/5.18.0/dji-sdk-v5-aircraft-provided-5.18.0.jar)
- [FindUAS receiver protocol notes](PROTOCOL.md)
- [DJI RC 2 state research](DJI_RC2_STATE_RESEARCH.md)
- [DJI RC 2 RF-power and area-code research](DJI_RC2_RF_POWER_RESEARCH.md)
