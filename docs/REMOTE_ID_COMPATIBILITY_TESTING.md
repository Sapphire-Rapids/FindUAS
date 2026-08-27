# Remote ID compatibility testing and region profiles

Last reviewed: 2026-08-27

This note answers two related but materially different questions:

1. Can DJI RC 2 / DJI Fly expose a Remote ID on/off or region control?
2. Can FindUAS provide a safe switch and region selector for receiver compatibility testing?

The short answer is **no** to a general aircraft-broadcast switch and **yes** to an isolated,
offline compatibility-test mode. A test profile must never be presented as changing the aircraft,
remote controller, receiver, radio country code, channel plan, or transmit power.

This document records research and an implementation boundary. The proposed test mode has not yet
been implemented.

## Decision summary

| Proposed control | Evidence and meaning | Product decision |
| --- | --- | --- |
| Disable ordinary aircraft Remote ID | No public generic DJI switch was found; US and current Chinese requirements explicitly prevent an ordinary operator disable control | Do not implement |
| French Electronic ID switch | DJI exposes a writable French EID setting on supported products | Keep as research context; do not expose through FindUAS |
| DJI MSDK area strategy | Selects a regional SDK delegate for development; it is not proof of changing the aircraft's true region or over-the-air format | Investigate only in a separate, supported MSDK test app |
| FlySafe `RID_UNLOCK` | An official managed license type; a retained, stubbed delegate branch suggests a matching enabled license may produce `NO_BROADCAST` | Never represent as a local toggle or reproduce its authorization path |
| FindUAS compatibility-test switch | Starts/stops a synthetic or captured-data replay pipeline that does not touch hardware | Recommended |
| FindUAS validation profile selector | Selects the expected fields and conditions for one versioned regional profile | Recommended, labelled “does not change device region” |
| Real receiver RF compatibility test | Requires a standards-compliant source and controlled RF setup | Separate lab phase, not an aircraft country-code change |

## “Remote ID switch” is not one control

### Ordinary Broadcast Remote ID

DJI Fly receives a working-state report from the aircraft through `KeyRidWorkingStatusPush`. It
can report `IDLE`, `WORKING`, an operator-location or firmware error, `NO_BROADCAST`, or
`NOT_SUPPORTED`. That is a status path, not a writable user preference.

No generic local `force working`, `broadcast enabled`, or `disable RID` debug Boolean was found in
the recovered DJI Fly and MSDK paths. The aircraft's self-report must also not be confused with an
independent RF observation; a separate receiver is still required to show that packets are
actually receivable.

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
`setElectronicIDEnabled()` under the France strategy. It must not be generalized to FAA Remote ID,
EU operator registration, Japanese registration, or Chinese operation identification.

FindUAS is a BLE client for the external receiver and has no supported DJI aircraft control path,
so this setting does not belong in the FindUAS application.

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

This is strong evidence that DJI can perform an internal real-area experiment. It is a poor
Remote ID compatibility control for an external test tool because it crosses multiple regulatory
surfaces at once:

- flight-controller area and FlySafe policy;
- Remote ID regional behavior and registration flows;
- Sky/Ground radio country policy and possibly the available channel/power profile;
- cached and continuously synchronized state, with retry behavior on failed writes.

It has no supported production UI, its native update rules are not fully recovered, and changing
it would not by itself prove which Remote ID packets were emitted. This path should remain a
read-only research finding unless a separate, authorized laboratory protocol defines exact
readback, isolation, restoration, and independent RF measurement. It must not be implemented in
FindUAS.

### `RID_UNLOCK` is a managed license, with unverified runtime behavior

DJI's official FlySafe model includes `RID_UNLOCK`; the currently recovered types are European and
China. A retained delegate branch after a leading stub return only treats it as active when an
enabled license matches the current area strategy, then reports `NO_BROADCAST`. This is structural
evidence of a possible authorization-backed exception path, not runtime verification and not a
locally minted preference. FindUAS must not request, synthesize, replay, or expose it as a switch.

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

The first implementation should use explicit profiles rather than informal country names:

- `rawReceiverOutput`
- `usPart89Standard`
- `usPart89BroadcastModule`
- `eu2019_945Integrated`
- `eu2019_945Addon`
- `jpMLITDirectRID2022`
- `cnGB46750_2025`
- `ukCAA2026`
- `sgCAAS_AS10`

Profiles are read-only data. They may contain the standard/version, device category, field
requirements, one-of conditions, source URLs, review date, and a list of properties that the
receiver output cannot establish. They must not contain a country-code write, frequency, power,
DUML command, GATT command, or executable callback.

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

The test controller must own its own framing/session state. Evidence must be created from each raw
decoded frame **before** `TelemetrySession`-style target merging and then evaluated in an explicit
observation window; it must never be reconstructed from `activeTargets`. The controller must not
publish into the live `BluetoothManager` or `AppState` path, because that path can alert, merge with
real targets, and persist history through `RecordStore`.

### User-visible behavior

- Put the control in a separate **Compatibility Test** view, not ordinary receiver settings.
- Default it to off and do not restore “on” after relaunch.
- Label the profile selector “validation profile — does not change device region”.
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
4. If DJI SDK strategy behavior is still useful, build a separate official-MSDK experiment and
   compare SDK state, aircraft-reported area, and independent RF reception. Do not fold it into
   FindUAS and do not substitute guessed native writes.
5. Keep the O4 FCC/CE area-code investigation separate from Remote ID profiles.

## Sources

- [DJI MSDK V5 `IUASRemoteIDManager`](https://developer.dji.com/api-reference-v5/android-api/Components/IUASRemoteIDManager/IUASRemoteIDManager.html)
- [DJI MSDK V5 `IFlyZoneManager` and `RID_UNLOCK`](https://developer.dji.com/api-reference-v5/android-api/Components/IFlyZoneManager/IFlyZoneManager.html)
- [DJI MSDK V5 official sample](https://github.com/dji-sdk/Mobile-SDK-Android-V5)
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
- [Recovered DJI Fly EID UI path, pinned source](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/component/fpv/widget/setting/ui/safety/remoteidentify/SettingRemoteIdSwitchViewModel.java)
- [Recovered DJI Fly internal area-code path, pinned source](https://github.com/MAVProxyUser/SKYROVER_src/blob/8186e19241c913318b140bf37c5eafba005f1e7c/com/uav/service/areacode/AreaCodeServiceImpl.java)
- [DJI MSDK V5.18.0 `aircraft-provided` artifact](https://repo1.maven.org/maven2/com/dji/dji-sdk-v5-aircraft-provided/5.18.0/dji-sdk-v5-aircraft-provided-5.18.0.jar)
- [FindUAS receiver protocol notes](PROTOCOL.md)
- [DJI RC 2 state research](DJI_RC2_STATE_RESEARCH.md)
- [DJI RC 2 RF-power and area-code research](DJI_RC2_RF_POWER_RESEARCH.md)
