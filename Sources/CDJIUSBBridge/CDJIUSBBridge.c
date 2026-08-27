#include "CDJIUSBBridge.h"

#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

/* libusb is loaded dynamically so the application has no build-time SDK or
 * library dependency. Only the ABI subset used below is declared here. */
typedef struct libusb_context libusb_context;
typedef struct libusb_device libusb_device;
typedef struct libusb_device_handle libusb_device_handle;

struct libusb_device_descriptor {
    uint8_t bLength;
    uint8_t bDescriptorType;
    uint16_t bcdUSB;
    uint8_t bDeviceClass;
    uint8_t bDeviceSubClass;
    uint8_t bDeviceProtocol;
    uint8_t bMaxPacketSize0;
    uint16_t idVendor;
    uint16_t idProduct;
    uint16_t bcdDevice;
    uint8_t iManufacturer;
    uint8_t iProduct;
    uint8_t iSerialNumber;
    uint8_t bNumConfigurations;
};

typedef int (*libusb_init_fn)(libusb_context **context);
typedef void (*libusb_exit_fn)(libusb_context *context);
typedef ssize_t (*libusb_get_device_list_fn)(
    libusb_context *context,
    libusb_device ***list
);
typedef void (*libusb_free_device_list_fn)(libusb_device **list, int unref_devices);
typedef int (*libusb_get_device_descriptor_fn)(
    libusb_device *device,
    struct libusb_device_descriptor *descriptor
);
typedef libusb_device_handle *(*libusb_open_device_with_vid_pid_fn)(
    libusb_context *context,
    uint16_t vendor_id,
    uint16_t product_id
);
typedef void (*libusb_close_fn)(libusb_device_handle *handle);
typedef int (*libusb_claim_interface_fn)(libusb_device_handle *handle, int interface_number);
typedef int (*libusb_release_interface_fn)(libusb_device_handle *handle, int interface_number);
typedef int (*libusb_bulk_transfer_fn)(
    libusb_device_handle *handle,
    unsigned char endpoint,
    unsigned char *data,
    int length,
    int *transferred,
    unsigned int timeout_ms
);

typedef struct LibUSBAPI {
    void *library;
    libusb_init_fn init;
    libusb_exit_fn exit;
    libusb_get_device_list_fn get_device_list;
    libusb_free_device_list_fn free_device_list;
    libusb_get_device_descriptor_fn get_device_descriptor;
    libusb_open_device_with_vid_pid_fn open_device_with_vid_pid;
    libusb_close_fn close;
    libusb_claim_interface_fn claim_interface;
    libusb_release_interface_fn release_interface;
    libusb_bulk_transfer_fn bulk_transfer;
} LibUSBAPI;

enum {
    LIBUSB_ERROR_ACCESS = -3,
    LIBUSB_ERROR_NO_DEVICE = -4,
    LIBUSB_ERROR_BUSY = -6,
    LIBUSB_ERROR_TIMEOUT = -7
};

enum {
    DJI_VENDOR_ID = 0x2CA3,
    DJI_AIRCRAFT_PRODUCT_ID = 0x0020,
    DJI_CONTROLLER_PRODUCT_ID = 0x1021,
    DUML_SOF = 0x55,
    DUML_PROTOCOL_VERSION = 0x04,
    DUML_PROTOCOL_MASK = 0xFC,
    DUML_MINIMUM_FRAME_LENGTH = 13,
    DUML_MAXIMUM_FRAME_LENGTH = 1023,
    DUML_REQUEST_WITH_ACK = 0x40,
    /* A response has packet-type bit 7 set and no acknowledgement request.
     * Live Mini 5 Pro/RC 2 GET replies use exactly 0x80. */
    DUML_ACK_RESPONSE = 0x80,
    DUML_FC_AREA_GET_CODE = 0x04,
    USB_WRITE_TIMEOUT_MS = 1000,
    USB_READ_SLICE_MS = 250,
    USB_QUERY_TIMEOUT_MS = 3000,
    USB_READ_CHUNK_LENGTH = 4096,
    USB_PENDING_CAPACITY = 8192
};

typedef enum FixedQueryKind {
    FIXED_QUERY_FC_AREA = 0,
    FIXED_QUERY_SKY_COUNTRY = 1,
    FIXED_QUERY_GROUND_COUNTRY = 2,
    FIXED_QUERY_FRANCE_EID_STATUS = 3
} FixedQueryKind;

typedef struct FixedQuerySpec {
    uint16_t product_id;
    int interface_number;
    uint8_t endpoint_out;
    uint8_t endpoint_in;
    uint8_t source;
    uint8_t target;
    uint8_t command_set;
    uint8_t command_id;
    const uint8_t *request_payload;
    size_t request_payload_length;
} FixedQuerySpec;

