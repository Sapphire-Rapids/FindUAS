# DJI Remote ID Firmware Research

Last updated: 2026-08-27

## Scope and boundary

This document records clean-room, offline research into where DJI Remote ID behavior may live on
the observed `wa150` aircraft and `rc331` DJI RC 2. It is research context, not a FindUAS product
feature or an installation guide.

The repository does not contain a firmware downloader, upgrader, device writer, signature bypass,
Remote ID disable patch, vendor binary, decrypted partition, credential, or private download URL.
All firmware originals and working copies remain outside the repository. No firmware was sent to an
aircraft or controller during this work.

## Assistant 2 inventory snapshot

The installed DJI Assistant 2 service exposes three distinct stages:

1. read-only version and package-configuration metadata;
2. download of individual module files to the Mac, with size and MD5 validation;
3. the separate `upgrade_firm_pack` entry point, which chains download, device transfer, and upgrade.

Only the first two stages were used. The upgrade entry point and the UI button that invokes the
combined workflow were not used.

The 2026-08-27 read-only inventory was:

| Product | Canonical local package | Latest package | Visible packages |
| --- | --- | --- | --- |
| aircraft `wa150` | `01.00.0400` | `01.00.0700` | `01.00.0600`, `01.00.0700` |
| controller `rc331` | `07.00.0100` | `10.00.0800` | `10.00.0100`, `10.00.0400`, `10.00.0700`, `10.00.0800` |

An outer RC local-storage string also reported `08.00.01.20`. It is not the same version layer as
the canonical package value and must not be converted or compared as though the formats were
equivalent. Package byte counts below are sums of module files, not single monolithic downloads.

## `rc331` adjacent-package diff

Official controller packages `10.00.0700` and `10.00.0800` each contain four modules. `0200` and
`0205` changed; `0600` and `1400` have identical version, size, and MD5 records:

| Module | `10.00.0700` | `10.00.0800` | Evidence-based role |
| --- | --- | --- | --- |
| `0200` | `12.14.13.85`, 454,223,680 B | `12.18.16.30`, 468,098,688 B | verified outer APP and protected inner FLYA; inner PRAK/TBIE boundary remains |
| `0205` | `00.01.14.99`, 985,959,104 B | `14.00.00.04`, 985,790,560 B | Android/Qualcomm A/B base-system OTA |
| `0600` | `10.06.00.50`, 108,640 B | identical | RC MCU; unchanged and not the primary adjacent RID/account candidate |
| `1400` | `10.00.19.01`, 25,644,608 B | identical | exact role unresolved; unchanged and lower priority |

## Verified `rc331/10.00.0700/0200` outer boundary

The exact official `0200` module was also obtained outside the repository and locked read-only
after its declared size and official MD5 matched:

| Field | Value |
| --- | --- |
| Module version | `12.14.13.85` |
| Size | 454,223,680 bytes |
| Official MD5 | `cc219b04c4fcf34d8b14569a7e55eae1` |
| Local SHA-256 | `d8a8fe5b418ee6461f6971d9dfad77bc4491d15160d47d5cf8f7481dc7113949` |

A strict no-force pass with public `PRAK-2020-01` verified the outer IMaH v2 header signature,
stored checksum, and plain checksum. It yielded one 454,223,200-byte inner object whose SHA-256 is
`ea5e447b56823c6aa320eb90d4d883bc9f9223cd250a50b47689d23ffd04cb46`. The inner object is
`flyapp`/`RAW`, contains one `FLYA` chunk, and independently selects `PRAK` authentication plus
`TBIE` encryption.

The encrypted inner payload is internally consistent, but none of the eight public PRAK variants
verified its header and none of the six public TBIE variants produced the expected plaintext
checksum. This proves two precise limitations of the tested public key corpus; it does not prove
where the missing material is stored. `--force-continue` would copy ciphertext or emit
checksum-failing bytes, not a verified DJI Fly image. Rooting the controller would not, by itself,
provide the missing key or repair this trust boundary.

## Verified `rc331/10.00.0700/0205` Android OTA

The official `0205` module remained outside the repository and matched all download metadata:

