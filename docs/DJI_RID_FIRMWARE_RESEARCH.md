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
| `1400` | `10.00.19.01`, 25,644,608 B | identical | RC ground-side `SPARROW_GND`/Sparrow2 radio image family; unchanged |

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
`ConfigDataType` and byte count used by F8/F9 come from the initialized `CCacheConfigKeyInfo`, not
from the Java/Kotlin converter name or a guessed Boolean width. Current code directly confirms F7
status at offset 0, a 16-bit type at offset 1, and min/max/default four-byte slots at offsets
7/11/15; the older public dissector's size/attribute names at offsets 3/5 are corroboration, not a
field naming independently recovered from this binary. A successful F7 metadata response remains
a mandatory live capability gate even though that callback is not what populates the SDK cache.
These facts do **not** turn either field into a general RID switch:
the recovered Java business logic owns the C0 value as an automatic cloud/area/CE-class policy and
owns the CCC value as packed broadcast-effect configuration.

This phone APK is strong same-generation native evidence, not proof that the embedded RC 2 runs
the byte-identical package. Exporting the live controller's public base/split APKs remains useful
for exact version parity, but it is no longer necessary merely to establish that these key names,
FC parameter names, and F7/F8/F9/FA transports exist in a current official implementation. No APK,
native library, decompiled source, or private CDN material is present in this repository.

A fixed research-only probe was prepared for only the two recovered parameter hashes. It exposes
F7 metadata GET and conditionally F8 value GET, and has no F9, FA, or generic hash path. After DJI
Assistant 2 was closed and its USB interfaces released, both direct-aircraft and RC-routed
plaintext F7 requests received the same one-byte payload `0x03` for both hashes. That payload is an
error/end form, not the at-least-20-byte metadata record required before any F8 value read.

This was not a broken F7 transport: on the same live RC path, the established height-limit,
distance-limit, and distance-enabled parameters returned valid F7 metadata and F8 values. A
separate legacy DJI SIMPLE-encryption control produced no matching response, while plaintext
continued to pass the positive controls. The strongest current conclusion is therefore that
`ccc_broadcast_signal_quality_0` and `EU_CE_enable_c0_rid_0` are not currently readable through
this Mini 5 Pro's live FLYC metadata surface. Current DJI Fly does more than carry generic handler
strings: its type-139/UAV139 (`wa150`) abstraction dynamically registers both FCConfig mappings.
That application-side registration still does not prove the target FC firmware provides or
enables either parameter. Status `0x03` may represent absence, a runtime/product gate, or another
refusal; its exact public enum name remains unresolved and is not guessed. Neither candidate is
eligible for F8 or F9 on this hardware.

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
could be documentation drift or a real product/route variant. The current 1.21.10 native callback
does resolve its own build: byte 0 is a batch status, then entries repeat
`[hash:u32le][value:cached_size]`. Size and `ConfigDataType` come from the SDK cache metadata, not
from guessing the Java type. A reader for this build must require that layout plus strict response
length, route, sequence, known request hash, cached size/type, and exact final cursor. An
offset-zero hash parser may remain relevant only to a separately identified older variant; it
must not be silently selected because it yields a plausible value.

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

The eight unchanged records are six `1100` battery variants, one `1200` ESC image, and the single
`0806` image discussed below. This inventory leaves no separate changed Wi-Fi/Bluetooth/Remote-ID
module to patch in isolation; any new 0600-to-0700 RID logic is most likely inside `0802`, while a
runtime policy or unchanged radio component could still consume it.

The four version-targeted `0802`/`2603` module files were downloaded into an external analysis
directory. Each matched the exact package-config size and MD5 and was then made read-only.
Additional SHA-256 values are:

| Package/module | SHA-256 |
| --- | --- |
| `01.00.0600/0802` | `c36bcbd17f03f6f3aaed66a381c5823e510f72d19a74495b3a30780b2c560386` |
| `01.00.0600/2603` | `4a573ab95316de69137deb71249ead09c23325a28acbf9ee305a36410775f274` |
| `01.00.0700/0802` | `83978e131181977fee908641102ce8bd9b5c8fe6d34e0af8fd600a1aa5c307a9` |
| `01.00.0700/2603` | `cb9b8f6c274e50551dbb683d9440eeeef60717775e3db5278c74d79de371aaba` |