static const uint8_t kFCAreaGetPayload[9] = {
    DUML_FC_AREA_GET_CODE, 0, 0, 0, 0, 0, 0, 0, 0
};
static const uint8_t kFranceEIDGetPayload[1] = {0x02};

static pthread_mutex_t kUSBQueryLock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic uint_fast32_t kSequenceCounter = 1;

static uint16_t read_u16_le(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static uint64_t read_u64_le(const uint8_t *bytes) {
    uint64_t value = 0;
    for (size_t index = 0; index < 8; index += 1) {
        value |= (uint64_t)bytes[index] << (index * 8);
    }
    return value;
}

static void write_u16_le(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)(value & 0xFF);
    bytes[1] = (uint8_t)(value >> 8);
}

static uint8_t duml_crc8(const uint8_t *bytes, size_t length) {
    uint8_t crc = 0x77;
    for (size_t index = 0; index < length; index += 1) {
        crc ^= bytes[index];
        for (unsigned int bit = 0; bit < 8; bit += 1) {
            crc = (crc & 1U) != 0U
                ? (uint8_t)((crc >> 1) ^ 0x8C)
                : (uint8_t)(crc >> 1);
        }
    }
    return crc;
}

static uint16_t duml_crc16(const uint8_t *bytes, size_t length) {
    uint16_t crc = 0x3692;
    for (size_t index = 0; index < length; index += 1) {
        crc ^= bytes[index];
        for (unsigned int bit = 0; bit < 8; bit += 1) {
            crc = (crc & 1U) != 0U
                ? (uint16_t)((crc >> 1) ^ 0x8408)
                : (uint16_t)(crc >> 1);
        }
    }
    return crc;
}

static int fixed_query_spec(FixedQueryKind kind, FixedQuerySpec *out_spec) {
    if (out_spec == NULL) {
        return 0;
    }

    memset(out_spec, 0, sizeof(*out_spec));
    switch (kind) {
        case FIXED_QUERY_FC_AREA:
            *out_spec = (FixedQuerySpec) {
                .product_id = DJI_AIRCRAFT_PRODUCT_ID,
                .interface_number = 4,
                .endpoint_out = 0x04,
                .endpoint_in = 0x85,
                .source = 0x0A,
                .target = 0x03,
                .command_set = 0x03,
                .command_id = 0xAF,
                .request_payload = kFCAreaGetPayload,
                .request_payload_length = sizeof(kFCAreaGetPayload)
            };
            return 1;
        case FIXED_QUERY_SKY_COUNTRY:
            *out_spec = (FixedQuerySpec) {
                .product_id = DJI_AIRCRAFT_PRODUCT_ID,
                .interface_number = 4,
                .endpoint_out = 0x04,
                .endpoint_in = 0x85,
                .source = 0x0A,
                .target = 0x09,
                .command_set = 0x07,
                .command_id = 0x19,
                .request_payload = NULL,
                .request_payload_length = 0
            };
            return 1;
        case FIXED_QUERY_GROUND_COUNTRY:
            *out_spec = (FixedQuerySpec) {
                .product_id = DJI_CONTROLLER_PRODUCT_ID,
                .interface_number = 0,
                .endpoint_out = 0x01,
                .endpoint_in = 0x81,
                .source = 0xAA,
                .target = 0x0E,
                .command_set = 0x07,
                .command_id = 0x19,
                .request_payload = NULL,
                .request_payload_length = 0
            };
            return 1;
        case FIXED_QUERY_FRANCE_EID_STATUS:
            *out_spec = (FixedQuerySpec) {
                .product_id = DJI_AIRCRAFT_PRODUCT_ID,
                .interface_number = 4,
                .endpoint_out = 0x04,
                .endpoint_in = 0x85,
                .source = 0x0A,
                .target = 0x03,
                .command_set = 0x03,
                .command_id = 0x77,
                .request_payload = kFranceEIDGetPayload,
                .request_payload_length = sizeof(kFranceEIDGetPayload)
            };
            return 1;
    }
    return 0;
}

static size_t build_frame(
    uint8_t source,
    uint8_t target,
    uint16_t sequence,
    uint8_t command_type,
    uint8_t command_set,
    uint8_t command_id,
    const uint8_t *payload,
    size_t payload_length,
    uint8_t *output,
    size_t output_capacity
) {
    const size_t frame_length = DUML_MINIMUM_FRAME_LENGTH + payload_length;
    if (output == NULL || frame_length > DUML_MAXIMUM_FRAME_LENGTH ||
        frame_length > output_capacity || (payload_length > 0 && payload == NULL)) {
        return 0;
    }

    output[0] = DUML_SOF;
    output[1] = (uint8_t)(frame_length & 0xFF);
    output[2] = (uint8_t)(((frame_length >> 8) & 0x03) | DUML_PROTOCOL_VERSION);
    output[3] = duml_crc8(output, 3);
    output[4] = source;
    output[5] = target;
    write_u16_le(output + 6, sequence);
    output[8] = command_type;
    output[9] = command_set;
    output[10] = command_id;
    if (payload_length > 0) {
        memcpy(output + 11, payload, payload_length);
    }
    write_u16_le(output + frame_length - 2, duml_crc16(output, frame_length - 2));
    return frame_length;
}

