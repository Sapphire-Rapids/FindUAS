# AGENTS.md

This file is the handoff contract for humans and coding agents working in this repository. It
applies to the entire repository.

## Product boundary

FindUAS is an independent macOS client for the receiver sold for FindUAS/FindUAV systems. The
Mac scans for and connects to the BLE receiver; the receiver, not the Mac, listens for aircraft
Remote ID broadcasts. This is not a direct DJI/Autel aircraft client and is not official vendor
software.

The **Compatibility Lab** administrator surface is a safety-preview control plane, not an aircraft
or RF control plane. Its validation profiles, staged state, lease, and audit log are local-only. The
current backend cannot transmit Remote ID, write any connected device, or change a device region.
The DJI card has a separate experimental, fixed read-only USB observer. It can issue only the
compiled GET requests described below; it is not a supported DJI control session.

Do not add accounts, cloud telemetry, background uploads, registration-database lookups, or other
network services without an explicit product decision and privacy review.

## Repository map

- `Sources/FindUASCore/`: Apple-framework-free framing, configuration, decoding, and models.
- `Sources/CDJIUSBBridge/`: dynamically loaded libusb bridge with a closed set of DJI GET requests;
  it deliberately exposes no setter, raw-frame, serial-number, or generic-command API.
- `Sources/FindUASMac/`: CoreBluetooth lifecycle, persistence, and SwiftUI UI.
- `Checks/`: executable regression checks; add protocol reproductions here.
- `docs/PROTOCOL.md`: recovered and hardware-validated interoperability notes.
- `docs/DJI_RC2_STATE_RESEARCH.md`: predominantly read-only DJI Fly/RC 2 Remote ID, account-state,
  runtime flight-limit, and explicitly bounded area/country research; it is context, not a product
  integration contract.
- `docs/DJI_RC2_RF_POWER_RESEARCH.md`: predominantly read-only DJI Fly/RC 2 regulatory area-code
  and FCC/CE RF-policy research, including separately authorized bounded state-only transactions;
  it is context, not a radio-modification implementation or product feature.
- `docs/DJI_RID_FIRMWARE_RESEARCH.md`: Assistant 2 inventory, the encrypted `wa150` trust boundary,
  verified `rc331/0205` Android OTA/platform inventory, verified-outer/protected-inner
  `rc331/0200`, current official DJI Fly native evidence, and non-flashable offline integrity work;
  it is context, never a downloader, upgrader, root guide, signature bypass, or Remote ID control.
- `docs/REMOTE_ID_COMPATIBILITY_TESTING.md`: the safety boundary, regional profiles, and phased
  design for isolated Remote ID receiver compatibility tests. It is not an aircraft-region or
  broadcast-control specification.
- `docs/ARCHITECTURE.md`: data flow, ownership, persistence, and extension seams.
- `scripts/`: local checks and clean `.app` packaging.
- `Packaging/Info.plist`: bundle identity and macOS privacy usage descriptions.

## Commands before handoff

Run both commands after any functional change:

```sh
./scripts/check.sh
./scripts/build-app.sh
```

The second command must finish with successful `plutil` and `codesign --verify` output. If SwiftPM
cannot write its default cache in a sandbox, point `CLANG_MODULE_CACHE_PATH` and the SwiftPM cache
at `.build/`; do not weaken macOS security settings.

## Protocol invariants

Preserve these behaviors unless new captured evidence proves they are wrong:

1. Compatible advertisements are `FindUAS Device` and `FindUAV Device`; aircraft advertisements
   must not be treated as receivers.
2. Service `00FF` contains FF01 telemetry and FF02 configuration. Do not write FF03: its purpose is
   unknown.
3. A BLE link is not “connected” in the UI until service discovery confirms FF01.
4. Legacy frames are balanced UTF-8 JSON. V2 is `08 17 30 LL HH + JSON + 3F 55`, with a little-
   endian length that includes the two trailer bytes.
5. Swift `Data` indices need not restart at zero after prefix removal. Always index relative to
   `startIndex`; this previously caused a live FF01 crash.
6. Target freshness uses local receive time. Payload timestamps may be Unix time, uptime, zero, or
   seconds after a UTC hour and must not expire a newly received target.
7. Firmware sentinel values `0,0`, `-1000 m`, and `361°` mean unavailable. Normalize them before
   map display or persistence.
