# DJI RC 2 / O4 regulatory RF-power research

This note records predominantly read-only research into the feature commonly called “FAA mode” in DJI
communities. The accurate term is **FCC regulatory mode**: the FAA regulates flight operations,
while DJI's own radio specifications distinguish FCC, CE, SRRC, and MIC limits.

This is research context, not a radio-power modification guide. Explicitly authorized bounded
experiments closed FC-area and Sky-country `CN -> US -> CN` loops. A single Ground US request had no
matching ACK and the following GET remained CN, so the harness sent neither a restore SET nor a
retry. Two final
independent probes reported FC/Sky/Ground all CN. None of these experiments changed or measured an
SDR power selector, channels, account state, flight limits, motors, Remote ID, or actual RF output.

## Result in one paragraph

The modern DJI Fly path is an area-code policy pipeline, not a single transmit-power integer. DJI
Fly combines aircraft/controller or phone GNSS, MCC, IP, nearby-city, and cached inputs; publishes
the selected code to the sky and ground Airlink keys; mirrors it to Wi-Fi on applicable products;
and synchronizes a flight-controller area-code key. Native key-value code and the radio firmware
then select downstream regulatory behavior. Community RC 2 tools bypass the policy layer
and replay DUML traffic through the controller's loopback proxy. Confirmed state writes and
candidate components of that bypass include a country-code update, a flight-controller area-code
update, and the legacy Sky SDR selector that DJI code literally calls `setForceFcc()`. The popular
full profile and two-second keepalive contain unrelated or unidentified commands and are not a
validated minimal protocol.

## What a regulatory-mode change can affect

DJI's RC 2 specification lists these O4 video-transmission EIRP ceilings:

| Band | FCC | CE | Ceiling delta |
| --- | ---: | ---: | ---: |
| 2.4 GHz | `<33 dBm` | `<20 dBm` | up to 13 dB, about 20× EIRP |
| 5.1 GHz | not listed | `<23 dBm` | not comparable |
| 5.8 GHz | `<33 dBm` | `<14 dBm` | up to 19 dB, about 79× EIRP |

They are limits, not constant measured outputs. A third-party tool showing an FCC channel graph
does not prove that the current link is transmitting at 33 dBm. O4 video transmission is also
separate from the controller's ordinary Android Wi-Fi radio; changing Linux/Android Wi-Fi
regdomain state is not evidence that O4 changed.