static size_t build_fixed_request(
    FixedQueryKind kind,
    uint16_t sequence,
    uint8_t *output,
    size_t output_capacity
) {
    FixedQuerySpec spec;
    if (!fixed_query_spec(kind, &spec)) {
        return 0;
    }
    return build_frame(
        spec.source,
        spec.target,
        sequence,
        DUML_REQUEST_WITH_ACK,
        spec.command_set,
        spec.command_id,
        spec.request_payload,
        spec.request_payload_length,
        output,
        output_capacity
    );
}

static int validate_fixed_response(
    FixedQueryKind kind,
    uint16_t sequence,
    const uint8_t *frame,
    size_t frame_length,
    const uint8_t **out_payload,
    size_t *out_payload_length
) {
    FixedQuerySpec spec;
    if (frame == NULL || out_payload == NULL || out_payload_length == NULL ||
        !fixed_query_spec(kind, &spec) || frame_length < DUML_MINIMUM_FRAME_LENGTH ||
        frame_length > DUML_MAXIMUM_FRAME_LENGTH) {
        return 0;
    }

    const uint16_t declared_length =
        (uint16_t)(read_u16_le(frame + 1) & 0x03FF);
    if (frame[0] != DUML_SOF ||
        (frame[2] & DUML_PROTOCOL_MASK) != DUML_PROTOCOL_VERSION ||
        declared_length != frame_length ||
        duml_crc8(frame, 3) != frame[3] ||
        duml_crc16(frame, frame_length - 2) != read_u16_le(frame + frame_length - 2)) {
        return 0;
    }

    if (frame[4] != spec.target || frame[5] != spec.source ||
        read_u16_le(frame + 6) != sequence || frame[8] != DUML_ACK_RESPONSE ||
        frame[9] != spec.command_set || frame[10] != spec.command_id) {
        return 0;
    }

    *out_payload = frame + 11;
    *out_payload_length = frame_length - DUML_MINIMUM_FRAME_LENGTH;
    return 1;
}

static void repair_frame_checksums(uint8_t *frame, size_t frame_length) {
    frame[3] = duml_crc8(frame, 3);
    write_u16_le(frame + frame_length - 2, duml_crc16(frame, frame_length - 2));
}

static uint64_t monotonic_milliseconds(void) {
    struct timespec time_value;
    if (clock_gettime(CLOCK_MONOTONIC, &time_value) != 0) {
        return 0;
    }
    return (uint64_t)time_value.tv_sec * 1000U +
        (uint64_t)time_value.tv_nsec / 1000000U;
}

static uint16_t next_sequence(void) {
    const uint_fast32_t counter = atomic_fetch_add_explicit(
        &kSequenceCounter,
        1,
        memory_order_relaxed
    );
    struct timespec time_value = {0, 0};
    (void)clock_gettime(CLOCK_MONOTONIC, &time_value);
    const uint32_t mixed = (uint32_t)time_value.tv_nsec ^
        (uint32_t)time_value.tv_sec ^ (uint32_t)getpid() ^ (uint32_t)counter;
    return (uint16_t)(mixed == 0 ? 1 : mixed);
}

static void *open_dynamic_library(void) {
    char executable_path[PATH_MAX];
    uint32_t executable_path_size = (uint32_t)sizeof(executable_path);
    if (_NSGetExecutablePath(executable_path, &executable_path_size) == 0) {
        char *last_slash = strrchr(executable_path, '/');
        if (last_slash != NULL) {
            *last_slash = '\0';
            const char *relative_candidates[] = {
                "/../Frameworks/libusb-1.0.dylib",
                "/../Frameworks/libusb-1.0.0.dylib",
                "/../Resources/libusb-1.0.dylib",
                "/libusb-1.0.dylib"
            };
            for (size_t index = 0;
                 index < sizeof(relative_candidates) / sizeof(relative_candidates[0]);
                 index += 1) {
                char candidate[PATH_MAX];
                const int written = snprintf(
                    candidate,
                    sizeof(candidate),
                    "%s%s",
                    executable_path,
                    relative_candidates[index]
                );
                if (written > 0 && (size_t)written < sizeof(candidate)) {
                    void *library = dlopen(candidate, RTLD_NOW | RTLD_LOCAL);
                    if (library != NULL) {
                        return library;
                    }
                }
            }
        }
    }

    const char *absolute_candidates[] = {
        "/opt/homebrew/lib/libusb-1.0.dylib",
        "/opt/homebrew/lib/libusb-1.0.0.dylib",
        "/usr/local/lib/libusb-1.0.dylib",
        "/usr/local/lib/libusb-1.0.0.dylib",
        "/opt/local/lib/libusb-1.0.dylib",
        "/usr/lib/libusb-1.0.dylib"
    };
    for (size_t index = 0;
         index < sizeof(absolute_candidates) / sizeof(absolute_candidates[0]);
         index += 1) {
        void *library = dlopen(absolute_candidates[index], RTLD_NOW | RTLD_LOCAL);
        if (library != NULL) {
            return library;
        }
    }
    return NULL;
}

