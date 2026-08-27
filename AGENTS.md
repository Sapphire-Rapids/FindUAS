# AGENTS.md

This file is the handoff contract for humans and coding agents working in this repository. It
applies to the entire repository.

## Product boundary

FindUAS is an independent macOS client for the receiver sold for FindUAS/FindUAV systems. The
Mac scans for and connects to the BLE receiver; the receiver, not the Mac, listens for aircraft
Remote ID broadcasts. This is not a direct DJI/Autel aircraft client and is not official vendor
software.

Do not add accounts, cloud telemetry, background uploads, registration-database lookups, or other
network services without an explicit product decision and privacy review.

## Repository map

- `Sources/FindUASCore/`: Apple-framework-free framing, configuration, decoding, and models.
- `Sources/FindUASMac/`: CoreBluetooth lifecycle, persistence, and SwiftUI UI.
- `Checks/`: executable regression checks; add protocol reproductions here.
- `docs/PROTOCOL.md`: recovered and hardware-validated interoperability notes.
- `docs/DJI_RC2_STATE_RESEARCH.md`: read-only DJI Fly/RC 2 Remote ID, account-state, and runtime
  flight-limit research; it is context, not a product integration contract.
- `docs/DJI_RC2_RF_POWER_RESEARCH.md`: read-only DJI Fly/RC 2 regulatory area-code and FCC/CE RF
  policy research; it is context, not a radio-modification implementation or product feature.
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

## Concurrency and state ownership

`BluetoothManager`, `AppState`, and `RecordStore` are main-actor objects. Core parsing types are
`Sendable` value types. Keep CoreBluetooth callbacks on the main queue unless the ownership model
is redesigned and tested. UI derives live targets from `AppState`; do not maintain a second,
divergent live-target cache.

## Privacy and repository hygiene

Never commit:

- real UAS IDs, receiver serial numbers, exact aircraft/operator coordinates, or phone numbers;
- raw field captures that can be linked to a person or flight;
- extracted APKs, vendor binaries, icons, sounds, model databases, or decompiled source;
- executable RF-region/power profiles, blind DUML keepalive loops, or claims that a local socket
  write proves actual EIRP changed;
- fixtures containing real aircraft identities or positions, or a test profile with executable
  country-code, radio, aircraft, receiver, or authorization writes;
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
- Name any future region control “validation profile” and state that it does not change device
  region. A replay controller must own isolated framing/session state, create evidence per decoded
  frame before merging, and never infer it from `activeTargets`. It must not publish into live
  targets, alerts, whitelist, maps, exports, or `RecordStore`.
- Never add a generic aircraft “Remote ID off” control. The recovered French EID setting, MSDK
  development area strategy, and managed `RID_UNLOCK` license path are distinct mechanisms and
  do not belong in this external-receiver client.

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