8. Observed V2 frames place `RID_Standard` and `Reg` under `UAVInfo`; retain flat fallbacks for
   older firmware.
9. Phone numbers are not standard Remote ID elements. Display only an explicit proprietary field;
   never infer one from UAS ID or query a private registration service.
10. Configuration writes use FF02 with response, validate ranges, and require a visible user
    confirmation.
11. FF01 Legacy/V2 is only the receiver-to-Mac wrapper. Do not label it as an ASTM, EU, Japan, or
    China protocol selector.
12. A compatibility-test region is read-only validation metadata. It must never trigger FF02,
    FF03, DUML, country-code, channel-plan, RF-power, aircraft, or account writes.
13. `RIDLabSourceCapability.noRFBackend` is the fail-closed default. A UI state transition must
   never be treated as evidence that a packet was transmitted or received over RF.
14. The lab session may enter `activeDryRun` only after all five checklist items pass and the lease is
   between 5 and 15 minutes. Stop and lease expiry return to `complianceAuto`; `lockout` requires an
   explicit reset. Do not persist or automatically restore an armed/staged/active state.
15. The DJI USB bridge is read-only and fixed: FC area GET is `0x03/0xAF`, Sky/Ground country GET is
    `0x07/0x19`, and France EID GET is `0x03/0x77` with payload `0x02`. Do not add a generic DUML
    entry point or setter to this target.
16. A matching DJI reply must pass declared length/version, CRC8/CRC16, reverse route, sequence,
    command set/id, and payload validation. Current valid replies use command type `0x80`.
17. Current country GET replies are four bytes: zero prefix, two uppercase country bytes, zero
    reserved tail. Longer reserved tails are acceptable only when every extra byte is zero.
18. France EID is queried by the app only when FC area has independently read back `FR`. A timeout,
    short/mismatched reply, unsupported product, or missing capability is `unavailable`, never OFF.
    French EID is not a generic FAA/EU/JP/CN Remote ID switch.
19. FC, Sky, Ground, and RC/DJI Fly policy are separate region surfaces. Never infer the unknown RC
    surface or a complete region change from one or three USB values.
20. `RidWorkingStatusPush` is a read-only status source on `0x11/0x1C`, not a setter. The current
    native handler consumes exactly seven raw bytes: a little-endian flag word, a four-byte area
    value, and one failure byte. Until one Mini 5 Pro frame is captured, keep command type and
    sender/receiver open and fail closed; never persist raw RID status payloads or infer RF
    transmission from an onboard `normal` bit alone.
21. FlySafe `RID_UNLOCK` is a signed, account/FC-bound license, not a local configuration bit.
    The completed legacy work-only probe reported only count, enabled/valid, type, and level and
    discarded raw payloads, license IDs, descriptions, times, coordinates, account/device
    identifiers, and serials. Its hand-built one-byte `0x11/0x11` request timed out and must not be
    resent unchanged; that timeout proves neither an empty inventory nor lack of V2 support. Any
    later read-only query must first establish support/version and the exact current session and
    route; only a proven V2 session may use its one-byte index. Never add upload `0x11/0x10` or
    enable-state `0x11/0x12` to the app, and never forge, modify, replay, or upload a license. A
    later work-only state experiment requires a genuine type-6 record, exact pre/post readback,
    bounded rollback, and independent motor-on RF observation.
22. MSDK 5.18's current native map directly resolves query `PackType 0x38` to tuple
    `11 11 00 01`: cmdset `0x11`, cmdid `0x11`, unknown third tuple byte `0`, and ACK-result-byte
    separation enabled. V2 requests one-byte indexes. V3/V4 first send `00 01`, then page with
    `00 (index << 1)`; they parse a group protobuf followed by status-byte-plus-license-protobuf
    records. Do not feed modern group bytes to the legacy record parser, bypass the support/version
    gates, or improvise receiver routes, product/device tokens, or raw frames.
