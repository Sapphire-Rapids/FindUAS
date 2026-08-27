# Changelog

All notable user-visible changes are documented here. The project follows semantic versioning once
stable releases begin.

## Unreleased

### Added

- Added the “Compatibility Lab” administrator safety preview with versioned validation profiles,
  a staged broadcast intent, five explicit prechecks, a 5–15 minute lease,
  staged/local-dry-run/rollback states, and a bounded in-memory redacted audit log.
- Added read-only lab status for the receiver plus a fixed DJI USB observer for device presence,
  FC area, Sky/Ground country, and the France-only EID state when the FC area is FR. A generic
  Remote ID switch is intentionally absent; France EID has no setter; region writes are not
  implemented in the app.
- Added strict, hardware-free DJI frame/CRC/route/sequence/command/payload checks and region-state
  reconciliation checks.

### Documentation

- Defined the boundary and phased design for isolated Remote ID region-profile compatibility
  testing, distinct from aircraft broadcast, regulatory-area, and RF-power controls.
- Recorded that USB visibility of the current DJI Mini 5 Pro / DJI RC 2 pair is not an official
  MSDK 5.18.0 control path, and documented the interlocks required by a future external
  OpenDroneID-based laboratory source adapter.
- Recorded the live read-only FC/Sky/Ground `CN` snapshot, unavailable France EID result, bounded
  FC and Sky `CN -> US -> CN` research round trips, and the single Ground request that produced no
  matching ACK and left readback at CN. These are not described as a complete region, Remote ID,
  channel, or RF-power change.
- Documented the DJI Assistant 2 `wa150`/`rc331` package inventory, the `0802` main-system and
  `2603` GNSS module evidence, and the corrected distinction between IMaH parser support and missing
  target PRAK/STUE material.
- Recorded no-force verification of the official adjacent `rc331/10.00.0700/0205` Android OTA, its
  29-partition inventory, the system-UID/non-root development-assistant boundary, and the decision
  to reject bootloader unlock/root on the current controller. No firmware, APK, extracted partition,
  downloader, upgrader, root tool, or Remote ID patch is included.
- Recorded strict outer verification of `rc331/10.00.0700/0200`, the separate inner PRAK/TBIE
  failure boundary, and targeted static evidence from the current official DJI Fly native library:
  two RID-policy Key/parameter/handler registrations plus distinct F7 metadata-read, F8 value-read,
  F9 write, and FA reset transports. After Assistant was closed, the two fixed RID-policy hashes
  returned only F7 status `0x03` over both direct and RC-routed plaintext paths, while known
  height/distance parameters passed on the same route; neither candidate was read or written.
- Recovered the exact seven-byte native `0x11/0x1C` RID/EID working-status layout and recorded
  strict read-only aircraft/RC 2 motors-off baselines. No status candidate appeared without an
  official subscription or state transition; this is not reported as lack of RID support or as an
  RF result.
- Cross-checked DJI-Link and `dji-firmware-tools`: both corroborate the hash-command family and the
  former independently corroborates RID status route `0x11/0x1C`. DJI-Link's own wire document and
  runtime parser disagree on the F8 prefix; current DJI Fly 1.21.10 native code resolves its build
  as `[batch_status][hash][cached-size value]...`. The UAV139/wa150 abstraction dynamically
  registers both RID-policy mappings, but the live FC still returns no metadata for either.
- Audited public RC331 extraction/decryption prior art and found no exact, reproducible no-root
  base/split export for the current build and no plaintext recovery of the exact `10.00.0700/0200`
  FLYA; root and bootloader unlock therefore remain outside the next-step path.
- Identified DJI's official signed FlySafe `RID_UNLOCK` license as the leading stable-control
  candidate: published type 6 with EU/China levels, account download, FC-SN filtering, push/pull,
  and license enable/disable semantics. Documented a privacy-redacted, read-only `0x11/0x11`
  inventory check and explicitly excluded neighboring upload/toggle commands and license forgery.
- Recorded that the legacy inventory request timed out through both direct-aircraft and RC 2 proxy
  routes while immediate FC-area and Sky/Ground-country positive controls succeeded. This is
  classified as a product/transport mismatch, not an empty license inventory.
- Traced MSDK 5.18's current pull path from FC serial through FlySafe JNI/session mediation to a
  whole `FlysafeLicenseGroup`, including RID-license model support. Recorded that its exact queued
  wire message remains unresolved and that DJI Fly 1.21.10 package evidence does not prove a
  type-6 UI or consumer entitlement; the older executable UI cannot safely label type 6.

### Security and privacy

- The laboratory backend is explicitly no-RF and no-device-write: profile selection and “start”
  change local memory only, never aircraft, controller, receiver, country-code, channel-plan, or
  RF-power state.
- The DJI bridge exports no raw command or setter API, reads no USB strings, and rejects replies
  that fail length, CRC, reverse-route, sequence, command, or fixed-payload checks.
- The app bundle does not currently include libusb; the optional DJI observer requires a compatible
  external `libusb-1.0` and otherwise reports unavailable without affecting receiver features.
- Lab audit entries are typed, bounded, non-persistent, and exclude raw packets, device/aircraft
  identifiers, coordinates, credentials, and private operator-registration data.

## 0.1.0 - 2026-08-27

### Added

- Native macOS SwiftUI client for FindUAS/FindUAV BLE receivers.
- Receiver discovery, connection, FF01/FF02 notification handling, and confirmed FF02 writes.
- Legacy JSON and V2 framing with automatic detection.
- Live targets, aircraft/operator map markers, local history, whitelist, and alert sound.
- Live and historical target details covering identity, location, motion, GNSS quality, and receiver
  metadata.
- Independent BLE interoperability documentation and regression checks.

### Fixed

- Live device-list refresh no longer depends on switching views.
- Connected state now requires the FF01 telemetry characteristic, not merely a BLE link.
- FF01 V2 assembly no longer indexes `Data` from zero after prefix removal.
- Relative payload timestamps no longer cause fresh targets to disappear.
- Nested `RID_Standard` and `Reg` fields are decoded from `UAVInfo`.
- Firmware sentinel values no longer appear as real map positions, altitudes, or headings.

### Security and privacy

- No account, telemetry upload, or private registration lookup.
- Receiver configuration writes are validated and confirmed; FF03 remains untouched.
- Real hardware identifiers and coordinates are excluded from the repository.