| Field | Value |
| --- | --- |
| Size | 985,959,104 bytes |
| Official MD5 | `5c874f6e39819067caa31b67e0ad341b` |
| Local SHA-256 | `f707cf3dc0be2894b111ce4973d0206e896a2c7e9c4ebe43de1040b528cf49ce` |

An independent `dji_imah_fwsig.py` pass used public `PRAK-2020-01` with no force option. The IMaH
v2 header signature, stored/encrypted chunk checksum, and plain/decrypted chunk checksum all passed;
no chunk was skipped or truncated. The container is type `QCS6`, one chunk, with no content-
encryption key.

The verified inner object is an Android SignApk OTA containing `payload.bin`,
`payload_properties.txt`, metadata, and `otacert`. Its update-engine metadata enumerates 29
partitions: `abl`, `aop`, `bluetooth`, `boot`, `bw_secure`, `cpucp`, `devcfg`, `dsp`, `dtbo`,
`featenabler`, `hyp`, `imagefv`, `keymaster`, `modem`, `multiimgoem`, `odm`, `product`, `qupfw`,
`shrm`, `system`, `system_ext`, `tz`, `uefisecapp`, `vbmeta`, `vbmeta_system`, `vendor`,
`vendor_boot`, `xbl`, and `xbl_config`. Only selected system/vendor/product/odm/boot/vbmeta
partitions were extracted for static inspection; the enumeration does not mean all 29 were extracted.

The base OTA's `/dji_apk` directory is empty. This positively separates the readable platform OTA
from DJI Fly. The changed `0200` module is now confirmed as the protected `flyapp` family, but its
inner FLYA still cannot be converted to verified plaintext with the tested public key corpus.

## Current official DJI Fly native boundary

A current official Android phone-distribution APK was downloaded through DJI's public DJI Fly
download page and official CDN, then kept under the external work tree only. Its manifest reports
DJI Fly `1.21.10`; the APK is 719,464,897 bytes with SHA-256
`0312228ad536381509c09dbfdf1c7e3d4c825c5936199f444058b112985deb3a`. Only targeted entries were
read. The ARM64 `libsdk_jni.so` is 87,313,856 bytes with SHA-256
`5abd990c86bcd00c9a652a21e329ad4580a20ec9f80188075ada61f5a7b46286`.

This native library directly contains the current key/handler vocabulary `EIDSwitch`,
`RidWorkingStatusPush`, `IsEuCeEnableC0Rid`, `CccBroadcastSignalQuality`, `RemoteIDHelper`,
`OIDIdentifier`, and `ComplianceSerialNumber`. It also contains the flight-controller parameter
names `ccc_broadcast_signal_quality_0` and `EU_CE_enable_c0_rid_0`. DJI's established parameter
hash function produces `0xD7757AD2` and `0xF80992FE`, respectively.

The same library independently identifies the modern flight-controller hash-parameter transports:

| Command | Meaning |
| --- | --- |
| FLYC `0x03/0xF7` | obtain parameter metadata by 32-bit hash |
| FLYC `0x03/0xF8` | read the current parameter value by 32-bit hash |
| FLYC `0x03/0xF9` | write a hash parameter; not implemented or exercised here |
| FLYC `0x03/0xFA` | reset a hash parameter; not implemented or exercised here |

Corrected image-base-aware constructor analysis closes both registrations in this build:

- `CccBroadcastSignalQuality` -> `ccc_broadcast_signal_quality_0` ->
  `GetConfigValueHandler<IntMsg>` / `SetConfigValueHandler<IntMsg>`;
- `IsEuCeEnableC0Rid` -> `EU_CE_enable_c0_rid_0` ->
  `GetConfigValueHandler<BoolMsg>` / `SetConfigValueHandler<BoolMsg>`.

`IntMsg` and `BoolMsg` are SDK converter types, not proof of a fixed wire width. The actual
`ConfigDataType` and byte count must come from the F7 metadata response. Current code directly
confirms status at offset 0, a 16-bit type at offset 1, and min/max/default four-byte slots at
offsets 7/11/15; the older public dissector's size/attribute names at offsets 3/5 are corroboration,
not a field naming independently recovered from this binary. These facts do **not** turn either
field into a general RID switch:
the recovered Java business logic owns the C0 value as an automatic cloud/area/CE-class policy and
owns the CCC value as packed broadcast-effect configuration.

