# Architecture

## Data flow

```text
FindUAS / FindUAV receiver
        │ CoreBluetooth notifications
        ▼
BluetoothManager (main actor)
        │ FF01 bytes                    │ FF02 bytes
        ▼                               ▼
TelemetrySession                 BLEFrameAssembler
        │                               │
BLEFrameAssembler                DeviceConfiguration.decode
        │ complete JSON frames
        ▼
TelemetryDecoder
        │ normalized DroneTelemetry values
        ▼
AppState ───────────────► SwiftUI live table and map
        │
        └───────────────► RecordStore ─► local telemetry.jsonl
```

## Targets

`FindUASCore` is a pure Swift library with no Apple UI or Bluetooth imports. It owns framing,
configuration JSON, telemetry decoding, sentinel normalization, target merging, and expiry. This is
the portability boundary for a future Windows/WinRT client.

`FindUASMac` owns CoreBluetooth, main-actor application state, JSONL persistence, MapKit, and SwiftUI.
The UI never parses raw packets.

`CDJIUSBBridge` is a C target with four compiled DJI GET operations and dynamic libusb loading. It
has no generic-command or write API. `DJIRegionLab.swift` contains only non-executable allow-list,
snapshot, journal-value, and reconciliation models for tests and future design work; there is no
journal store, transaction coordinator, writer transport, or UI writer in the current build.
The product-139 France-EID request uses the recovered static default target `0x92` and body `[02]`;
its response validator alone accepts the clear closed set `{0x80,0xC0}` and requires the exact
two-byte successful body before applying the official `state & 1` interpretation.

`FindUASCoreChecks` is an executable check target rather than XCTest so contributors can run the
same regression suite with a minimal Swift toolchain.

## BLE lifecycle

The central scans without a service filter because observed receivers advertise by local name and
do not consistently expose their custom service in advertisements. Only compatible names get a
connection button. After connecting, the client discovers service `00FF`, subscribes to readable/
notifiable characteristics, and reports “connected” only after FF01 is present.

On disconnect, characteristic references and device configuration are cleared. Live target state
is reset for a new connection, while persisted history remains local.

## Framing and decoding

`BLEFrameAssembler` accepts split, concatenated, and noise-prefixed frames. Automatic mode selects
V2 from its binary header and otherwise balances Legacy JSON braces while respecting strings and
escapes. `TelemetrySession` owns one assembler and merges decoded targets by UAS ID.

`TelemetryDecoder` accepts flat and grouped firmware layouts with conservative aliases. It keeps
payload event time separate from local receive time. `DroneTelemetry` normalizes unavailable
protocol sentinels so every consumer—table, map, history, and future platforms—gets the same values.

## Persistence and privacy

`RecordStore` appends the complete encoded `DroneTelemetry` at most once every two seconds per UAS
ID and merges records when loading. The file lives under
`Application Support/FindUASMac/telemetry.jsonl`; it can contain UAS/registration and receiver IDs,
proprietary phone data, aircraft/operator coordinates, and other telemetry. It is not encrypted,
rotated, or automatically expired. Whitelisted UAS IDs are separately persisted in `UserDefaults`.
There is intentionally no network client or cloud synchronization.

## Compatibility Lab control plane

The administrator safety-preview path is intentionally separate from the live telemetry path:

```text
Compatibility Lab SwiftUI
        │ profile / inert broadcast intent / checklist / lease / local actions
        ▼
RIDLabSession (FindUASCore)
        │
        ├─ RIDLabSourceCapability.noRFBackend
        │      supportsDryRun = true
        │      canTransmitRemoteID = false
        │      canWriteDevice = false
        │      canChangeDeviceRegion = false
        │
        └─ bounded typed audit events (memory only)

        ╳ BluetoothManager / device writes / network / RecordStore / RF transmitter

RIDConfigurationCatalog (FindUASCore)
        └─ display-only truth labels; canWriteDevice = false for every entry
```