Source: [DJI RC 2 specifications](https://www.dji.com/rc-2/specs?startPoint=0).

## Normal DJI Fly policy path

```text
DATA_CHANGE / aircraft GNSS / controller or phone GNSS
  / MCC / IP / nearby city / cache
                    │
                    ▼
             AreaCodeManager
                    │
       ┌────────────┼─────────────┐
       ▼            ▼             ▼
AreaCodeFromSky  AreaCodeFromGround  Wi-Fi CountryCode (selected products)
       └────────────┬─────────────┘
                    ▼
          flight-controller AreaCode
                    ▼
      native KeyValue registry and DUML
                    ▼
 sky + ground radio firmware regulatory tables
```

Direct static evidence:

- The Java-facing `AreaCodeStrategy` and `AppAreaCodeStrategy.getBest()` expose the candidate order
  `DATA_CHANGE`, `DRONE_GPS`, `PHONE_GPS`, `MCC`, `IP`, `NEAR_CITY`, and `CACHE`. Final fusion,
  trust, caching, and anti-drift behavior remain inside native `UAVAreaCodeManager`.
- `SDRDeviceAreaCodeLogic` writes the same `AreaCodeInfo` to `AreaCodeFromSky` and
  `AreaCodeFromGround`, retrying each up to ten times at 100 ms intervals. It also writes the
  Wi-Fi country key on applicable products.
- `FlightControllerAreaCodeLogic` compares app and FC area codes and, while connected, retries a
  mismatched FC update every two seconds.
- The Airlink area-code keys are readable, writable, and observable. A separate action queries
  whether the target area code is supported.
- DJI MSDK 5.18.0's arm64 native library maps the modern `GetFCAreaCode` and `SetFCAreaCode`
  operations to FLYC `0x03/0xAF`. The fixed request is nine bytes: subcommand `0x04` plus eight
  zero bytes for GET, or subcommand `0x03` plus the ISO-3166-1 numeric value as little-endian u64
  for SET. The current native GET requires at least nine response bytes and reads the numeric code
  at response offset 1.

Primary reverse-source snapshot:

- [`AreaCodeStrategy.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/uav/areacode/AreaCodeStrategy.java)
- [`SDRDeviceAreaCodeLogic.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/flymodel/v1logics/areacode/SDRDeviceAreaCodeLogic.java)
- [`FlightControllerAreaCodeLogic.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/flymodel/v1logics/areacode/FlightControllerAreaCodeLogic.java)
- [`AreaCodeServiceImpl.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/service/areacode/AreaCodeServiceImpl.java)
- [`UAVAirlinkKey.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/uav/sdk/keyvalue/key/UAVAirlinkKey.java)

### Internal debug controls

Two internal-build controls exist, but neither is a production FCC toggle:

- `debug_area_code_switch` gates whether an internal app sends area code to the device. Its normal
  default allows synchronization; setting it false suppresses a write rather than selecting FCC.
- `key_country_code_local_forever_debug` supplies a persistent mock country to the area-code
  manager, but `AreaCodeServiceImpl` applies it only when the app identifies as an internal build.

These controls strengthen the area-code-policy model. No evidence was found that an account
country, resource overlay, certificate replacement, or public settings screen directly exposes
the same control in a production RC 2 build.

## Community DUML path audit

FreeFCC sends DUML frames to the RC 2 loopback TCP proxy at `127.0.0.1:40009`. ADB or sideloading
only installs the Android app; the loopback DUML transport is the control surface.

### Confirmed state writes and candidate components

1. **Airlink country state.** Wi-Fi/Airlink command family `0x07/0x30` sets country state and
   `0x07/0x19` reads it back. Public RC 2 evidence shows one update changing a following readback
   from `RU` to `AU`. A legacy ten-byte DJI request carries 2.4 and 5 GHz slots, but the audited
   RC 2 handler consumes only the leading alpha-2 code and persists one vendor country slot, so
   duplicate identical frames do not prove per-band writes. On the current aircraft Sky route, one
   authorized US SET produced a matching ACK and fresh GET=US; one CN restore produced a matching
   ACK and fresh GET=CN. On the RC 2 Ground route, one authorized US request produced no matching
   ACK and the fresh GET remained CN, so no restore or retry was sent. The latter is inconclusive,
   not a successful write and not proof of permanent non-support.
2. **Flight-controller area state.** The legacy `DataFlycGetSetProductConfig` class and DJI MSDK
   5.18.0 native code agree on FLYC `0x03/0xAF`: subcommand 3 sets and subcommand 4 gets a nine-byte
   ISO-numeric area slot. On the connected Mini 5 Pro, a bounded `CN(156) -> US(840) -> CN(156)`
   test produced a matching transport ACK and independent GET readback after each write. The
   current DJI SET callback does not inspect an application payload, so ACK alone is insufficient;
   the GET readback is mandatory. This proves only the FC surface in the current session.
3. **Sky SDR FCC selector.** `DataOsdSetSdrAssitantWrite.setForceFcc()` selects Sky, CP_A7, byte
   data, address `0xFFFF0048`, and value `2`, then sends OSD/OFDM command `0x09/0x27`. One community
   frame matches this operation exactly. No current DJI Fly Java caller was found, so it is a
   proven legacy protocol surface, not a proven modern business-path call.

Legacy source references:

- [`DataFlycGetSetProductConfig.java`](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/uav/midware/data/model/P3/DataFlycGetSetProductConfig.java)
- [`DataOsdSetSdrAssitantWrite.java`](https://github.com/ctomichael/fpv_live/blob/4c7bb40e5cc5daec67b39cc093235afb959a4bfe/src/main/java/dji/midware/data/model/P3/DataOsdSetSdrAssitantWrite.java)

### Frames that must not be called “the FCC protocol”

| Item | Evidence-based interpretation |
| --- | --- |
| SDR `0xFFFF0063 = 3` | A frequency-band selector, not a power register; legacy values define `0` dual, `1` 2.4 GHz, and `2` 5.8 GHz, while `3` remains unexplained |
| RC `0x06/0x72` | RC 2 firmware identifies it as stick-value lock; the same ID reaches a different persistent parameter on RC Pro 2 |
| 500 m height write | A flight-controller height configuration side effect, unrelated to FCC |
| Activation, Care, perception, and lost-link frames | Queries, rejected operations, other subsystems, or safety flags; not established RF primitives |
| One-frame “restore CE” | No reliable state readback or controlled A/B proof |
| Four-frame two-second keepalive | Contains neither the country update nor `setForceFcc`; one published test could not restore FCC after a CE fallback |

Public reports describe a visible FCC-like UI result on some real hardware after replaying the
original profile, but socket writes do not establish which frames caused it. The current
implementation's success UI primarily proves that local writes completed; it is not an RF
measurement.

References:

- [FreeFCC repository](https://github.com/doesthings/FreeFCC)
- [Protocol provenance issue #30](https://github.com/doesthings/FreeFCC/issues/30)
- [Command-label audit #24](https://github.com/doesthings/FreeFCC/issues/24)
- [Country-frame audit #25](https://github.com/doesthings/FreeFCC/issues/25)
- [CE-restore audit #29](https://github.com/doesthings/FreeFCC/issues/29)
- [SkylabFCCfree DUML audit v1.5.50](https://github.com/danusha2345/SkylabFCCfree/blob/v1.5.50/docs/DUML_COMMAND_AUDIT.md)
- [dji-firmware-tools DUML dissector](https://github.com/o-gs/dji-firmware-tools/blob/195692263c2684cf1ddc4995f2736be6c0fb135e/comm_dissector/wireshark/dji-dumlv1-proto.lua)

## Current hardware read-only snapshot

At 2026-08-27 05:12:42.250–05:12:54.893 UTC+8, a fixed-address reader queried
SDR Assistant Read `0x09/0x26` on the directly connected aircraft Sky endpoint and the RC 2 Ground
endpoint. Its hard allow-list contained only `0xFFFF0048` and `0xFFFF0063`; it had no SDR write,
country, service, commit, or keepalive path.

| Endpoint | `0xFFFF0048` | `0xFFFF0063` |
| --- | ---: | ---: |
| Aircraft Sky/OFDM | `5` | `0` |
| RC 2 Ground/OSD | `5` | `0` |

Every matching response returned result code zero. This proves that the two endpoints agreed at
that moment. It does **not** name selector value `5`: the only recovered legacy fact is that
`setForceFcc()` writes the literal value `2`. Value `0` at `0xFFFF0063` is the legacy `BAND_DUAL`
frequency-band state; whether current DJI Fly presents that state as “auto” remains an inference.

The legacy RC PowerMode GET (`0x06/0x21`) produced no response on either candidate RC 2 route. That
is evidence that the old query path is not usable here; it is not evidence for CE or FCC state.

## Bounded area/country hardware validation

On 2026-08-27, after an explicit warning that an area change could affect regulatory, FlySafe,
Remote ID, and link policy, the operator authorized a fixed one-shot experiment. The procedure
was:

```text
FC GET -> CN / 156
FC SET -> US / 840
matching ACK + FC GET -> US / 840
FC SET -> original CN / 156
matching ACK + FC GET -> CN / 156
independent final FC GET -> CN / 156
```

A later surface-specific authorization used a double-CN precondition and allowed at most one
forward and one restore write per airlink surface:

```text
Sky GET, GET -> CN, CN
Sky SET -> US; matching ACK + fresh GET -> US
Sky SET -> CN; matching ACK + fresh GET -> CN

Ground GET, GET -> CN, CN
Ground SET -> US; no strictly matching ACK
fresh Ground GET -> CN; no restore SET and no retry
```

No serial number, account, coordinate, or complete raw frame was retained. Two later independent
read-only snapshots reported FC=CN, Sky=CN, Ground=CN; the candidate RC-local country route remained
unavailable. The FindUAS receiver was offline, so the experiments produced no over-the-air Remote
ID, channel, or RF-power evidence. Persistence across an aircraft power cycle is also unknown.

The official native SET callback treats transport success plus a non-null response as success and
does not compare the applied value. Therefore every implementation must use `SET -> independent
GET`, never ACK-only success, and must reject unknown alpha-2 codes rather than inheriting the old
Java implementation's unsafe US fallback.

## Verification ladder

```text
loopback/socket write succeeded
  != target accepted and persisted the request
  != country or SDR selector changed on both endpoints
  != permitted bands/channels and power table changed
  != measured EIRP increased
```

| Level | Read-only evidence | What it establishes |
| --- | --- | --- |
| Transport | Bytes written to local proxy or USB | Only local delivery |
| Protocol state | Matching ACK; Sky/Ground/FC area-code and SDR readback | Target acceptance and state agreement |
| Regulatory surface | Band range, available channels, bandwidth, frequency-point range, DJI Fly graph | Observable policy consequences, still indirect |
| RF measurement | Spectrum analyzer or power meter under shielded/fixed-attenuation A/B conditions | Actual channel and EIRP change |

Range, RSSI, and DJI Fly's distance lines are noisy observables. The display path also applies
path-loss, RC-link, TX-power, and distance offsets; those are graph calibration inputs, not direct
transmit-power readings.

## Open work

1. Recover the current `AreaCodeFromSky`, `AreaCodeFromGround`, `CountryCode`, and support-query
   registrations from matching `libsdk_jni`/KeyValue native libraries. The FC `AreaCode` mapping
   itself is now confirmed.
2. Recover the O4 meaning and ownership of selector value `5`, including reconnect and reboot
   fallback behavior.
3. Keep country-only, FC-area-only, SDR-selector-only, and combined changes separate. Sky country
   is proven only for this fixed route/session. Recover the exact modern Ground route/context from
   passive evidence before proposing another separately authorized test; do not treat the prior
   timeout as permission to retry and do not replay opaque profile frames as the baseline.
4. Determine the final authority and persistence boundary among ground, sky, flight-controller,
   Wi-Fi, and app policy state.
5. Use calibrated RF equipment before making any claim about dBm or EIRP.

This repository must not ship a power-modification profile or a blind keepalive loop. A future
region lab must snapshot every independently writable surface, journal the original values before
the first write, write each forward value at most once, read it back, and restore in reverse order.
If any read returns a third value, it must stop rather than fight DJI Fly's policy synchronizer.

## Scope across DJI generations

Legacy Lightbridge firmware patches, WM160 `/etc/amt/wifi.conf`, RC-N1 USB frames, and O3/O4 Air
Unit marker files are product-specific mechanisms. None is evidence that RC 2 plus a consumer O4
aircraft uses the same implementation. Raising transmitter power may violate local radio rules and
product certification; investigate only with authorization and suitable RF containment.

Research snapshots used for this note:

- `MAVProxyUser/SKYROVER_src` at `8186e19241c913318b140bf37c5eafba005f1e7c`
- `doesthings/FreeFCC` at `597157bd52120dfeb9677f79a8ad46b6027ce8dc`
- `danusha2345/SkylabFCCfree` tag `v1.5.50`, commit
  `aa024985bf1556ab9c3b12f3d0f2305f63b021f5`
- `o-gs/dji-firmware-tools` at `195692263c2684cf1ddc4995f2736be6c0fb135e`
- DJI MSDK 5.18.0 `dji-sdk-v5-aircraft-5.18.0.aar`, SHA-256
  `b2d659c6caf7e8c3bdf672ceacebbcbb17d88d29309fa53f3e232bc26e9b6aa3`; extracted arm64
  `libdjisdk_jni.so`, SHA-256
  `27402f45c63bf6ea9e8d3a783fc1202b53631e0ee24cc18a938ba1e91629dbcf`