23. MSDK 5.18's current pull path is FC serial -> `queryFCLicensesJni` ->
    `native_QueryLicenseFromFC(productId, deviceId)` -> `ModuleMediator::QueryLicenseFromFC`, and
    it returns a whole `FlysafeLicenseGroup` that can contain RID licenses. The current native
    set-enable map independently resolves `PackType 0x39` to tuple `11 12 00 01`; V2 uses a six-byte
    license-id/boolean payload and V3/V4 use a seven-byte version-specific payload. This is static schema
    evidence, not live acceptance or proof that changing any license changes RF. Current DJI Fly
    1.21.10 proves only that generic license UI/JNI symbols are packaged, not a type-6 RID UI or
    entitlement. The executable 1.21.4 prior version recognizes only types 0--4/255 and can
    mis-handle type 6; never use that generic UI label/switch as proof of RID semantics.
24. Current DJI Fly 1.21.10 initializes FlySafe unlock version to unknown and support to false, then
    populates them from registered area/version and whitelist/support pushes. A passive dual USB
    window saw neither push even though it validated ordinary aircraft and RC 2 frames. Absence is
    unknown, not unsupported. Do not substitute the initial cache values, blind-scan receiver
    addresses, or send a query until the current session yields both gates and one exact route.
25. The WA150 nonflashable patch experiment can recompute payload SHA-256 and `encr_cksum` after a
    ciphertext byte change, but current evidence cannot correctly determine or validate the
    modified `plain_cksum`, and the repaired header changes the RSA-PSS-signed message while
    retaining the old signature. Public checksum repair is not a signature/decryption bypass.
    Never retain, distribute, transfer, or flash that temporary output.
26. DJI's current public FlySafe front end has qualified Mainland and overseas RID application
    forms, but product eligibility is a server response: `support_unlock_type` must contain `Rid`,
    and the request binds product plus FC serial. No public evidence closes Mini 5 Pro/WA150
    issuance and FC acceptance. Never bypass account qualification, misstate EU label status,
    forge a license, or treat the existence of the form as product support.
27. The full `01.00.0600`/`01.00.0700` `0802` ciphertext comparison found distinct wrapped
    scramble values, no equal aligned 16/32-byte payload blocks, and random-like XOR statistics.
    The five local STUE samples all have unique wrapped values. Do not repeat cross-version XOR,
    crib, or offset scans as though they were a plaintext route unless new evidence first shows
    identical content key/counter reuse.

## Concurrency and state ownership

`BluetoothManager`, `AppState`, `RecordStore`, and `DJIUSBReadOnlyMonitor` are main-actor objects.
The monitor runs the blocking fixed GET capture in a detached, nonisolated worker and publishes only
`Sendable` value snapshots back on the main actor. Core parsing types are `Sendable` value types.
Keep CoreBluetooth callbacks on the main queue unless the ownership model is redesigned and tested.
UI derives live targets from `AppState`; do not maintain a second, divergent live-target cache.

## Compatibility Lab safety contract

`RIDLabProfile`, `RIDLabBroadcastIntent`, `RIDLabChecklistItem`, `RIDLabPhase`, and `RIDLabSession`
are pure control-plane models. The allowed phase sequence is:

```text
complianceAuto -> precheck -> staged -> activeDryRun -> rollback -> complianceAuto
                         \---------------- failure ----------------> lockout
```

The current UI may stage a rehearsal, start a local dry run, stop/roll back, and explicitly refresh
the fixed DJI USB read-only snapshot. There is deliberately no generic Remote ID switch; the
France-only EID surface is GET-only; region writes are not implemented in the app. The receiver card
exposes only read-only application/session diagnostics.
On 2026-08-27 macOS could enumerate that aircraft/controller pair over USB, but DJI's MSDK 5.18.0
supported-product list did not include the pair. USB enumeration is not a supported SDK session and
does not authorize guessed private writes.

The verified read-only snapshot on that date was FC=`CN`, Sky=`CN`, Ground=`CN`, RC policy unknown.
The France EID GET was unavailable on the CN product state. Never render unavailable as disabled.
The bridge identifies only the observed VID/PID routes, opens the first match, and reads no USB
strings or serial numbers. It does not bind a stable aircraft/controller pair and must never be used
as a write-authorization identity.
The separate research harness proved FC and Sky `CN -> US -> CN` readback/restore loops. A separately
authorized Ground US request transmitted once but produced no strictly matching ACK; the immediate
and two final independent GETs remained CN, so no restore write or forward retry was sent. Treat
Ground SET as unverified, not successful and not universally unsupported. No writer transport
belongs in the app yet. The external one-shot harness is now locked after consuming that
authorization; do not rerun or reconstruct it without new, surface-specific authorization. Before
any future writer is enabled, require fixed aircraft+controller
session binding, cross-process transaction exclusion, a durable recovery journal, independent
readback after every step, a non-cancellable bounded rollback, and explicit authorization for every
surface being written.

