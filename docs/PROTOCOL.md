# FindUAS Device BLE interoperability notes

This is an independently produced interoperability description for receivers associated with
[FindUAS](https://finduas.com). It is not an official specification.

## Compatible receiver identity

Known advertising names:

- `FindUAS Device`
- `FindUAV Device`

The receiver exposes the following custom GATT layout:

| Purpose | UUID | Observed properties |
| --- | --- | --- |
| Primary service | `00FF` | Primary service |
| Remote ID telemetry | `FF01` | Read, write, notify |
| Receiver configuration | `FF02` | Read, write, notify |
| Unknown | `FF03` | Write |

This client subscribes to FF01 and FF02. It deliberately does not write FF03 because its purpose
has not been established.

## Transport modes

### Legacy

Legacy messages are bare UTF-8 JSON objects. There is no length prefix or checksum. A receiver
must balance the outer `{` and `}` while respecting JSON string quoting and backslash escapes.

### V2

```text
08 17 30 LL HH [UTF-8 JSON payload] 3F 55
```

- `LL HH` is a 16-bit little-endian length.
- The length is `payload byte count + 2`; the two trailer bytes are included.
- The total frame size is `5 + length`.
- Trailer: `3F 55`.
- No CRC/checksum was observed.
- The recovered Android parser limits the JSON payload to 4096 bytes.

Saved protocol values in the Android client were `0 = automatic`, `1 = legacy`, and `2 = v2`.

These values select only the FF01 receiver-to-client wrapper. They do not select an ASTM,
ASD-STAN, Japanese, Chinese, or other over-the-air Remote ID protocol. No receiver country,
jurisdiction, or Remote ID standard-selection field has been recovered.

## FF02 configuration

The write payload uses these exact JSON keys:

```json
{
  "channel": [1, 6, 11],
  "channelStayTime": 250,
  "vibrate": true,
  "sound": true,
  "flashLight": false
}
```

Receiver reports may additionally contain `batteryPercent`, `support5GChannel`, or
`channelNumbers`. One real receiver repeatedly reported the following 106-byte Legacy message:

```json
{"sound":true,"flashLight":true,"vibrate":false,"channelStayTime":2,"batteryPercent":82,"channel":[6,149]}
```

Channel selection controls receiver scanning behavior; it is not evidence that a regional Remote
ID profile or BLE/Wi-Fi air protocol changed. The separate compatibility-test design is documented
in [`REMOTE_ID_COMPATIBILITY_TESTING.md`](REMOTE_ID_COMPATIBILITY_TESTING.md).

## FF01 telemetry

Observed/recovered payloads may be flat or grouped under `MonitorInfo`, `UAVInfo`, `OperatorInfo`,
and `GPS`. The tolerant field mapping is implemented in
`Sources/FindUASCore/TelemetryDecoder.swift`.

The recovered Android 1.4.4 parser recognizes the following grouped fields:

| JSON object | Recovered fields |
| --- | --- |
| `MonitorInfo` | `Name` / `MonitorName`, `SN` / `MonitorUUID`, `Temp`, `Ch` |
| `UAVInfo` | `RID_Standard`, `Reg`, `ID`, `Type`, `ID_Type`, `Lat`, `Lon`, `Height`, `AltGeo`, `AltBaro`, `H_Speed`, `V_Speed`, `Trk`, `Sta`, `T_Stamp` |
| `OperatorInfo` | `Lat`, `Lon`, `Operator Height` |
| `GPS` / `GPSInfo` | `Fix_Type`, `HDOP`, `Spkm`, `Spkn`, `Utc_Time`, `Utc_Date`, `NSat` |

`RID_Standard` and `Reg` belong to `UAVInfo` in observed V2 frames. Flat root-level fallbacks are
accepted for older firmware. The macOS model additionally has forward-compatible fields for the
operation category, aircraft category, control-station location type, coordinate system, position/
speed/time accuracy, and emergency status defined by current Remote ID schemes.

A phone number is not a standard Remote ID message element. No phone parser key was found in the
recovered Android client. The macOS decoder recognizes a narrowly scoped set of explicit phone keys
only in case receiver firmware supplies a proprietary extension; it does not derive a phone number
from the UAS ID or registration ID.

An idle receiver has been observed sending a short counter-like byte sequence followed by blocks
of 516 zero bytes on FF01. Those are synchronization/idle data rather than JSON telemetry and are
discarded by the automatic frame assembler.

A live aircraft was also observed producing approximately 358-byte V2 frames. The payload used
the grouped `MonitorInfo` / `UAVInfo` layout and identified the Remote ID standard as
`GB42590-2023`. The macOS client continuously assembled and decoded those frames without rejects.
The live aircraft identifier and coordinates are intentionally not retained in this repository.

Observed firmware also uses protocol sentinel values when a measurement is unavailable: the
coordinate pair `0, 0`, altitude `-1000`, and track angle `361`. The core model normalizes those
values to absent data before publishing them to the map, history, or detail view.

## Standards context

The current Chinese operational-identification standard is
[GB 46750—2025](https://www.caac.gov.cn/XXGK/XXGK/BZGF/BZGF_GJBZ/202601/t20260120_229783.html),
effective 2026-05-01. Its data set includes aircraft identification/registration state, aircraft
and control-station positions, course, speed, height/altitude, operating state, coordinate system,
accuracy, and time. CAAC's
[official interpretation](https://www.caac.gov.cn/XXGK/XXGK/ZCJD/202601/t20260120_229793.html)
states that this information does not include a user's name, phone number, or address.

Some observed receiver firmware reports `GB42590-2023` as its `RID_Standard` value. That string is
preserved as device data. The official title of
[GB 42590—2023](https://openstd.samr.gov.cn/bzgk/gb/newGbInfo?hcno=0DC41035BA23EF2C5B94E6482492AF1E)
is the civil-UAS system safety-requirements standard, not the newer operational-identification
standard.

## Research basis and limits

The frame formats and field aliases were recovered for interoperability from FindUAS Android
1.4.4, then the GATT layout, FF02 Legacy data, idle FF01 behavior, and live non-empty FF01 V2
telemetry were checked against a real receiver. No vendor code or APK is distributed in this
repository.
