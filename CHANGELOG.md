# Changelog

All notable user-visible changes are documented here. The project follows semantic versioning once
stable releases begin.

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