`DJIRegionLab.swift` is non-executable scaffolding only: allow-list values, snapshots, a redacted
journal value, and reconciliation classification. The repository intentionally has no journal
store, transaction coordinator, writer transport, or UI writer. Do not describe these models as an
implemented transaction capability.

The five required checks are controlled test area, regulatory/site authorization, synthetic test
identity, independent receiver readiness, and emergency-stop/rollback readiness. The
`silent`/`broadcast` intent is an inert description of a future source scenario while the backend
is `noRFBackend`; it must never be relabelled as an aircraft or RF switch.

Audit events must be typed, bounded, memory-only records of phase/profile/broadcast-intent/checklist/
lease changes. Never add free-form payloads, device identifiers, UAS/operator identities,
coordinates, credentials, or secrets to this log.

A future external test-source adapter must remain disabled unless it passes all of these gates:

1. explicit hardware identity and capability handshake;
2. a physical RF interlock or a documented shielded/conducted laboratory setup;
3. the same complete checklist, short lease, immediate stop, timeout, rollback, and lockout rules;
4. independent RF observation proving what was actually emitted;
5. synthetic identities and authorization for the selected test jurisdiction and transport.

Candidate implementations such as OpenDroneID Linux, nRF, or ESP/ArduRemoteID are starting points,
not trusted backends. Validate their packet encoding, transport, cadence, and RF behavior before
enabling an adapter. Never fall back from a failed handshake to a private DJI, country-code, radio,
or receiver write.

## Firmware-research boundary

Firmware research artifacts stay outside this repository. Keep official originals read-only and
separate from working copies. Record product, package, module, size, official MD5, and local SHA-256
before analysis. Never place a modified copy in Assistant's cache or next to an installable package
manifest.

Treat Assistant metadata/download, device transfer, and upgrade as separate boundaries.
`upgrade_firm_pack` invokes a combined download/transfer/upgrade workflow and must not be used as a
"download, then interrupt" technique. No Assistant, USB, DUML, transfer, or upgrade call belongs in
repository code for firmware research.

For IMaH or Android OTA material, run info/verify first. An unknown key, unsupported container, or
signature failure is `unsupported`; do not use force extraction and then describe the output as
verified plaintext. Do not repair a manifest, recalculate install checksums, re-sign, repack, or
produce a flashable image. A deliberately corrupted integrity sample must be clearly named
`nonflashable`, remain outside the repository and vendor cache, and document exactly which checks
failed.

Parser support, availability of the matching authentication key, and availability of a content-
decryption key are separate facts. Public tooling supports IMaH v2 and 384-byte/3072-bit RSA/PSS;
the current `wa150` blocker is missing target-matching PRAK and STUE material, not a new unsupported
container format. Forced processing of an encrypted chunk is still encrypted/unverified data.

The work-only `imah_nonflashable_patch_probe.py` deliberately proves only that payload SHA-256 and
`encr_cksum` can be brought back into public-field consistency after one ciphertext-byte change.
It preserves the not-independently-validated `plain_cksum` and original signature even though the
signed header changes, refuses `original/` and FindUAS repository destinations, and rejects
alternate parser modules. It marks output nonflashable/read-only; the full-size experiment's caller
used `TemporaryDirectory`, which removed that output after verification. With its pinned parser it
implements no sign/transfer/flash interface. Do not copy this tool or its vendor inputs into the MIT
repository, relax its guards, add manifest repair/sign/transfer/flash behavior, or describe its
output as a safe firmware candidate or a proven loader rejection.

The package-identical `wa150/0806` module has now been independently downloaded and audited as
IMaH type `DONG`; RC 2's official configuration identifies peer host `0x0806` as LTE. It is another
PRAK/STUE-protected module and not a plaintext RID route. `1200` is the ESC/motor-controller family;
motor start can gate RID without placing RID encoding there. Keep `0802/E3` as the primary firmware
candidate. Do not transplant the Mini 2-era S1/Sparrow unsigned-SDRH bypass to WA150/Sparrow2: no
current module, loader, or configuration has shown an SDRH/equivalent unsigned post-verify patch
path.

