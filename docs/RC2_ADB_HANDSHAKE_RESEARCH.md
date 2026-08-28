# DJI RC 2 ADB handshake research

This document records the redacted, reproducible boundary established for a DJI RC 2 whose UI
reported firmware `07.00.0100`. It is research context for maintainers, not a root, unlock, or
firmware-modification guide.

No shell, APK install, Android command, reboot, fastboot operation, bootloader unlock, root,
Magisk, firmware write, or DJI protocol request was used in the experiments below. No ADB key or
device authorization record is included in this repository.

## Result

The observed failure occurs before ordinary ADB authentication:

```text
Host -> CNXN
RC 2 -> no ADB packet
        bulk-IN timeout after about 15 seconds
```

The controller returned neither `AUTH TOKEN` nor `CNXN`. Consequently, neither the normal
`AUTH SIGNATURE` path nor the known DJI direct-public-key-after-token path was reached. Standard
`adb devices -l` consistently reported `offline`, not `unauthorized` or `device`.

## Live USB descriptor

The descriptor was enumerated from the connected unit instead of assuming an older firmware
layout. Device serials, USB addresses, port locations, and host-specific paths were deliberately
omitted.

```text
VID:PID 2ca3:1021

Interface 0  ff/43/01
  bulk OUT 0x01, bulk IN 0x81, MaxPacket 512

Interface 1  06/01/01 (MTP/PTP)
  bulk OUT 0x02, bulk IN 0x82, interrupt IN 0x83

Interface 2  ff/42/01 (ADB-shaped)
  bulk OUT 0x03, bulk IN 0x84, MaxPacket 512
```

The system ADB server was stopped before each custom claim of interface 2.

## Reproduced host profiles

Stock platform-tools 37.0.1 was tested through both the macOS legacy USB backend and libusb. A
handshake-only client also reproduced the pre-authentication profile of
[`Dr-Muh/dji-adb`](https://github.com/Dr-Muh/dji-adb/tree/027c7815568c89e55fff22bfeede9dd294404660):

```text
version  = 0x01000000
MAXDATA  = 262144
banner   = "host::pydevice\0"
framing  = separate 24-byte header and payload USB transfers
```

The client validated ADB magic, checksum, length, and short transfers; it was hard-limited to
`CNXN` and, only after a real token, `AUTH RSAPUBLICKEY`. It never sent `OPEN` or a shell service.
The RC 2 did not return a token, so the public-key packet was never sent.

Starting from the exact profile above, changing one variable at a time did not advance the state:

| Single changed variable | Result |
| --- | --- |
| protocol version `0x01000001` | no reply; timeout |
| MAXDATA `1 MiB` | no reply; timeout |
| short `host::\0` banner | no reply; timeout |
| stock 286-byte feature banner | no reply; timeout |
| zero legacy payload checksum | no reply; timeout |

Combining header and payload into one USB transfer caused an immediate I/O-path failure. Current
[`ya-webadb`](https://github.com/yume-chan/ya-webadb/tree/340d3fe0f0f6a44830ac41965106a2aea41bc484)
also preserves separate header/payload transfers, so combined framing is not a useful
authentication lead.

Current WebADB can skip `AUTH SIGNATURE` when it has no stored key, but only after receiving
`AUTH TOKEN`. It therefore has the same pre-authentication dependency and does not explain the
observed `CNXN` silence.

## Exact adjacent `adbd` root cause

The no-force-verified adjacent RC331 `10.00.0700/0205` Android OTA contains an unstripped AArch64
`adbd` with SHA-256:

```text
b300d9bb90f5941fe2952bc9f6dacc30e639a498be4435f59a4ae95134bd5422
```

Static disassembly establishes two DJI-specific gates.

First, `adbd_main()` reads the ordinary `ro.adb.secure` value and then overwrites the resulting
global `auth_required` decision with `is_dji_production_lock()`:

```c
production_locked =
    getprop("ro.boot.mp_state", "engineering") == "production" &&
    get_int_prop("ro.boot.dbg_cnt", 0) < 1;

user_locked =
    getprop("rc.userlock.state", "locked") != "unlock" &&
    getprop("persist.rc.lockscreen.state", "disabled") == "enabled";

auth_required =
    (production_locked || user_locked) && !once_auth_open_adb;
```

Second, the `CNXN` branch in `handle_packet()` parses the host banner and then independently repeats
the production-state test. When `ro.boot.mp_state` is `production` and `ro.boot.dbg_cnt < 1`, it
logs the embedded text below and frees the packet without calling `send_auth_request()` or
`send_connect()`:

```text
[lsx_dbg]handle_new_connection return
```

That branch precisely explains the live trace: the USB OUT transfers succeed, but the daemon emits
neither `AUTH TOKEN` nor `CNXN`. Deleting host keys, toggling USB debugging, changing the banner,
or skipping `AUTH SIGNATURE` cannot fix a path that never reaches authentication.

`once_auth_open_adb` exists as a BSS flag, but only a read was found in this binary; no in-binary
writer or safe external setter was established. More importantly, the repeated per-`CNXN`
production check does not use that flag. It is therefore not a documented or usable debug switch.

## Unverified authentication branch

The same static switch statement handles `AUTH/RSAPUBLICKEY` independently from `CNXN` and can
reach `adbd_auth_confirm_key()`. This makes a first-packet public-key experiment a technically
interesting hypothesis, not a result. It has not been sent to the controller.

Such a test is state-changing: it can display an authorization prompt and may persist an accepted
key. It requires separate action-specific approval, a disposable key generated outside the normal
ADB key directory, a packet-only client that never sends `OPEN`, a user watching the RC 2 screen,
and deletion of the temporary host key after the run. Do not reuse or publish an existing ADB key.

## DJI development assistant boundary

The adjacent OTA includes DJI's `com.dpad.fuli` development assistant under Android system UID
1000. Its internal `ShellCommandActivity` is not a clean diagnostic carrier: opening that page
automatically attempts `adb shell su`, writes a test command, and runs `adb version`; its generic
executor also discards stderr and the process exit status. Empty output is therefore ambiguous.

Do not use that page as proof of shell privilege, and do not open its updater/recovery, Type-C,
FTM, SDR, MCU, Share, or log-control functions for exploration. System UID is not root UID 0.

## Current conclusion and next step

The `offline` state is explained by a DJI production gate in `adbd`, not by an ordinary Android RSA
authorization failure. Repeating stock ADB, WebADB, key deletion, USB-debugging toggles, or
post-token signature/public-key variations is low value while the daemon remains silent at
`CNXN`.

The only narrowly justified next ADB experiment is the separately authorized, disposable-key,
first-packet public-key hypothesis described above. It must remain handshake-only and may not be
combined with bootloader, fastboot, root, firmware, or shell work.

Primary source comparisons:

- [AOSP ADB](https://android.googlesource.com/platform/packages/modules/adb/)
- [`Dr-Muh/dji-adb` pinned revision](https://github.com/Dr-Muh/dji-adb/tree/027c7815568c89e55fff22bfeede9dd294404660)
- [`ya-webadb` pinned revision](https://github.com/yume-chan/ya-webadb/tree/340d3fe0f0f6a44830ac41965106a2aea41bc484)
