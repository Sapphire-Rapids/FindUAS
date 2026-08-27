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
- `docs/DJI_RID_FIRMWARE_RESEARCH.md`: Assistant 2 inventory, `wa150` module-role evidence, IMaH
  trust boundaries, and a non-flashable offline integrity experiment; it is context, not a firmware
  downloader, upgrader, signature bypass, or Remote ID control implementation.
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
