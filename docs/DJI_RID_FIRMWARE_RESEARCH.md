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

The public `dji-firmware-tools` PRAK variants do not validate this newer header/signature, and the
tool has no `STUE` decryption material. Analysis therefore stopped at the authenticated/encrypted
outer boundary. `--force-continue` was not used: unsupported output must not be represented as
verified plaintext.

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
an RID patch and does not by itself prove an RSA verification result, because the public verifier
cannot validate the original PRAK signature either. The experiment did not repair checksums,
re-sign, repack, transfer, or flash the file.

## Handoff sequence

1. Keep originals immutable and outside this repository. Verify size, official MD5, and local
   SHA-256 before every analysis run.
2. Seek an authorized read-only plaintext source for `0802`; do not treat forced extraction as
   validated output.
3. If plaintext becomes available, inventory Android OTA/A/B/AVB and nested containers with
   info/verify operations before extraction.
4. Diff 0600 and 0700 by file hash, then inspect changed init scripts, SELinux policy, system/vendor
   services, JNI libraries, wireless configuration, and RID/PFST anchors.
5. Correlate static findings with the read-only RID status/HMS timeline and an independent RF
   receiver. Aircraft self-report alone is not proof of OTA transmission.
6. Do not implement a firmware writer, signature bypass, generic DUML endpoint, or Remote ID-off
   control in FindUAS.

## Repository hygiene and known traps

- Never commit DJI firmware, APKs, extracted vendor files, decrypted partitions, Assistant static
  material, request-authentication material, temporary CDN links, account data, device IDs, or
  modified firmware copies.
- `dji-firmware-tools` is GPL-3.0. Do not copy it into this MIT repository.
- The installed Assistant's `app.asar` contains abnormal entries that caused a whole-archive
  extractor to create about 153 GiB of invalid temporary data. Use targeted reads or validate entry
  offsets and sizes before extraction; do not repeat whole-archive extraction.
- Downloading a module to an external analysis directory does not authorize device transfer or
  upgrade. The combined Assistant UI flow must not be used as a "download, then interrupt" method.

## Sources

- [DJI Drone Security White Paper](https://www.dji.com/trust-center/resource/white-paper)
- [DJI Remote ID FAQ](https://repair.dji.com/help/content?customId=01700007747&lang=en&paperDocType=ARTICLE&re=US&spaceId=17)
- [Nozomi Networks: DJI Mavic 3 firmware analysis](https://www.nozominetworks.com/blog/dji-mavic-3-drone-research-part-1-firmware-analysis)
- [`dji-firmware-tools`](https://github.com/o-gs/dji-firmware-tools)
- [Unicore UC6580 product page](https://en.unicore.com/products/dual-band-gps-chip-uc6580/)
