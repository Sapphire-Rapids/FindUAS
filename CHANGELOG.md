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

### Fixed

- Corrected the product-139 France-EID fixed read-only GET target from the older FLYC address
  assumption `0x03` to the recovered static default `0x92`. Its validator now accepts only the
  command-specific clear-response set `{0x80,0xC0}` and an exact two-byte successful canonical ACK;
  no setter or generic DUML surface was added.

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
  `2603` GNSS module evidence, the protected `0806/DONG` LTE candidate, and the corrected
  distinction between IMaH parser support and missing target PRAK/STUE material. A one-byte
  non-flashable `0802` integrity sample demonstrates package-MD5, payload-digest, and encrypted-
  checksum breakage. Format analysis maps the changed header fields into the signature coverage,
  but no matching WA150 public key was available for offline signature verification and no target
  acceptance or rejection behavior was exercised. No patch was transferred or flashed.
- Audited retail Assistant readback and RC 2 Sparrow2 loading. WA150's implemented export surface
  is diagnostic log/data FTP rather than `0802` plaintext readback; the ESC `ReadFlashData` UI has
  no discovered WA150 backend. The ground-side chain is Android upgrade-framework package checking,
  agent-orchestrated `brload`/fastboot transfer, and final target Boot ROM/bootloader acceptance,
  with no discovered retail unsigned patch gate or safe aircraft-image readback. No vendor binary
  was executed, and no device mode, loader, fastboot, manufacturing script, or device write was used.
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
- Rejected installation of a third-party approximately 52 MB multi-capability APK and documented
  the independent `com.finduas.ridobserver` research line. Historical v0.1-v0.4 are withdrawn and
  must not be installed or started: even an input-only `40007`/`40009` connection may replace DJI
  Fly's single active broker fd. Their parsers/tests remain offline-only. The current same-package
  v0.10 candidate has zero requested permissions, one launcher Activity, and no service, receiver,
  provider, socket, DUML, DJI application Binder transaction, process execution, file persistence,
  network send, native library, or agent/library attach/load path. It retains v0.8's read-only
  environment inventory and adds strict self-process ART identity: two stable maps snapshots,
  bounded page-aligned geometry, symlink-safe descriptor identity, nanosecond metadata, whole-file
  SHA-256/build ID, and two named known-profile ranges that are never invoked. The 2,570,983-byte
  candidate has SHA-256
  `fdad29bfb1237bc224a805d6eb5a99358a044bd226610d9f0fc33975d94b606c`; 43 tests, lint,
  manifest/final-DEX/signature/zipalign, 21 adversarial mutations, and two byte-identical builds
  pass. Independent audit found no unresolved P0–P3. It has not been copied, installed, or run on
  RC 2; sealed v0.8/v0.9 are provenance records rather than current staging instructions.
- Recorded that the ADB host opens the RC 2 endpoints and sends `CNXN`, but receives neither
  `AUTH` nor `CNXN` and stays offline across stock backends, the pinned Dr-Muh pre-auth profile,
  and isolated version/MAXDATA/banner/checksum changes. Static disassembly of the exact adjacent
  unstripped `adbd` closes the cause: DJI overwrites ordinary `ro.adb.secure` policy and its CNXN
  branch drops the packet when `ro.boot.mp_state=production` and `ro.boot.dbg_cnt<1`, before
  `send_auth_request()` or `send_connect()`. A first-packet public-key branch remains an untested,
  state-changing hypothesis and was not sent. No shell or ADB installation was used. USB parentage showed both visible storage LUNs
  belonged to the aircraft; one interim work-only APK copy was removed only after an exact hash
  match, and the RC 2 microSD was not exposed through that USB configuration. A separately resolved
  removable card was explicitly authorized for MBR/ExFAT formatting, received the sole APK with a
  matching source/destination hash, passed read-only ExFAT verification, and was safely ejected.
  RC 2 initially offered only native reformat rather than browse for that Mac-created volume.
  After RC-native storage setup, the user successfully installed the signed PackageInstaller and
  FileManager helpers plus an earlier observer build. That historical observer must remain stopped
  and be overwritten in place only after separate staging authorization by the no-permission/
  no-socket v0.10 environment probe; ADB remains offline and was not used.
