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

`RecordStore` appends JSON lines at most once every two seconds per UAS ID and merges records when
loading. The file lives under `Application Support/FindUASMac/telemetry.jsonl`; it is not encrypted.
There is intentionally no network client or cloud synchronization.

## Extension seams

- Add field aliases and normalized values in `FindUASCore`, not in views.
- Add another transport by feeding complete receiver notification bytes into `TelemetrySession`.
- Compatibility replay must use separate framing/session state and a result publisher. Produce
  per-frame validation evidence immediately after decode and before any target merge; never infer
  evidence from `activeTargets`. It must not enter `BluetoothManager`, live `AppState`, alerts,
  whitelist, maps, exports, or `RecordStore`. Region profiles are validator metadata only; see
  [`REMOTE_ID_COMPATIBILITY_TESTING.md`](REMOTE_ID_COMPATIBILITY_TESTING.md).
- A Windows client should reimplement discovery/connection and UI while reusing or porting the core
  framing fixtures and model semantics.
- Reverse geocoding, identity enrichment, and private database access are out of scope by default.