static int load_symbol(
    void *library,
    const char *name,
    void *out_function_pointer,
    size_t function_pointer_size
) {
    if (library == NULL || name == NULL || out_function_pointer == NULL ||
        function_pointer_size != sizeof(void *)) {
        return 0;
    }
    void *symbol = dlsym(library, name);
    if (symbol == NULL) {
        return 0;
    }
    memcpy(out_function_pointer, &symbol, sizeof(symbol));
    return 1;
}

static int load_libusb(LibUSBAPI *out_api) {
    if (out_api == NULL) {
        return 0;
    }
    memset(out_api, 0, sizeof(*out_api));
    out_api->library = open_dynamic_library();
    if (out_api->library == NULL) {
        return 0;
    }

#define LOAD_LIBUSB_SYMBOL(member, symbol_name) \
    load_symbol( \
        out_api->library, \
        symbol_name, \
        &out_api->member, \
        sizeof(out_api->member) \
    )

    const int loaded =
        LOAD_LIBUSB_SYMBOL(init, "libusb_init") &&
        LOAD_LIBUSB_SYMBOL(exit, "libusb_exit") &&
        LOAD_LIBUSB_SYMBOL(get_device_list, "libusb_get_device_list") &&
        LOAD_LIBUSB_SYMBOL(free_device_list, "libusb_free_device_list") &&
        LOAD_LIBUSB_SYMBOL(get_device_descriptor, "libusb_get_device_descriptor") &&
        LOAD_LIBUSB_SYMBOL(open_device_with_vid_pid, "libusb_open_device_with_vid_pid") &&
        LOAD_LIBUSB_SYMBOL(close, "libusb_close") &&
        LOAD_LIBUSB_SYMBOL(claim_interface, "libusb_claim_interface") &&
        LOAD_LIBUSB_SYMBOL(release_interface, "libusb_release_interface") &&
        LOAD_LIBUSB_SYMBOL(bulk_transfer, "libusb_bulk_transfer");

#undef LOAD_LIBUSB_SYMBOL

    if (!loaded) {
        dlclose(out_api->library);
        memset(out_api, 0, sizeof(*out_api));
        return 0;
    }
    return 1;
}

static void unload_libusb(LibUSBAPI *api) {
    if (api != NULL && api->library != NULL) {
        dlclose(api->library);
        memset(api, 0, sizeof(*api));
    }
}

static DJIUSBBridgeStatus status_from_libusb_error(int error) {
    switch (error) {
        case LIBUSB_ERROR_ACCESS:
            return DJIUSB_BRIDGE_STATUS_ACCESS_DENIED;
        case LIBUSB_ERROR_BUSY:
            return DJIUSB_BRIDGE_STATUS_INTERFACE_BUSY;
        case LIBUSB_ERROR_NO_DEVICE:
            return DJIUSB_BRIDGE_STATUS_DEVICE_NOT_FOUND;
        case LIBUSB_ERROR_TIMEOUT:
            return DJIUSB_BRIDGE_STATUS_TIMEOUT;
        default:
            return DJIUSB_BRIDGE_STATUS_USB_IO;
    }
}

static int device_is_present(
    const LibUSBAPI *api,
    libusb_context *context,
    uint16_t product_id,
    int *out_enumeration_error
) {
    libusb_device **devices = NULL;
    const ssize_t count = api->get_device_list(context, &devices);
    if (count < 0) {
        if (out_enumeration_error != NULL) {
            *out_enumeration_error = (int)count;
        }
        return 0;
    }

    int present = 0;
    for (ssize_t index = 0; index < count; index += 1) {
        struct libusb_device_descriptor descriptor;
        memset(&descriptor, 0, sizeof(descriptor));
        if (api->get_device_descriptor(devices[index], &descriptor) == 0 &&
            descriptor.idVendor == DJI_VENDOR_ID && descriptor.idProduct == product_id) {
            present = 1;
            break;
        }
    }
    api->free_device_list(devices, 1);
    if (out_enumeration_error != NULL) {
        *out_enumeration_error = 0;
    }
    return present;
}