- Cross-checked DJI-Link and `dji-firmware-tools`: both corroborate the hash-command family and the
  former independently corroborates RID status route `0x11/0x1C`. DJI-Link's own wire document and
  runtime parser disagree on the F8 prefix; current DJI Fly 1.21.10 native code resolves its build
  as `[batch_status][hash][cached-size value]...`. The UAV139/wa150 abstraction dynamically
  registers both RID-policy mappings, but the live FC still returns no metadata for either.
- Audited N3Live at pinned revision `bb254b0d0b1f5ac79462e9fe3ea986fc91adeec0`.
  Corrected the evidence attribution: N3Live reads Goggles N3 USB IF4 and has no RC-local
  `40007`/`40009`, RID decoder or encryption-selector parser. Selector-0 target admission is a
  separate retired-observer fact at the RC-local broker and does not show that O4 is clear.
  N3Live's 416-command list is extracted template-symbol metadata from an uncommitted input
  library, not a call graph or proof of payload, route, product support or safe setter semantics.
- Recovered a smaller conditional same-owner France-EID baseline route in current DJI Fly 1.21.10:
  `JNIRawData.native_SendData` reuses the initialized SDK/SessionMgr and returns raw ACK application
  payload through its existing callback, preserving `[protocol_result,state]`. It remains offline-
  only until current productId/deviceId/senderIndex/HostID, product139/France/EID identity, loader
  and connection-epoch gates are closed. Also rejected the stock `dpad_fuli` Protocol page: it has
  no selector control and its Parcel path reconstructs retry max 2, so it cannot reproduce the
  corrected native policy. `uav_cmd_req+0x08` is retry rather than receiver index; receiver index is
  at `+0x19`. Product-139 initializes retry to 3; static EID registration gives Characteristics
  `+0x30` the value 0, so the initial typed GET retains 3, while a runtime update may make its
  conditional clear apply. Typed SET retains 3. The proposed raw retry-0 GET is therefore an
  explicitly safer laboratory single-shot, not an official-exact retry claim.
- Rebuilt the offline-only ARM64 JVMTI V0 canary with mandatory `DisposeEnvironment`. Final APK
  SHA-256 is `4a3867251a745ce5db6c0513c23def5c97e53a57e17f4d611621895e4e323c73`; the earlier
  non-disposing build is revoked. Neither V0 nor V1 has been copied, installed or attached. The
  adjacent stock `dpad_fuli` Shell page is also withdrawn as a possible launcher because it
  automatically probes `adb shell su`, runs `adb version`, and discards stderr/exit status; a
  separately audited side-effect-free, result-preserving UID1000 caller is still required. A full
  exported-component audit found no alternate fixed-command caller in that package, and Android 11
  `attach-agent` requires the signature-level `SET_ACTIVITY_WATCHER` permission; an ordinary
  debuggable app or `/system/bin/cmd` child does not bypass that caller check.
- Sealed the offline-only ARM64 JVMTI V2.1 route resolver. Its final APK SHA-256 is
  `7f0159619f89f7c6a9849b1028003a1070d97988838da7a6ef027e09626ada0d`, and its sole packaged
  library SHA-256 is `3c2a293e167531ecc9d352c2825ad20c8f35a3e829c66aad6896d06eabad3365`.
  Independent audits cover deterministic builds, manifest/ELF/imports, exact compiled profile tables,
  symbol extents, relocations and the immutable-zero exception gate. The artifact cannot pass
  `EXCEPTION_BOUNDARY_UNPROVEN`, contains no request or transport path, and has never been staged.
- Withdrew the earlier global same-worker epoch assumption. The primary datalink add/remove path is
  worker-serialized, but ProductMgr callbacks and the complete HardwareLayer writer surface are not.
  A worker-tail recheck is now classified only as `STABLE_OBSERVED`; any future request requires
  nested-safe `active_mutators`, a monotonic `connection_epoch`, reader double-checks, and a shared
  reader/writer `route_gate`, with fail-closed telemetry for coverage and lock ordering.
- Rejected the proposed three-symbol C++ exception bridge after an exact NDK 27 catch-all compile
  also required `_ZSt9terminatev`. Live exception GOT/PLT coherence across the three interposable
  DJI DSOs remains unproved. Recorded a reduced exact-build stack-SSO `EIDSwitch`/stack-prefix route
  that removes target string and CacheKey allocation, while keeping it NOT ADMITTED because direct
  characteristics lookup still contains target unwind and shared-owner cleanup paths.