This phone APK is strong same-generation native evidence, not proof that the embedded RC 2 runs
the byte-identical package. Exporting the live controller's public base/split APKs remains useful
for exact version parity, but it is no longer necessary merely to establish that these key names,
FC parameter names, and F7/F8/F9/FA transports exist in a current official implementation. No APK,
native library, decompiled source, or private CDN material is present in this repository.

A fixed read-only probe was prepared for only the two recovered parameter hashes and delegates
only to the existing F7 metadata GET and F8 value GET. It has no F9, FA, or generic write path. Its
first live attempt stopped before any USB request was sent because both direct-aircraft and RC-bridge
`claimInterface` calls returned `LIBUSB_ERROR_ACCESS` while DJI Assistant 2 processes were active.
That result is consistent with USB ownership/permission contention, not evidence that either
parameter is absent or that the protocol failed. A future retry should first close Assistant 2
normally, then repeat only the fixed F7/F8 reads.

### Public implementation cross-check

Independent community material supports the command-family interpretation, but its F8 description
is internally inconsistent:

- the pinned `dji-firmware-tools` Wireshark dissector labels F7/F8/F9/FA as metadata/read/write/reset,
  and decodes an older F7 response as
  `[status][type:u16][size:u16][attribute:u16][min:u32][max:u32][default:u32][name...]`;
- DJI-Link's committed DJI Fly 1.21.4 analysis reports the same F7 structure and independently maps
  `RID_WORKING_STATUS` to `0x11/0x1C`, including US bit 0, Cloud bit 10, EU bit 11, and France bit 13
  under product-specific fallback rules. Its `0x0C00` mask covers Cloud bit 10 and EU bit 11
  together; it is not evidence of one EU on/off bit.

The pinned `dji-firmware-tools` parser and DJI-Link's own runtime parser/RTH notes use
`[status][hash][value]`, while DJI-Link's `PARAM_WIRE.md` documents `[hash][value]`. That conflict
could be documentation drift or a real product/route variant; the current 1.21.10 native callback
has not resolved it. A live reader must preserve the raw payload, look for the requested hash at
offset 0 or 1, and accept a layout only after strict response length, F7 type/size, route, sequence,
and echoed-hash checks. If neither candidate closes, the result is unknown rather than a guessed
Boolean.

The two exact parameter names and hashes had no independent indexed GitHub mapping in this audit.
Their name/hash pairing is reproducible with the public DJI hash algorithm, while their handler and
business semantics remain findings from the current official DJI Fly APK—not community-proven
evidence that either parameter exists or is writable on this RC 2/aircraft combination.

## No-root RC 2 access boundary

The selected `vendor` filesystem contains `/vendor/app/dpad_fuli`, package `com.dpad.fuli`, version
`1.0.08.29-5e7f0af3`. Its manifest sets `sharedUserId="android.uid.system"`, `coreApp=true`, and
`debuggable=true`. Its command screen forwards entered text to `Runtime.getRuntime().exec(...)`.
That is a privileged system-UID execution context under SELinux, **not root UID 0**. Its `haveRoot()`
helper merely attempts the literal command `adb shell su`; there is no successful `su` or `id`
transcript. The app also exposes updater/recovery, Type-C, FTM, SDR, MCU, and log-toggle surfaces,
none of which was launched on the live controller.

This is evidence from adjacent official package `10.00.0700`, not proof that the connected
controller runs the same package or exposes the same activity. The latest live rootless MTP/PTP
view returned 14 directories and zero files, with no DJI Fly APK or `dpad-test` path. Assistant's
RC 2 front end advertises all-log export, but the matching backend `GetLogList` and `ExportAllLog`
methods are explicit unsupported stubs. Its separate data-export mode was not entered because it
changes device service state.

A fixed-version public-prior-art audit found no current RC331 record that closes all of: no root,
base plus every split, per-file hashes, signing-certificate identity, and a replayable export
transcript. It also found no public plaintext recovery of this exact `10.00.0700/0200` FLYA. The
closest low-risk paths are Android's documented `publicSourceDir`/`splitPublicSourceDirs` interface
and a public DJI Fly 1.21.4 disposable-arm64-emulator recovery report with fixed artifact hashes.
Committed DJI-Link DEX files are useful for symbol cross-checking, but their source-package identity
does not prove byte parity with the live RC 2. These are route-selection clues, not a reason to root
or unlock the controller.