`RIDLabSession` owns the selected `RIDLabProfile`, an inert `RIDLabBroadcastIntent`, a 5–15 minute
lease, five checklist states, expiration, and audit events. The intent records whether a future
source scenario asks for silence or broadcast; it does not transmit or change a device. The
fail-closed phase sequence is
`complianceAuto -> precheck -> staged -> activeDryRun -> rollback -> complianceAuto`; a failure can
enter `lockout`, which requires an explicit reset. Stop and expiration always return to
`complianceAuto`, and the application does not persist or restore an armed state.

The lab's DJI Mini 5 Pro / DJI RC 2 write controls remain locked because macOS USB enumeration does
not establish a supported DJI MSDK session. The same card has an independent fixed read-only path:

```text
AdminLabView -> DJIUSBReadOnlyMonitor (main actor)
                         │ detached fixed-query capture
                         ▼
                  CDJIUSBBridge -> dynamically loaded libusb
                         │
                         ├─ aircraft presence + FC area + Sky country
                         ├─ controller presence + Ground country
                         └─ France EID status only after FC independently reads FR
```

`CDJIUSBBridge` exposes no raw frame, serial number, generic command, or setter. It validates the
complete response envelope and returns normalized values or a typed unavailable error. The app
never converts unavailable EID to OFF and never derives the unknown RC/DJI Fly policy surface from
FC/Sky/Ground. The receiver card remains separate and reads application/session state only:
connection, live-target and FF01/assembled/decoded/rejected counts, and the detected FF01 wrapper.

`RIDConfigurationCatalog` adds no transport. It is a curated display subset that distinguishes live read-only, passive,
static-locked, managed, opaque, legacy, and separate synthetic-source surfaces so the UI does not
render unavailable research as a working toggle; its scope text records intentionally excluded
app-cloud, opaque-quality, and name-only debug surfaces. Detailed evidence remains canonical in
[DJI-RC2-Mini5Pro-Research](https://github.com/Sapphire-Rapids/DJI-RC2-Mini5Pro-Research).

The bridge identifies only the observed DJI VID/PID routes and opens the first match. It does not
read USB strings or bind a stable aircraft/controller pair, so this identity level is suitable only
for read-only diagnostics. `scripts/build-app.sh` currently does not bundle libusb; the observer
requires a compatible external `libusb-1.0` at runtime and otherwise fails closed as unavailable.

### Future controlled-source adapter

A real laboratory source belongs behind a new capability-gated adapter, never behind
`BluetoothManager` or a validation profile. OpenDroneID Linux/nRF or ESP/ArduRemoteID can be
evaluated as implementation starting points, but the adapter must fail closed unless it verifies a
known hardware identity, declared transports, packet encoder version, physical RF interlock, and
independent RF observation. It must retain the checklist, short lease, immediate stop, timeout,
rollback, and lockout guarantees. Emission belongs in a shielded/conducted or explicitly authorized
test environment using synthetic identities.

No adapter may translate a profile selection into a DJI private command, aircraft country-code,
channel plan, transmit-power change, receiver FF02/FF03 write, or account/license operation.

## Extension seams

- Add field aliases and normalized values in `FindUASCore`, not in views.
- Add another transport by feeding complete receiver notification bytes into `TelemetrySession`.
- Keep `RIDLabSession` as the UI-independent safety state machine. A future source adapter must
  declare capabilities explicitly; `noRFBackend` remains the default and must never silently fall
  back to device writes.
- Compatibility replay must use separate framing/session state and a result publisher. Produce
  per-frame validation evidence immediately after decode and before any target merge; never infer
  evidence from `activeTargets`. It must not enter `BluetoothManager`, live `AppState`, alerts,
  whitelist, maps, exports, or `RecordStore`. Region profiles are validator metadata only; see
  [`REMOTE_ID_COMPATIBILITY_TESTING.md`](REMOTE_ID_COMPATIBILITY_TESTING.md).
- A Windows client should reimplement discovery/connection and UI while reusing or porting the core
  framing fixtures and model semantics.
- Reverse geocoding, identity enrichment, and private database access are out of scope by default.