static int append_and_find_response(
    FixedQueryKind kind,
    uint16_t sequence,
    uint8_t *pending,
    size_t *pending_length,
    const uint8_t *new_bytes,
    size_t new_byte_count,
    uint8_t *out_payload,
    size_t out_payload_capacity,
    size_t *out_payload_length
) {
    if (pending == NULL || pending_length == NULL || new_bytes == NULL ||
        out_payload == NULL || out_payload_length == NULL) {
        return 0;
    }

    if (*pending_length + new_byte_count > USB_PENDING_CAPACITY) {
        *pending_length = 0;
    }
    if (new_byte_count > USB_PENDING_CAPACITY) {
        new_bytes += new_byte_count - USB_PENDING_CAPACITY;
        new_byte_count = USB_PENDING_CAPACITY;
    }
    memcpy(pending + *pending_length, new_bytes, new_byte_count);
    *pending_length += new_byte_count;

    size_t cursor = 0;
    while (cursor < *pending_length) {
        while (cursor < *pending_length && pending[cursor] != DUML_SOF) {
            cursor += 1;
        }
        if (*pending_length - cursor < 3) {
            break;
        }

        const size_t declared_length =
            (size_t)(read_u16_le(pending + cursor + 1) & 0x03FF);
        if ((pending[cursor + 2] & DUML_PROTOCOL_MASK) != DUML_PROTOCOL_VERSION ||
            declared_length < DUML_MINIMUM_FRAME_LENGTH ||
            declared_length > DUML_MAXIMUM_FRAME_LENGTH) {
            cursor += 1;
            continue;
        }
        if (*pending_length - cursor < declared_length) {
            break;
        }

        const uint8_t *payload = NULL;
        size_t payload_length = 0;
        if (validate_fixed_response(
                kind,
                sequence,
                pending + cursor,
                declared_length,
                &payload,
                &payload_length
            )) {
            if (payload_length > out_payload_capacity) {
                return 0;
            }
            memcpy(out_payload, payload, payload_length);
            *out_payload_length = payload_length;
            *pending_length = 0;
            return 1;
        }

        /* A bad CRC may make its declared span untrustworthy; advance one byte
         * and resynchronize. A valid unrelated frame is harmlessly rescanned. */
        cursor += 1;
    }

    if (cursor > 0) {
        memmove(pending, pending + cursor, *pending_length - cursor);
        *pending_length -= cursor;
    }
    return 0;
}

static DJIUSBBridgeStatus perform_fixed_query(
    FixedQueryKind kind,
    uint8_t *out_payload,
    size_t out_payload_capacity,
    size_t *out_payload_length
) {
    FixedQuerySpec spec;
    if (out_payload == NULL || out_payload_length == NULL ||
        !fixed_query_spec(kind, &spec)) {
        return DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT;
    }
    *out_payload_length = 0;
    memset(out_payload, 0, out_payload_capacity);

    LibUSBAPI api;
    if (!load_libusb(&api)) {
        return DJIUSB_BRIDGE_STATUS_LIBUSB_UNAVAILABLE;
    }

    libusb_context *context = NULL;
    int result = api.init(&context);
    if (result != 0) {
        unload_libusb(&api);
        return status_from_libusb_error(result);
    }

    DJIUSBBridgeStatus status = DJIUSB_BRIDGE_STATUS_USB_IO;
    libusb_device_handle *handle = api.open_device_with_vid_pid(
        context,
        DJI_VENDOR_ID,
        spec.product_id
    );
    if (handle == NULL) {
        int enumeration_error = 0;
        const int present = device_is_present(
            &api,
            context,
            spec.product_id,
            &enumeration_error
        );
        status = enumeration_error != 0
            ? status_from_libusb_error(enumeration_error)
            : (present ? DJIUSB_BRIDGE_STATUS_ACCESS_DENIED
                       : DJIUSB_BRIDGE_STATUS_DEVICE_NOT_FOUND);
        api.exit(context);
        unload_libusb(&api);
        return status;
    }

    int interface_claimed = 0;
    result = api.claim_interface(handle, spec.interface_number);
    if (result != 0) {
        status = status_from_libusb_error(result);
        goto cleanup;
    }
    interface_claimed = 1;

    const uint16_t sequence = next_sequence();
    uint8_t request[32];
    const size_t request_length = build_fixed_request(
        kind,
        sequence,
        request,
        sizeof(request)
    );
    if (request_length == 0) {
        status = DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR;
        goto cleanup;
    }

    int transferred = 0;
    result = api.bulk_transfer(
        handle,
        spec.endpoint_out,
        request,
        (int)request_length,
        &transferred,
        USB_WRITE_TIMEOUT_MS
    );
    memset(request, 0, sizeof(request));
    if (result != 0) {
        status = status_from_libusb_error(result);
        goto cleanup;
    }
    if (transferred != (int)request_length) {
        status = DJIUSB_BRIDGE_STATUS_USB_IO;
        goto cleanup;
    }

    uint8_t pending[USB_PENDING_CAPACITY];
    uint8_t chunk[USB_READ_CHUNK_LENGTH];
    size_t pending_length = 0;
    const uint64_t start = monotonic_milliseconds();
    const uint64_t deadline = start + USB_QUERY_TIMEOUT_MS;
    while (monotonic_milliseconds() < deadline) {
        const uint64_t now = monotonic_milliseconds();
        const uint64_t remaining = deadline > now ? deadline - now : 0;
        const unsigned int read_timeout = remaining < USB_READ_SLICE_MS
            ? (unsigned int)remaining
            : USB_READ_SLICE_MS;
        if (read_timeout == 0) {
            break;
        }

        transferred = 0;
        result = api.bulk_transfer(
            handle,
            spec.endpoint_in,
            chunk,
            (int)sizeof(chunk),
            &transferred,
            read_timeout
        );
        if (result == LIBUSB_ERROR_TIMEOUT) {
            continue;
        }
        if (result != 0) {
            status = status_from_libusb_error(result);
            goto cleanup;
        }
        if (transferred <= 0) {
            continue;
        }
        if (append_and_find_response(
                kind,
                sequence,
                pending,
                &pending_length,
                chunk,
                (size_t)transferred,
                out_payload,
                out_payload_capacity,
                out_payload_length
            )) {
            status = DJIUSB_BRIDGE_STATUS_OK;
            goto cleanup;
        }
    }
    status = DJIUSB_BRIDGE_STATUS_TIMEOUT;

cleanup:
    if (interface_claimed) {
        (void)api.release_interface(handle, spec.interface_number);
    }
    api.close(handle);
    api.exit(context);
    unload_libusb(&api);
    return status;
}