## Container and trust boundary

Those four files begin with `IM*H` and use format 2, `PRAK` authentication, `STUE` encryption, one
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

### Read-only auditor positive controls

The external work tree now has a read-only IMaH auditor that validates declared sizes, the payload
SHA-256, the v2 encrypted-data checksum, and the RSA signature over the header plus chunk table. It
does not extract, decrypt, modify, repack, transfer, or flash firmware. The same code successfully
verified both official RC 2 positive controls: the `0200` outer APP and `0205` QCS6 OTA pass their
payload/checksum checks and verify with public `PRAK-2020-01`; both outer chunks are plaintext.
All five downloaded WA150 files consistently stop at the target-specific PRAK/STUE boundary. This
rules out a generic parser failure as the reason WA150 cannot currently be patched.

Static inspection of the installed Assistant 2 adds a separate negative result. Its legacy DA2
verifier copies a `0x20c` public-key structure for a 2048-bit key and passes a fixed `0x100`-byte
signature to its RSA verifier. WA150 uses a `0x180`-byte/3072-bit signature. That embedded verifier
therefore does not supply the matching WA150 key, an STUE content key, or any private signing key.
The Mac being able to download and transfer a package is not evidence that it can decrypt or
re-sign the package; the modern target trust chain may perform the decisive verification.

### Assistant readback audit

The installed retail Assistant 2 build was also checked for a no-write route from a live WA150 to
an `0802/E3` plaintext image. WA150's product configuration and native services do implement an
end-to-end log/data-export flow: the device is asked to enter an export mode, then explicitly
offered log directories and files can be listed and downloaded through the product's FTP/file
service. No corresponding partition, block, upgrade-slot, running-image, or `0802` readback handler
was found. This means the official export flow may later provide useful RID diagnostics, but it is
not evidence of arbitrary filesystem access or decrypted firmware extraction.

The front end also contains `ReadFlashData` under an `/esc/config/` route. It is grouped with ESC
configuration, erase, selection, and motor-test functions; the installed native services contain
no matching WA150 handler or `0802` binding. It is therefore a generic or legacy ESC UI surface,
not a demonstrated aircraft-main-system readback API. Firmware-download and cryptographic helper
code likewise belongs to the inbound upgrade path and does not form the missing reverse chain:

```text
live 0802 partition -> authenticated readback -> host-side decryption -> verified plaintext image
```

No Assistant binary or device service was launched for this audit, and no device mode was changed.

## Why `0802` is the primary RID candidate

Direct evidence rules out `2603` as the primary RID service:

- its container type is `GNSS`;
- its filename identifies UC6580, a GNSS receiver platform;
- GNSS can supply position, velocity, and time and can affect RID pre-flight self-test, but it does
  not provide the aircraft's Wi-Fi or Bluetooth broadcast path.

The package-identical `0806` module was also downloaded once through the same target-locked,
download-only path and independently matched its official 12,251,264-byte size and MD5. Its local
SHA-256 is `75bc1b74a0d46a43aa4099fc9f4570087e99c12298985528b5e961c712d1dfbc`.
The IMaH header directly identifies its type as `DONG`; the filename includes `4GG4CN`. It is also
a single STUE-encrypted, 384-byte-PRAK-signed chunk with no matching public key material. This is
stronger evidence for an optional communication-dongle role than for the aircraft's primary RID
service, and it does not provide a plaintext route around `0802`.

The published 2023 S1/Sparrow `SDRH` signature bypass is not presently transferable evidence. That
work used unsigned runtime patch records accepted by the older S1 transceiver boot chain and
verified the issue on Mini 2-era hardware; the same paper explicitly found a different Mavic 3
transceiver unaffected by that signature bypass. No WA150 metadata, downloaded module header, or
current public sample has shown `sparrow_firmware`, an `SDRH` record, or an unsigned post-verify
patch loader. Treating the old technique as an O4/WA150 method without those prerequisites would be
guessing at a boot-critical path.