- Defined the missing runtime whole-file identity gate for a future route resolver. The offline
  official DJI Fly 1.21.10 APK profile is restricted to extracted native SOs; a live RC 2 package
  must first match that profile. Exact whole-ELF SHA-256 must then be bound to the
  loaded mappings by two maps device/inode/offset snapshots and non-writable `PT_LOAD` byte
  comparison. APK-entry, deleted, memfd/anonymous, unreadable or drifting sources fail closed; this
  did not change or admit V2.1.
- Rejected the raw-GET prototype's fixed 100 ms callback quiet window. ACK delivery occurs before
  pending-node erase, timer delivery before copied-owner destruction, and explicit cancellation is
  asynchronous. Any future GET must prove ordered registration, callback-return/in-flight zero and
  exact pending/Stopper absence at a post-terminal worker-tail fence; no live path was admitted.
- Specified the zero-send raw-GET quiescence state machine and recovered a worker-only pending
  predicate. `SessionMgr::IsSending` can conservatively prove absence of a unique `03/77` route
  tuple, but is not handle-specific; `CallbackStopper` has no read predicate. The design therefore
  remains NOT ADMITTED until exact locked membership and lifecycle/fence hooks exist.
- Closed product-139's EASA operator-registration surface: the registered
  `OperatorRegistrationNumber` string GET/SET handlers use `0x03/0x78`, with an explicit delete
  operation. This is OPID registration data, not a broadcast Boolean. A complete current Fly/MSDK
  sweep found no ordinary Boolean master switch spanning France EID, EASA OPID/C0, Japan DIPS,
  FAA/US, and China OID. Legacy `EidOpen`/`EidClose`/`EidIsOpen` declarations and the industry-France
  `EIDBroadcastEnable` key stop at generated/shared metadata in the current app; none has a current
  native handler or UAV139 characteristic, so they do not establish a Fly 1.21.10/WA150 control.
- Recorded the offline-only ARM64 JVMTI V1 France-EID semantic-anchor resolver (final APK SHA-256
  `ccdf198c83ecdd3d33a54192e2bffeb9ab89ce65289497643d16f5a00bff62b2`). It only counts two exact
  already-loaded generated thunks and their shared ClassLoader, then cleans references and disposes
  its JVMTI environment. It has never been copied, installed, or attached and contains no Java
  invocation, GET/LISTEN/SET, socket, Binder, or DUML path.
- Located same-owner raw France-EID ACK evidence before the native Boolean converter and a native
  all-command observer before pending matching. Neither has live admission: locking/thread
  serialization, C++ callback ABI, observer ID, removal, and unload lifecycle remain unresolved,
  and no sender or setter was built or run.
- Audited public RC331 extraction/decryption prior art and found no exact, reproducible no-root
  base/split export for the current build and no plaintext recovery of the exact `10.00.0700/0200`
  FLYA; root and bootloader unlock therefore remain outside the next-step path.
- Identified DJI's official signed FlySafe `RID_UNLOCK` license as the leading stable-control
  candidate: published type 6 with EU/China levels, account download, FC-SN filtering, push/pull,
  and license enable/disable semantics. Documented a privacy-redacted, read-only inventory check
  and explicitly excluded license upload, forgery, replay, and product integration of a setter.
- Clarified that the public Mainland/overseas RID application forms still depend on server-side
  `support_unlock_type=Rid` eligibility and bind product information to the flight-controller
  serial; no public result establishes Mini 5 Pro/WA150 issuance or acceptance. A genuine signed
  record, pull/readback, bounded restore, and independent motor-on RF observation remain required.
- Recorded that the legacy inventory request timed out through both direct-aircraft and RC 2 proxy
  routes while immediate FC-area and Sky/Ground-country positive controls succeeded. The cause
  remains unresolved; session, payload, route, and selected license version are possible factors,
  and the result is not an empty-license-inventory finding.
- Traced MSDK 5.18's current pull path from FC serial through FlySafe JNI/session mediation to a
  whole `FlysafeLicenseGroup`, including RID-license model support. Recovered the current native
  query `PackType 0x38 -> 0x11/0x11` and set-enable `PackType 0x39 -> 0x11/0x12` mappings, the
  V2/V3/V4 request layouts, support/version and receiver-route gates, ACK result-byte handling,
  protobuf/status parsing, and enable-result parsing. These are static protocol findings, not
  evidence that the Mini 5 Pro has a genuine type-6 entitlement or that RF state changes.

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