static void alpha2_for_numeric(uint64_t numeric, char alpha2[3]) {
    const char *value = NULL;
    switch (numeric) {
        case 36: value = "AU"; break;
        case 156: value = "CN"; break;
        case 250: value = "FR"; break;
        case 276: value = "DE"; break;
        case 392: value = "JP"; break;
        case 702: value = "SG"; break;
        case 784: value = "AE"; break;
        case 826: value = "GB"; break;
        case 840: value = "US"; break;
        default: break;
    }
    if (value == NULL) {
        alpha2[0] = '\0';
        alpha2[1] = '\0';
        alpha2[2] = '\0';
        return;
    }
    alpha2[0] = value[0];
    alpha2[1] = value[1];
    alpha2[2] = '\0';
}

static int parse_country_payload(
    const uint8_t *payload,
    size_t payload_length,
    DJIUSBBridgeCountry *out_country
) {
    if (payload == NULL || out_country == NULL || payload_length < 4 || payload[0] != 0) {
        return 0;
    }
    const size_t offset = 1;
    if (payload[offset] < 'A' || payload[offset] > 'Z' ||
        payload[offset + 1] < 'A' || payload[offset + 1] > 'Z') {
        return 0;
    }
    /* Live 0x07/0x19 replies currently carry one zero status/prefix byte,
     * two country bytes, and a trailing zero. Accept longer reserved tails
     * only when every extra byte is zero. */
    for (size_t index = offset + 2; index < payload_length; index += 1) {
        if (payload[index] != 0) {
            return 0;
        }
    }
    out_country->alpha2[0] = (char)payload[offset];
    out_country->alpha2[1] = (char)payload[offset + 1];
    out_country->alpha2[2] = '\0';
    return 1;
}

static int parse_france_eid_payload(
    const uint8_t *payload,
    size_t payload_length,
    DJIUSBBridgeFranceEIDStatus *out_status
) {
    if (payload == NULL || out_status == NULL || payload_length < 2 || payload[0] != 0) {
        return 0;
    }
    out_status->enabled = (payload[1] & 0x01U) != 0U ? 1 : 0;
    return 1;
}

DJIUSBBridgeStatus dji_usb_bridge_get_device_presence(
    DJIUSBBridgeDevicePresence *out_presence
) {
    if (out_presence == NULL) {
        return DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_presence, 0, sizeof(*out_presence));

    LibUSBAPI api;
    if (!load_libusb(&api)) {
        return DJIUSB_BRIDGE_STATUS_LIBUSB_UNAVAILABLE;
    }

    libusb_context *context = NULL;
    const int result = api.init(&context);
    if (result != 0) {
        unload_libusb(&api);
        return status_from_libusb_error(result);
    }
    out_presence->libusb_available = 1;

    int aircraft_error = 0;
    const int aircraft_present = device_is_present(
        &api,
        context,
        DJI_AIRCRAFT_PRODUCT_ID,
        &aircraft_error
    );
    int controller_error = 0;
    const int controller_present = device_is_present(
        &api,
        context,
        DJI_CONTROLLER_PRODUCT_ID,
        &controller_error
    );
    out_presence->aircraft_present = aircraft_present ? 1 : 0;
    out_presence->controller_present = controller_present ? 1 : 0;

    api.exit(context);
    unload_libusb(&api);
    if (aircraft_error != 0) {
        return status_from_libusb_error(aircraft_error);
    }
    if (controller_error != 0) {
        return status_from_libusb_error(controller_error);
    }
    return DJIUSB_BRIDGE_STATUS_OK;
}

