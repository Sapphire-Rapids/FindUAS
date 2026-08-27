#ifndef C_DJI_USB_BRIDGE_H
#define C_DJI_USB_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Result codes for the fixed, read-only DJI USB bridge.
 *
 * The bridge intentionally has no generic command, payload, frame, identifier,
 * or write API. Every USB transfer it can originate is compiled into the
 * implementation as one of four known GET requests.
 */
typedef enum DJIUSBBridgeStatus {
    DJIUSB_BRIDGE_STATUS_OK = 0,
    DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT = 1,
    DJIUSB_BRIDGE_STATUS_LIBUSB_UNAVAILABLE = 2,
    DJIUSB_BRIDGE_STATUS_DEVICE_NOT_FOUND = 3,
    DJIUSB_BRIDGE_STATUS_ACCESS_DENIED = 4,
    DJIUSB_BRIDGE_STATUS_INTERFACE_BUSY = 5,
    DJIUSB_BRIDGE_STATUS_USB_IO = 6,
    DJIUSB_BRIDGE_STATUS_TIMEOUT = 7,
    DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR = 8
} DJIUSBBridgeStatus;

typedef struct DJIUSBBridgeDevicePresence {
    uint8_t libusb_available;
    uint8_t aircraft_present;
    uint8_t controller_present;
} DJIUSBBridgeDevicePresence;

typedef struct DJIUSBBridgeFCArea {
    uint64_t iso_numeric;
    /** NUL-terminated ISO alpha-2 code when the numeric value is recognized. */
    char alpha2[3];
} DJIUSBBridgeFCArea;

typedef struct DJIUSBBridgeCountry {
    /** NUL-terminated uppercase two-letter value returned by the fixed GET. */
    char alpha2[3];
} DJIUSBBridgeCountry;

typedef struct DJIUSBBridgeFranceEIDStatus {
    /** 1 when the validated status bit is set, otherwise 0. */
    uint8_t enabled;
} DJIUSBBridgeFranceEIDStatus;

/** Enumerates only the two supported USB product types; no strings are read. */
DJIUSBBridgeStatus dji_usb_bridge_get_device_presence(
    DJIUSBBridgeDevicePresence *out_presence
);

/** Fixed aircraft FC product-area GET (command set/id 0x03/0xAF). */
DJIUSBBridgeStatus dji_usb_bridge_get_aircraft_fc_area(
    DJIUSBBridgeFCArea *out_area
);

/** Fixed aircraft Sky country GET (command set/id 0x07/0x19). */
DJIUSBBridgeStatus dji_usb_bridge_get_sky_country(
    DJIUSBBridgeCountry *out_country
);

/** Fixed RC 2 Ground country GET (command set/id 0x07/0x19). */
DJIUSBBridgeStatus dji_usb_bridge_get_ground_country(
    DJIUSBBridgeCountry *out_country
);

/**
 * Fixed product-139 France-EID status GET (0x03/0x77, body 0x02).
 * Uses the recovered static-default target 0x92; runtime HostID overrides and
 * the private DJI Fly route are not inferred or scanned. The implementation
 * accepts only correlated clear response 0x80/0xC0 and an exact two-byte
 * successful canonical body. It is not a generic RID query or setter.
 */
DJIUSBBridgeStatus dji_usb_bridge_get_france_eid_status(
    DJIUSBBridgeFranceEIDStatus *out_status
);

/**
 * Runs deterministic, hardware-free CRC, fixed-frame, and response-validation
 * checks. It performs no dynamic loading and no USB access.
 */
uint8_t dji_usb_bridge_protocol_self_test(void);

#ifdef __cplusplus
}
#endif

#endif