The retail Assistant's WA150 log/data-export path is a device-exposed, mode-gated diagnostic
FTP/file surface, not an `0802` partition or plaintext-firmware readback path. Its front-end
`/esc/config/ReadFlashData` route has no discovered WA150 native handler or `0802` binding. Do not
label either as firmware readback, browse arbitrary device paths, or switch a live device into
export mode without a separate test authorization.

RC 2's Sparrow2 is the ground-side `SPARROW_GND`/`1400` radio. `dji_sdrs_agent` orchestrates
`brload` and fixed fastboot writes; it is not a decrypt/sign oracle and its WA150 variant is not an
aircraft `0802` plaintext copy. Never run `brload`, `fastboot flash`, `cmpu_*`, OTP, production, or
unknown staged-upload scripts for discovery. A secure-debug gate exists, but no current evidence
shows that a retail controller or aircraft can enter or pass that state. No unsigned runtime-patch
descriptor or safe decrypted-aircraft readback was found, and some manufacturing writes may be
irreversible.

Official `rc331/10.00.0700/0205` passed its public outer signature and chunk checksums without force
and may be used for offline filesystem analysis only. It is the Android/Qualcomm base-system OTA,
not the matching DJI Fly module. All extracted partitions, APKs, platform apps, and binaries remain
outside this repository.

Official `rc331/10.00.0700/0200` also passed its outer PRAK signature and checksum verification
without force. Its inner `flyapp`/FLYA is a separate PRAK/TBIE object: all tested public key
variants fail inner signature or plaintext checksum. Do not repeat the sweep, use force output as
plaintext, or imply that root supplies the missing key.

The current official DJI Fly phone APK and targeted native entries are work-only research inputs.
Repository documentation may retain version, hashes, key/parameter names, and independently
recovered behavior, but never the APK, library, decompiled source, signing certificate, download
helper, CDN URL/query, or vendor bytes. It is same-generation evidence, not proof of the exact live
RC 2 package.

For the recovered RID policy parameters, FLYC `0x03/0xF7` is metadata GET, `0x03/0xF8` is value
GET, `0x03/0xF9` is write, and `0x03/0xFA` is reset. Keep `0xD7757AD2` and `0xF80992FE`
observation-only. A read-only probe must be hard-allow-listed to F7/F8 and those hashes. The live
Mini 5 Pro returned only the one-byte F7 payload `0x03` for both candidates over direct and
RC-routed plaintext paths, while known height/distance parameters succeeded on the same RC route;
legacy SIMPLE encryption produced no matching response. Treat both candidates as unavailable on
the live FC metadata surface, do not send F8 or F9 for them, and do not assign an exact enum name
to `0x03` without new evidence. DJI Fly's UAV139/wa150 abstraction dynamically registers both
mappings; that application-side registration does not override the endpoint's missing metadata or
prove a parameter is enabled. A `LIBUSB_ERROR_ACCESS`/claim failure while Assistant is active
still means no request was sent. Never add F9, FA, a generic hash reader, or a guessed value width
to product code.

Public F8 response layouts conflict even within the pinned prior art: `dji-firmware-tools` plus
DJI-Link's runtime parser/RTH notes use `[status][hash][value]`, while DJI-Link's `PARAM_WIRE.md`
uses `[hash][value]`. Current DJI Fly 1.21.10 native code resolves its own callback as
`[batch_status][hash][value:cached_size]...`; value size/type come from cached FC metadata. Require
that exact layout for this build plus route, sequence, requested hash, known metadata, total length,
and an exact final cursor. Treat an offset-zero hash layout as a separately identified legacy
variant only; never auto-select it merely because one parser returns a plausible Boolean.

The public-prior-art audit found neither a fully reproducible no-root base/split export for this
exact RC331 build nor a successful plaintext recovery of its exact `10.00.0700/0200` FLYA. Android
public APK paths, older emulator recovery, and committed community DEX files are research routes,
not proof of live-package parity and not justification for root or bootloader unlock.

The analysed adjacent OTA contains `com.dpad.fuli` with Android system UID. System UID is not root,
and adjacent-package presence is not live-device proof. Do not launch its updater/recovery, Type-C,
FTM, SDR, MCU, log-toggle, or other factory-test functions for exploration.