DJIUSBBridgeStatus dji_usb_bridge_get_aircraft_fc_area(
    DJIUSBBridgeFCArea *out_area
) {
    if (out_area == NULL) {
        return DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_area, 0, sizeof(*out_area));

    uint8_t payload[32];
    size_t payload_length = 0;
    pthread_mutex_lock(&kUSBQueryLock);
    const DJIUSBBridgeStatus status = perform_fixed_query(
        FIXED_QUERY_FC_AREA,
        payload,
        sizeof(payload),
        &payload_length
    );
    pthread_mutex_unlock(&kUSBQueryLock);
    if (status != DJIUSB_BRIDGE_STATUS_OK) {
        return status;
    }
    if (payload_length < 9 || payload[0] != DUML_FC_AREA_GET_CODE) {
        memset(payload, 0, sizeof(payload));
        return DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR;
    }

    out_area->iso_numeric = read_u64_le(payload + 1);
    alpha2_for_numeric(out_area->iso_numeric, out_area->alpha2);
    memset(payload, 0, sizeof(payload));
    return DJIUSB_BRIDGE_STATUS_OK;
}

static DJIUSBBridgeStatus get_fixed_country(
    FixedQueryKind kind,
    DJIUSBBridgeCountry *out_country
) {
    if (out_country == NULL) {
        return DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_country, 0, sizeof(*out_country));

    uint8_t payload[32];
    size_t payload_length = 0;
    pthread_mutex_lock(&kUSBQueryLock);
    const DJIUSBBridgeStatus status = perform_fixed_query(
        kind,
        payload,
        sizeof(payload),
        &payload_length
    );
    pthread_mutex_unlock(&kUSBQueryLock);
    if (status != DJIUSB_BRIDGE_STATUS_OK) {
        return status;
    }
    if (!parse_country_payload(payload, payload_length, out_country)) {
        memset(payload, 0, sizeof(payload));
        return DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR;
    }
    memset(payload, 0, sizeof(payload));
    return DJIUSB_BRIDGE_STATUS_OK;
}

DJIUSBBridgeStatus dji_usb_bridge_get_sky_country(
    DJIUSBBridgeCountry *out_country
) {
    return get_fixed_country(FIXED_QUERY_SKY_COUNTRY, out_country);
}

DJIUSBBridgeStatus dji_usb_bridge_get_ground_country(
    DJIUSBBridgeCountry *out_country
) {
    return get_fixed_country(FIXED_QUERY_GROUND_COUNTRY, out_country);
}

DJIUSBBridgeStatus dji_usb_bridge_get_france_eid_status(
    DJIUSBBridgeFranceEIDStatus *out_status
) {
    if (out_status == NULL) {
        return DJIUSB_BRIDGE_STATUS_INVALID_ARGUMENT;
    }
    memset(out_status, 0, sizeof(*out_status));

    uint8_t payload[32];
    size_t payload_length = 0;
    pthread_mutex_lock(&kUSBQueryLock);
    const DJIUSBBridgeStatus status = perform_fixed_query(
        FIXED_QUERY_FRANCE_EID_STATUS,
        payload,
        sizeof(payload),
        &payload_length
    );
    pthread_mutex_unlock(&kUSBQueryLock);
    if (status != DJIUSB_BRIDGE_STATUS_OK) {
        return status;
    }
    if (!parse_france_eid_payload(payload, payload_length, out_status)) {
        memset(payload, 0, sizeof(payload));
        return DJIUSB_BRIDGE_STATUS_PROTOCOL_ERROR;
    }
    memset(payload, 0, sizeof(payload));
    return DJIUSB_BRIDGE_STATUS_OK;
}