Targeted inspection of `dji_link`, `dji_lte`, `dji_wlm`, `dji_sdrs_agent`, and their Duml/WLM/TEE
libraries identified no explicit Remote ID/RID/UAS-ID platform service and no DJI user-account
`account`/`login` service. This is a scoped negative result for the base OTA, not product-wide
absence. `dji_link` activation, certificate, TEE, RPMB, and crypto-state paths describe device
activation/trust and must not be relabelled as DJI user login.

The same inspection recovered an explicit lower platform country path: root service `dji_link`
handles authenticated country events and persists `/mnt/dji_persist/country.bin`; root service
`dji_sdrs_agent` applies a wireless-country operation. Both are configured with `AUTH_DJIGO`.
`dji_wlm` also contains an internal SDR/Wi-Fi/LTE power-level test handler, but no safe public
property, level enum, registered message ID, or downstream acceptance rule was recovered. These are
static anchors, not permission to invoke a service or guess a writer.

The base properties are debug-friendly, but the DJI-modified `adbd` overrides the ordinary
`ro.adb.secure` result with a production/user-lock function. Its decision combines production
state, debug count, user/lockscreen state, and a one-time authorization flag. Therefore
`ro.adb.secure=0` is not proof of an unauthenticated root shell. If a future ADB test is separately
authorized, it must use an isolated disposable key and stop after a handshake plus `id` if the
production gate blocks access.

Root or bootloader unlock is therefore not the next step. A separately authorized, allow-listed
system-UID check of `id` and `pm path dji.go.v5`, followed only after review by a controlled copy of
public base/split APK paths, is the nearest justified escalation. No such command was run in this
pass. Bootloader unlock, Magisk/root, modified boot, and flash are rejected on the current
controller: AOSP specifies a data wipe and changed Verified Boot state, and a public single-device
RC 2 report records persistent DJI TEE/application failure and a later non-booting state. That
report is a serious warning, not proof of an eFuse mechanism or a universal outcome.

## `wa150` adjacent-package diff

Both aircraft packages contain ten module records. Eight records have identical version, size, and
MD5 values. Only these records changed:

| Module | `01.00.0600` | `01.00.0700` | Evidence-based role |
| --- | --- | --- | --- |
| `0802` | `10.00.12.83`, 679,368,672 B, anti 1 | `10.00.15.17`, 679,295,296 B, anti 2 | IMaH type `E3`; main-system candidate; about 98% of the package |
| `2603` | `01.00.00.01`, 436,000 B | `01.05.03.01`, 437,312 B | IMaH type `GNSS`; filename identifies the UC6580 GNSS platform |

The four official module files were downloaded into an external analysis directory. Each matched
the exact package-config size and MD5 and was then made read-only. Additional SHA-256 values are:

| Package/module | SHA-256 |
| --- | --- |
| `01.00.0600/0802` | `c36bcbd17f03f6f3aaed66a381c5823e510f72d19a74495b3a30780b2c560386` |
| `01.00.0600/2603` | `4a573ab95316de69137deb71249ead09c23325a28acbf9ee305a36410775f274` |
| `01.00.0700/0802` | `83978e131181977fee908641102ce8bd9b5c8fe6d34e0af8fd600a1aa5c307a9` |
| `01.00.0700/2603` | `cb9b8f6c274e50551dbb683d9440eeeef60717775e3db5278c74d79de371aaba` |

## Container and trust boundary

All four files begin with `IM*H` and use format 2, `PRAK` authentication, `STUE` encryption, one
chunk, and a 384-byte signature. The two `0802` headers report type `E3`; the two `2603` headers
report type `GNSS`. The `0802` anti-version changed from 1 to 2 between packages, matching the
filename change from `.ar1` to `.ar2`. The official meaning of the filename suffix itself remains
an inference.

Upstream `dji-firmware-tools` supports IMaH v2 and 384-byte/3072-bit RSA/PSS signatures. The blocker
for these `wa150` files is target-specific key material: none of the public PRAK variants matches
their signatures, and no public reproducible `STUE` decryption material is available. Analysis
therefore stopped at the authenticated/encrypted outer boundary. `--force-continue` was not used;
it would continue with encrypted/unverified chunk data, not produce verified plaintext.