A separate static audit of the RC 2 Sparrow2 components closes another tempting shortcut. The
controller's `dji_sdrs_agent` is a ground-side (`SPARROW_GND`, module `1400`) transport orchestrator:
it selects the aircraft-compatible ground-radio image, invokes `brload`, and then invokes fixed
`fastboot flash` operations. Package verification occurs earlier in the Android upgrade framework,
while the Sparrow2 Boot ROM/bootloader remains the final image-acceptance boundary. The agent is not
a signing or decryption oracle, and its WA150 compatibility directory is not an aircraft `0802`
plaintext copy.

No `SDRH` or equivalent runtime-patch descriptor was found in the complete inspected RC system and
vendor artifacts. An unsigned-package branch is gated by secure-debug state, with no evidence that
a retail controller or aircraft can enter that state. Existing file and crash-dump channels expose
named files, logs, or diagnostics rather than a safe decrypted aircraft image. Manufacturing flows
that write `cmpu_ver`, `cmpu_kdr`, `cmpu_pro`, or OTP before a staged transfer are not read-only and
must not be used for exploratory recovery; they can alter production or key state irreversibly.

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
  remained in the IMaH header;
- the computed encrypted-data checksum changed from the declared `0x81949d7d` to `0x81949d7c`.

This proves failure at the Assistant package MD5, internal payload-digest, and encrypted-data
checksum layers. Recomputing the two internal fields would still change the signed header and
require the unavailable matching private key. It is not an RID patch and does not by itself prove
an RSA verification result, because no matching public `wa150` PRAK key is available to validate
the original signature. The experiment did not repair checksums, re-sign, repack, transfer, or
flash the file.

## Modern FlySafe license query and enable paths

The official MSDK 5.18 implementation has now been followed from its public/JNI entry through the
current native PackProvider map and version-specific sessions. Its outer query chain is:

```text
FC serial
  -> queryFCLicensesJni
  -> native_QueryLicenseFromFC(productId, deviceId)
  -> ModuleMediator::QueryLicenseFromFC
  -> queued product/device resolver
  -> GetUnlockSupported + GetUnlockVersion
  -> V2 / V3 / V4 query session
  -> PackProviderImpl
  -> dji::sdk::send_data
  -> accumulated whole FlysafeLicenseGroup
```

The exact native samples used for the current mapping are independently identified as:

| File | GNU Build ID | SHA-256 |
| --- | --- | --- |
| `libdjisdk_jni.so` | `28ce8986e0fdd02a30ebe2f3c66b77a33ec8f931` | `27402f45c63bf6ea9e8d3a783fc1202b53631e0ee24cc18a938ba1e91629dbcf` |
| `libDJIFlySafeCore-CSDK.so` | `5e89d17659059297b200b1de47e328183845636f` | `1749d31c8ececb15b3da7c07a967ac9946ac05a0aaffd9e3d3840bd7db09e1ed` |

The current binary's own static PackType table gives direct, not inferred, mappings:

| Operation | PackType | Current tuple | Meaning |
| --- | ---: | --- | --- |
| query inventory | `0x38` | `11 11 00 01` | cmdset `0x11`, cmdid `0x11`, unknown byte `0`, ACK result byte present |
| set license enable | `0x39` | `11 12 00 01` | cmdset `0x11`, cmdid `0x12`, unknown byte `0`, ACK result byte present |

The query endpoint therefore reuses numeric `0x11/0x11`; a different command number is not needed
to explain the old live timeout. The current session contract contains several other variables:

- V2 query uses a one-byte zero-based record/page index;
- V3/V4 send `00 01` for group info and then `00 (index << 1)` per record;
- V3/V4 group info and licenses are protobuf messages, with a separate status byte on each record;
- support and version gates select V2/V3/V4 before sending;
- receiver route can be product- and version-dependent rather than the hand-written probe's route;
- PackProvider removes the ACK's first result-code byte before passing the remainder to the parser.

Because V2 itself uses a one-byte index, this static recovery does not identify which variable
caused the earlier hand-built requests to time out, nor does it establish that Mini 5 Pro selects
V2, V3, or V4. That requires a legitimate current-session support/version result and receiver route.

The protobuf union has a dedicated RID field; the domain type is `RID_UNLOCK == 6`, its RID payload
contains `level`, and each returned record carries invalid/enabled/in-valid-date status. The
official MIT sample independently displays `RID_UNLOCK`/`ridUnlockType` and enables or disables an
existing license before pulling the list again. This makes the enable state of a genuine signed
type-6 record the strongest current candidate for a stable laboratory switch. It does not create,
forge, upload, or entitle such a record, and MSDK 5.18 does not list Mini 5 Pro as an officially
supported product.