uint8_t dji_usb_bridge_protocol_self_test(void) {
    static const uint8_t expected_requests[4][22] = {
        {
            0x55, 0x16, 0x04, 0xFC, 0x0A, 0x03, 0x34, 0x12,
            0x40, 0x03, 0xAF, 0x04, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0xD5, 0x61
        },
        {
            0x55, 0x0D, 0x04, 0x33, 0x0A, 0x09, 0x34, 0x12,
            0x40, 0x07, 0x19, 0xEE, 0xCD
        },
        {
            0x55, 0x0D, 0x04, 0x33, 0xAA, 0x0E, 0x34, 0x12,
            0x40, 0x07, 0x19, 0xA1, 0x34
        },
        {
            0x55, 0x0E, 0x04, 0x66, 0x0A, 0x03, 0x34, 0x12,
            0x40, 0x03, 0x77, 0x02, 0x80, 0xCD
        }
    };
    static const size_t expected_request_lengths[4] = {22, 13, 13, 14};
    static const uint8_t fc_response[] = {
        0x55, 0x16, 0x04, 0xFC, 0x03, 0x0A, 0x34, 0x12,
        0x80, 0x03, 0xAF, 0x04, 0x9C, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0xF4
    };
    static const uint8_t sky_response[] = {
        0x55, 0x11, 0x04, 0x92, 0x09, 0x0A, 0x34, 0x12,
        0x80, 0x07, 0x19, 0x00, 0x43, 0x4E, 0x00, 0xA0, 0xDB
    };
    static const uint8_t ground_response[] = {
        0x55, 0x11, 0x04, 0x92, 0x0E, 0xAA, 0x34, 0x12,
        0x80, 0x07, 0x19, 0x00, 0x43, 0x4E, 0x00, 0x05, 0x75
    };
    static const uint8_t france_eid_response[] = {
        0x55, 0x0F, 0x04, 0xA2, 0x03, 0x0A, 0x34, 0x12,
        0x80, 0x03, 0x77, 0x00, 0x01, 0xFB, 0xB5
    };

    if (duml_crc8(expected_requests[0], 3) != 0xFC ||
        duml_crc16(expected_requests[0], 20) != 0x61D5) {
        return 0;
    }

    for (int kind = FIXED_QUERY_FC_AREA; kind <= FIXED_QUERY_FRANCE_EID_STATUS; kind += 1) {
        uint8_t request[32];
        const size_t request_length = build_fixed_request(
            (FixedQueryKind)kind,
            0x1234,
            request,
            sizeof(request)
        );
        if (request_length != expected_request_lengths[kind] ||
            memcmp(request, expected_requests[kind], request_length) != 0) {
            return 0;
        }
    }

    const uint8_t *responses[] = {
        fc_response, sky_response, ground_response, france_eid_response
    };
    const size_t response_lengths[] = {
        sizeof(fc_response), sizeof(sky_response), sizeof(ground_response),
        sizeof(france_eid_response)
    };
    for (int kind = FIXED_QUERY_FC_AREA; kind <= FIXED_QUERY_FRANCE_EID_STATUS; kind += 1) {
        const uint8_t *payload = NULL;
        size_t payload_length = 0;
        if (!validate_fixed_response(
                (FixedQueryKind)kind,
                0x1234,
                responses[kind],
                response_lengths[kind],
                &payload,
                &payload_length
            )) {
            return 0;
        }
        if ((kind == FIXED_QUERY_FC_AREA &&
             (payload_length != 9 || read_u64_le(payload + 1) != 156)) ||
            (kind == FIXED_QUERY_SKY_COUNTRY && payload_length != 4) ||
            (kind == FIXED_QUERY_GROUND_COUNTRY && payload_length != 4) ||
            (kind == FIXED_QUERY_FRANCE_EID_STATUS && payload_length < 2)) {
            return 0;
        }
    }

    DJIUSBBridgeCountry country;
    if (!parse_country_payload(sky_response + 11, 4, &country) ||
        strcmp(country.alpha2, "CN") != 0 ||
        !parse_country_payload(ground_response + 11, 4, &country) ||
        strcmp(country.alpha2, "CN") != 0) {
        return 0;
    }
    static const uint8_t short_country[] = {0x43, 0x4E};
    static const uint8_t missing_prefix[] = {0x43, 0x4E, 0x00, 0x00};
    static const uint8_t nonzero_tail[] = {0x00, 0x43, 0x4E, 0x01};
    if (parse_country_payload(short_country, sizeof(short_country), &country) ||
        parse_country_payload(missing_prefix, sizeof(missing_prefix), &country) ||
        parse_country_payload(nonzero_tail, sizeof(nonzero_tail), &country)) {
        return 0;
    }
    DJIUSBBridgeFranceEIDStatus france_eid_status;
    if (!parse_france_eid_payload(
            france_eid_response + 11,
            sizeof(france_eid_response) - DUML_MINIMUM_FRAME_LENGTH,
            &france_eid_status
        ) || france_eid_status.enabled != 1) {
        return 0;
    }

    uint8_t rejected[sizeof(fc_response)];
    const uint8_t *payload = NULL;
    size_t payload_length = 0;

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[1] -= 1;
    repair_frame_checksums(rejected, sizeof(rejected));
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[4] = 0x09;
    repair_frame_checksums(rejected, sizeof(rejected));
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[6] ^= 1;
    repair_frame_checksums(rejected, sizeof(rejected));
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[9] ^= 1;
    repair_frame_checksums(rejected, sizeof(rejected));
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[10] ^= 1;
    repair_frame_checksums(rejected, sizeof(rejected));
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }

    memcpy(rejected, fc_response, sizeof(rejected));
    rejected[sizeof(rejected) - 1] ^= 1;
    if (validate_fixed_response(
            FIXED_QUERY_FC_AREA, 0x1234, rejected, sizeof(rejected),
            &payload, &payload_length
        )) {
        return 0;
    }
    return 1;
}
