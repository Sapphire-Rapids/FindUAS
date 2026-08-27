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