Do not infer an open root shell from `ro.debuggable=1` or `ro.adb.secure=0`: the analysed DJI
`adbd` replaces the ordinary decision with a production/user-lock gate. Device activation/crypto
state is also distinct from DJI user-account login.

Do not unlock the bootloader, root/Magisk-patch, modify boot, flash, enable ADB, authorize a
persistent ADB key, or execute device shell commands without a new, action-specific authorization
and a bounded recovery procedure. Never read, reuse, or publish an existing/private `.adbkey` or
device authorization record. Any future authorized ADB test must generate a disposable key in an
isolated temporary directory and document its removal.

The installed Assistant `app.asar` has abnormal entries: whole-archive extraction once produced
about 153 GiB of invalid temporary files. Use targeted reads or validate entry offsets and lengths
before extracting. Do not repeat whole-archive extraction.

## Privacy and repository hygiene

Never commit:

- real UAS IDs, receiver serial numbers, exact aircraft/operator coordinates, or phone numbers;
- raw field captures that can be linked to a person or flight;
- extracted APKs, vendor binaries, icons, sounds, model databases, or decompiled source;
- executable RF-region/power profiles, blind DUML keepalive loops, or claims that a local socket
  write proves actual EIRP changed;
- fixtures containing real aircraft identities or positions, or a test profile with executable
  country-code, radio, aircraft, receiver, or authorization writes;
- laboratory audit logs containing free text, raw packets, identifiers, coordinates, registration
  material, account tokens, or private operator-ID suffixes;
- DJI firmware, modified firmware, decrypted partitions, module configs, Assistant static material,
  request-authentication material, account/session values, or temporary signed download links;
- ADB private/public key pairs, device authorization records, or exported Android package material;
- `.build/`, `dist/`, app bundles, crash reports, or local JSONL history.

Tests must use obviously synthetic identifiers and coordinates. Protocol issue templates require
redaction. A public Release asset must be produced only from the clean `dist/FindUAS.app` generated
by `scripts/build-app.sh`.

## UI and compatibility conventions

- User-facing UI is Simplified Chinese; identifiers and protocol keys remain as transmitted.
- Missing or invalid measurements display as `—`, never as fabricated zeroes.
- Clearly distinguish “Mac scanning for the receiver” from “receiver monitoring aircraft.”
- Keep `CFBundleIdentifier` stable so macOS permissions and local history survive updates.
- The package minimum is macOS 14 and Swift tools 6.0. Keep `FindUASCore` free of AppKit,
  CoreBluetooth, SwiftUI, and MapKit so it can seed a future Windows implementation.
- The optional DJI observer dynamically loads `libusb-1.0`. A missing runtime must degrade to an
  explicit unavailable state without affecting the receiver client. Release notes must say whether
  libusb is bundled or must be installed separately.
- Name the lab selector “validation profile” and state that it does not change device region. Keep
  the fixed warning “不发射无线电 · 不写飞机 / 遥控器 / 接收器” visible
  whenever the lab is open. A replay controller must own isolated framing/session state, create
  evidence per decoded frame before merging, and never infer it from `activeTargets`. It must not
  publish into live
  targets, alerts, whitelist, maps, exports, or `RecordStore`.
- Never add a generic aircraft “Remote ID off” control. The recovered French EID GET may remain as
  narrowly labelled experimental read-only status, but no EID setter belongs in the app. MSDK
  development area strategy and managed `RID_UNLOCK` are separate mechanisms, not local toggles.

## Adding protocol support

1. Reduce the observation to the smallest redacted byte/JSON fixture.
2. Add a failing check in `Checks/main.swift`.
3. Change the assembler/decoder/model in `FindUASCore`.
4. Verify merge behavior and history decoding when fields are added.
5. Add UI only after the core representation is stable.
6. Update `docs/PROTOCOL.md`, `CHANGELOG.md`, and README support tables.
7. Run checks and a full signed build. For BLE lifecycle or frame changes, validate on hardware.

## Release checklist

1. Confirm README, `CHANGELOG.md`, protocol notes, version, and compatibility statements.
2. Run checks and the Release build.
3. Inspect the app bundle and ZIP listing for vendor assets and private data.
4. Verify the app signature, calculate SHA-256, then create the GitHub Release.
5. State architecture and signing/notarization limitations in release notes.