The set-enable path is also statically closed through its manager gate, V2/V3/V4 builders,
PackProvider, `dji::sdk::send_data`, and ACK parser. V2 uses six payload bytes containing a
little-endian license ID, a Boolean byte, and one zero byte. V3/V4 use seven bytes containing a
leading zero byte, little-endian license ID, `1` for enable or `2` for disable, and a trailing zero
byte. These layouts are deliberately not implemented as a sender here: no current Mini 5 Pro ACK,
genuine type-6 record, rollback, or independent RF effect has yet been verified. A returned
per-item Boolean is not proof that Remote ID was emitted or silenced.

The read path's recovered local call graph contains no explicit DJI-account-login check. That
narrow negative result does not cover cloud license download, entitlement, binding, upload, or
firmware-side policy. Current DJI Fly 1.21.10 package strings likewise prove only that a generic
license subsystem is present. The executable DJI Fly 1.21.4 prior version recognizes only license
types 0--4/255 and can mis-handle type 6, so its generic label or switch is not usable RID evidence.

## Handoff sequence

1. Keep originals immutable and outside this repository. Verify size, official MD5, and local
   SHA-256 before every analysis run.
2. Controller track: do not repeat the verified `0205` extraction or the exhausted public-key
   sweep over `0200`. Use the current official phone APK to continue handler-level static mapping.
   Export the live controller's public `dji.go.v5` base/splits only when exact RC-build parity is
   needed; this remains a no-root package-manager task.
3. Aircraft track: seek an authorized read-only plaintext source for `wa150/0802`; do not treat
   forced extraction, Assistant log FTP, `/esc/config/ReadFlashData`, RC ground-Sparrow images, or
   manufacturing `get_staged` flows as validated output. If plaintext becomes available, inventory
   nested containers before extraction and diff 0600/0700 by file hash.
4. Correlate any static finding with the read-only RID status/HMS timeline and an independent RF
   receiver. Aircraft self-report alone is not proof of OTA transmission.
5. Do not unlock the current controller bootloader, root/Magisk-patch it, modify boot, flash it, or
   reuse an existing/private ADB key. A future authorized ADB experiment must use an isolated,
   disposable key and a fixed read-only command set.
6. Do not repeat the completed RID-policy hash probes: both fixed candidates returned unavailable
   F7 status on live direct/RC routes while known positive controls succeeded. Never escalate to F9
   by guessing a value type.
7. The modern query and set-enable schemas are now statically closed. The next dynamic step, if
   separately staged in the work tree, is read-only: obtain the legitimate current-session support
   and version state, reproduce the matching receiver route, and inventory only redacted type,
   level, enable, and validity fields. Do not retry the legacy one-byte request outside a proven V2
   session or feed V3/V4 group bytes to the legacy parser.
8. Do not implement a firmware writer, signature bypass, generic DUML endpoint, or Remote ID-off
   control in FindUAS.
9. Do not invoke Sparrow2 `brload`/`fastboot`, replace `bootarea.img`, touch modem/NVRAM images, or
   execute `cmpu_*`/OTP production scripts. None is a proven readback path, and some can be
   irreversible.

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
- [MSDK 5.18 FlySafe sample model](https://github.com/dji-sdk/Mobile-SDK-Android-V5/blob/a48aa4e7811d824c27abfa973f5655579bfb8a77/SampleCode-V5/android-sdk-v5-sample/src/main/java/dji/sampleV5/aircraft/models/FlySafeVM.kt)
- [MSDK 5.18 RID license display and enable UI](https://github.com/dji-sdk/Mobile-SDK-Android-V5/blob/a48aa4e7811d824c27abfa973f5655579bfb8a77/SampleCode-V5/android-sdk-v5-sample/src/main/java/dji/sampleV5/aircraft/pages/FlySafeFragment.kt)
- [NDSS 2023 DJI firmware/DroneID study](https://www.ndss-symposium.org/ndss-paper/drone-security-and-the-mysterious-case-of-djis-droneid/)
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