This is the current firmware blocker. Obtaining a binary is no longer the problem; obtaining a
lawful, reproducible, integrity-checked plaintext view of `0802` is.

## Why `0802` is the primary RID candidate

Direct evidence rules out `2603` as the primary RID service:

- its container type is `GNSS`;
- its filename identifies UC6580, a GNSS receiver platform;
- GNSS can supply position, velocity, and time and can affect RID pre-flight self-test, but it does
  not provide the aircraft's Wi-Fi or Bluetooth broadcast path.

`0802` is the stronger candidate because it dominates the package, is typed as `E3`, and adjacent
DJI aircraft research identifies this module family as a main OS image containing system/vendor
components and DJI services. Until plaintext is available, the exact RID process, library, or
driver remains unknown.

Existing application/native anchors to correlate with a future `0802` diff include:

- `KeyRidWorkingStatusPush` and all seven raw fields, preserving both `failResion` and `failReason`;
- HMS codes 30331 through 30334;
- `UAVRidCloudControlLogic` and `RID_BROADCAST_EFFECT_ICLOUD_CONTROL`;
- `uav_fc_handle_eid_switch` and `uav_fc_eid_switch_status` (France EID only);
- `uav_adsb_set_app_update_pos_enc` and the registered shared-key query symbols;
- `rid`, `remote_id`, `uas_id`, `operator`, `astm`, `f3411`, `area_code`, `pfst`, Wi-Fi beacon,
  Bluetooth, and NAN strings or service names.

These are search anchors, not setter definitions or permission to generate writes.

## Non-flashable integrity experiment

A clone of the `01.00.0700/0802` module was placed outside Assistant's cache, renamed with a
`.nonflashable.bin` suffix, and changed at exactly one payload byte (zero-based offset 4096). No
manifest was copied next to it.

The size remained 679,295,296 bytes, but:

- the official MD5 changed from `998d1f1448e8f4cddc3269c2c7549f65` to
  `1332f1f1e6db26ad2c215fcc49599808`;
- SHA-256 changed from
  `83978e131181977fee908641102ce8bd9b5c8fe6d34e0af8fd600a1aa5c307a9` to
  `dafe2c69e0ccf5ebeeaed2e9fd894f3ee3ac997453bc2b247c499aefe64a3fff`;
- the computed encrypted-payload SHA-256 changed to
  `030e351077962169afb6e377d2d6d8cd2513c8d7cd2892c0f9245503e459be60`, while the original digest
  remained in the IMaH header.

This proves failure at both the Assistant package MD5 and internal payload-digest layers. It is not
an RID patch and does not by itself prove an RSA verification result, because no matching public
`wa150` PRAK key is available to validate the original signature. The experiment did not repair checksums,
re-sign, repack, transfer, or flash the file.

## Handoff sequence

1. Keep originals immutable and outside this repository. Verify size, official MD5, and local
   SHA-256 before every analysis run.
2. Controller track: do not repeat the verified `0205` extraction or the exhausted public-key
   sweep over `0200`. Use the current official phone APK to continue handler-level static mapping.
   Export the live controller's public `dji.go.v5` base/splits only when exact RC-build parity is
   needed; this remains a no-root package-manager task.
3. Aircraft track: seek an authorized read-only plaintext source for `wa150/0802`; do not treat
   forced extraction as validated output. If plaintext becomes available, inventory nested
   containers before extraction and diff 0600/0700 by file hash.
4. Correlate any static finding with the read-only RID status/HMS timeline and an independent RF
   receiver. Aircraft self-report alone is not proof of OTA transmission.
5. Do not unlock the current controller bootloader, root/Magisk-patch it, modify boot, flash it, or
   reuse an existing/private ADB key. A future authorized ADB experiment must use an isolated,
   disposable key and a fixed read-only command set.
6. After DJI Assistant 2 is closed, retry only the two allow-listed F7/F8 parameter reads. Treat an
   unsupported status, missing response, or unknown width as unavailable; never escalate to F9 by
   guessing a value type.
7. Do not implement a firmware writer, signature bypass, generic DUML endpoint, or Remote ID-off
   control in FindUAS.

## Repository hygiene and known traps

- Never commit DJI firmware, APKs, extracted vendor files, decrypted partitions, Assistant static
  material, request-authentication material, temporary CDN links, account data, device IDs, or
  modified firmware copies.
- The official DJI Fly phone APK and targeted native entries are work-only research inputs. Record
  only hashes and independently recovered behavior; do not commit the package, libraries,
  decompiled code, certificate, or CDN query.
- Never commit extracted RC 2 partitions, platform applications, system binaries, ADB keys, or
  device-authorization records. System UID must never be described as root.
- Do not launch `dpad_fuli` updater/recovery, Type-C, FTM, SDR, MCU, or log-toggle functions for
  exploratory purposes. Adjacent-package presence is not live-device proof.
- `dji-firmware-tools` is GPL-3.0. Do not copy it into this MIT repository.
- The installed Assistant's `app.asar` contains abnormal entries that caused a whole-archive
  extractor to create about 153 GiB of invalid temporary data. Use targeted reads or validate entry
  offsets and sizes before extraction; do not repeat whole-archive extraction.
- Downloading a module to an external analysis directory does not authorize device transfer or
  upgrade. The combined Assistant UI flow must not be used as a "download, then interrupt" method.

## Sources

- [DJI Drone Security White Paper](https://www.dji.com/trust-center/resource/white-paper)
- [DJI Remote ID FAQ](https://repair.dji.com/help/content?customId=01700007747&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)
- [DJI Fly official download page](https://www.dji.com/downloads/djiapp/dji-fly)
- [DJI Mobile SDK Android V5](https://github.com/dji-sdk/Mobile-SDK-Android-V5)
- [Nozomi Networks: DJI Mavic 3 firmware analysis](https://www.nozominetworks.com/blog/dji-mavic-3-drone-research-part-1-firmware-analysis)
- [`dji-firmware-tools`](https://github.com/o-gs/dji-firmware-tools)
- [`dji-firmware-tools` F7/F8/F9 dissector](https://github.com/o-gs/dji-firmware-tools/blob/195692263c2684cf1ddc4995f2736be6c0fb135e/comm_dissector/wireshark/dji-dumlv1-flyc.lua)
- [`dji-firmware-tools` RC331 FLYA issue #467](https://github.com/o-gs/dji-firmware-tools/issues/467)
- [`dji-firmware-tools` 3072-bit IMaH support](https://github.com/o-gs/dji-firmware-tools/commit/739da082c08418d74195dcd4002322bff08014a1)
- [Unicore UC6580 product page](https://en.unicore.com/products/dual-band-gps-chip-uc6580/)
- [Independent exact `rc331/0205` corroboration](https://github.com/danusha2345/SkylabFCCfree/commit/51ef14244cbd2e9346db67fd9dd15e08e30750e8)
- [DJI-Link 1.21.4 parameter wire analysis](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/reverse_docs/PARAM_WIRE.md)
- [DJI-Link 1.21.4 Remote ID telemetry table](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/reverse_docs/TELEMETRY_TABLE.txt)
- [DJI-Link 1.21.4 RTH/F8 runtime notes](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/reverse_docs/RTH_ALTITUDE_RESEARCH_2026.md)
- [DJI-Link F8 runtime parser](https://github.com/Kolya080808/DJI-Link/blob/13b357f405149674a33e3285780885728f52cafe/dji_link_beta/src/core/client.cpp)
- [Android `ApplicationInfo` public APK paths](https://developer.android.com/reference/android/content/pm/ApplicationInfo)
- [DJI Fly 1.21.4 emulator recovery report](https://github.com/glasses666/dji4g-qdc507-research/blob/1218ac361e65917cd41b82cebe5ea89e72549462/reports/REPORT.md)
- [AOSP Verified Boot device state](https://source.android.com/docs/security/features/verifiedboot/device-state)
- [AOSP Verified Boot flow](https://source.android.com/docs/security/features/verifiedboot/boot-flow)
- [RC 2 single-device risk report](https://github.com/whitelewi1-ctrl/dji-rc2-research/commit/fc5949acfe8196e2faccf96615821b62fbe60804)
