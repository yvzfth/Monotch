#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#define MONOTCH_FAN_DAEMON_SOCKET "/var/run/fatihyavuz.Monotch.FanDaemon.v4.sock"

enum {
    kSMCUserClientOpen = 0,
    kSMCHandleYPCEvent = 2,
    kSMCReadBytes = 5,
    kSMCWriteBytes = 6,
    kSMCReadKeyInfo = 9
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
    uint8_t reserved[3];
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCKeyData;

static uint32_t smc_key(const char *key) {
    uint32_t value = 0;
    for (int i = 0; i < 4 && key[i] != '\0'; i++) {
        value = (value << 8) | (uint8_t)key[i];
    }
    return value;
}

static io_connect_t smc_open(void) {
    const char *serviceNames[] = {"AppleSMCKeysEndpoint", "AppleSMC"};

    for (size_t index = 0; index < sizeof(serviceNames) / sizeof(serviceNames[0]); index++) {
        io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(serviceNames[index]));
        if (service == IO_OBJECT_NULL) {
            continue;
        }

        io_connect_t connection = IO_OBJECT_NULL;
        kern_return_t result = IOServiceOpen(service, mach_task_self(), kSMCUserClientOpen, &connection);
        IOObjectRelease(service);

        if (result == KERN_SUCCESS && connection != IO_OBJECT_NULL) {
            return connection;
        }
    }

    return IO_OBJECT_NULL;
}

static kern_return_t smc_call_raw(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    size_t inputSize = sizeof(SMCKeyData);
    size_t outputSize = sizeof(SMCKeyData);

    return IOConnectCallStructMethod(
        connection,
        kSMCHandleYPCEvent,
        input,
        inputSize,
        output,
        &outputSize
    );
}

static int smc_call(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    kern_return_t result = smc_call_raw(connection, input, output);
    return result == KERN_SUCCESS && (output->result == 0 || output->result == 0x87);
}

static void print_key_probe(io_connect_t connection, const char *key) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = smc_key(key);
    input.data8 = kSMCReadKeyInfo;

    kern_return_t keyInfoResult = smc_call_raw(connection, &input, &output);
    printf(
        "%s info kern=0x%08x smc=%u status=%u size=%u type=0x%08x attr=%u\n",
        key,
        keyInfoResult,
        output.result,
        output.status,
        output.keyInfo.dataSize,
        output.keyInfo.dataType,
        output.keyInfo.dataAttributes
    );

    if (keyInfoResult != KERN_SUCCESS || output.result != 0 || output.keyInfo.dataSize > 32) {
        return;
    }

    SMCKeyInfoData info = output.keyInfo;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = smc_key(key);
    input.keyInfo = info;
    input.data8 = kSMCReadBytes;

    kern_return_t readResult = smc_call_raw(connection, &input, &output);
    printf(
        "%s read kern=0x%08x smc=%u status=%u bytes=",
        key,
        readResult,
        output.result,
        output.status
    );

    uint32_t size = info.dataSize;
    if (size > 8) {
        size = 8;
    }

    for (uint32_t index = 0; index < size; index++) {
        printf("%02x", output.bytes[index]);
    }

    printf("\n");
}

static int smc_write_number(io_connect_t connection, const char *key, double value);

static void print_write_probe(io_connect_t connection, const char *key, double value) {
    int success = smc_write_number(connection, key, value);
    printf("%s write %.0f success=%d\n", key, value, success);
}

static int smc_read_key_info(io_connect_t connection, const char *key, SMCKeyInfoData *info) {
    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = smc_key(key);
    input.data8 = kSMCReadKeyInfo;

    if (!smc_call(connection, &input, &output)) {
        return 0;
    }

    *info = output.keyInfo;
    return 1;
}

static int smc_read(io_connect_t connection, const char *key, uint8_t *bytes, uint32_t *size) {
    SMCKeyInfoData info;
    if (!smc_read_key_info(connection, key, &info)) {
        return 0;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = smc_key(key);
    input.keyInfo = info;
    input.data8 = kSMCReadBytes;

    if (!smc_call(connection, &input, &output)) {
        return 0;
    }

    uint32_t copySize = info.dataSize;
    if (copySize > 32) {
        copySize = 32;
    }

    memcpy(bytes, output.bytes, copySize);
    *size = copySize;
    return 1;
}

static int smc_write(io_connect_t connection, const char *key, const uint8_t *bytes, uint32_t size) {
    SMCKeyInfoData info;
    if (!smc_read_key_info(connection, key, &info)) {
        return 0;
    }

    if (size > 32) {
        return 0;
    }

    SMCKeyData input;
    SMCKeyData output;
    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));

    input.key = smc_key(key);
    input.keyInfo = info;
    input.keyInfo.dataSize = size;
    input.data8 = kSMCWriteBytes;
    memcpy(input.bytes, bytes, size);

    return smc_call(connection, &input, &output);
}

static int smc_read_uint8(io_connect_t connection, const char *key, uint8_t *value) {
    uint8_t bytes[32];
    uint32_t size = 0;
    if (!smc_read(connection, key, bytes, &size) || size < 1) {
        return 0;
    }

    *value = bytes[0];
    return 1;
}

static int smc_write_uint16(io_connect_t connection, const char *key, uint16_t value) {
    uint8_t bytes[2] = {(uint8_t)(value >> 8), (uint8_t)(value & 0xff)};
    return smc_write(connection, key, bytes, 2);
}

static int smc_write_uint8(io_connect_t connection, const char *key, uint8_t value) {
    return smc_write(connection, key, &value, 1);
}

static int smc_key_available(io_connect_t connection, const char *key) {
    SMCKeyInfoData info;
    return smc_read_key_info(connection, key, &info);
}

static int smc_read_number(io_connect_t connection, const char *key, double *value) {
    SMCKeyInfoData info;
    if (!smc_read_key_info(connection, key, &info)) {
        return 0;
    }

    uint8_t bytes[32];
    uint32_t size = 0;
    if (!smc_read(connection, key, bytes, &size) || size < 2) {
        return 0;
    }

    if (info.dataType == smc_key("fpe2")) {
        uint16_t raw = ((uint16_t)bytes[0] << 8) | bytes[1];
        *value = (double)raw / 4.0;
        return 1;
    }

    if (info.dataType == smc_key("flt ") && size >= 4) {
        float floatValue = 0;
        memcpy(&floatValue, bytes, sizeof(floatValue));
        if (!isfinite(floatValue) || floatValue < 0) {
            return 0;
        }

        *value = (double)floatValue;
        return 1;
    }

    return 0;
}

static int smc_write_number(io_connect_t connection, const char *key, double value) {
    SMCKeyInfoData info;
    if (!smc_read_key_info(connection, key, &info)) {
        return 0;
    }

    if (value < 0) {
        value = 0;
    }

    if (info.dataType == smc_key("fpe2")) {
        if (value > 16383.75) {
            value = 16383.75;
        }

        uint16_t raw = (uint16_t)(value * 4.0);
        return smc_write_uint16(connection, key, raw);
    }

    if (info.dataType == smc_key("flt ")) {
        float floatValue = (float)value;
        uint8_t bytes[4];
        memcpy(bytes, &floatValue, sizeof(bytes));
        return smc_write(connection, key, bytes, 4);
    }

    return 0;
}

static int fan_count(io_connect_t connection) {
    uint8_t explicitCount = 0;
    if (smc_read_uint8(connection, "FNum", &explicitCount) && explicitCount > 0) {
        return explicitCount > 8 ? 8 : explicitCount;
    }

    for (int index = 7; index >= 0; index--) {
        char key[5];
        double value = 0;
        snprintf(key, sizeof(key), "F%dAc", index);
        if (smc_read_number(connection, key, &value)) {
            return index + 1;
        }
        snprintf(key, sizeof(key), "F%dMx", index);
        if (smc_read_number(connection, key, &value)) {
            return index + 1;
        }
    }

    return 0;
}

static int fan_mode_key(io_connect_t connection, int index, char *key, size_t size) {
    snprintf(key, size, "F%dMd", index);
    if (smc_key_available(connection, key)) {
        return 1;
    }

    snprintf(key, size, "F%dmd", index);
    if (smc_key_available(connection, key)) {
        return 1;
    }

    key[0] = '\0';
    return 0;
}

static double fan_maximum_target(io_connect_t connection, int index) {
    char key[5];
    double target = 0;
    snprintf(key, sizeof(key), "F%dMx", index);
    if (!smc_read_number(connection, key, &target) || target <= 0) {
        target = 6200;
    }

    return target;
}

static double fan_minimum_target(io_connect_t connection, int index, double maximum) {
    char key[5];
    double target = 0;
    snprintf(key, sizeof(key), "F%dMn", index);
    if (!smc_read_number(connection, key, &target) || target <= 0 || target > maximum) {
        target = maximum * 0.28;
    }

    return target;
}

static double fan_target_for_mode(io_connect_t connection, int index, const char *mode) {
    double maximum = fan_maximum_target(connection, index);
    double minimum = fan_minimum_target(connection, index, maximum);

    if (strcmp(mode, "silent") == 0) {
        return minimum;
    }

    if (strcmp(mode, "balanced") == 0) {
        double halfMaximum = maximum * 0.50;
        return halfMaximum > minimum ? halfMaximum : minimum;
    }

    if (strcmp(mode, "performance") == 0) {
        return minimum + ((maximum - minimum) * 0.70);
    }

    return maximum;
}

static int enable_manual_mode(io_connect_t connection, int index, const char *modeKey) {
    if (smc_write_uint8(connection, modeKey, 1)) {
        return 1;
    }

    if (!smc_key_available(connection, "Ftst")) {
        fprintf(stderr, "Fan %d manual mode denied and Ftst is unavailable.\n", index);
        return 0;
    }

    if (!smc_write_uint8(connection, "Ftst", 1)) {
        fprintf(stderr, "Fan %d manual mode denied and Ftst write failed.\n", index);
        return 0;
    }

    usleep(500000);

    for (int attempt = 0; attempt < 100; attempt++) {
        if (smc_write_uint8(connection, modeKey, 1)) {
            return 1;
        }

        usleep(100000);
    }

    fprintf(stderr, "Fan %d manual mode timed out after Ftst unlock.\n", index);
    return 0;
}

static int set_auto(io_connect_t connection) {
    int count = fan_count(connection);
    int usedModernKeys = 0;
    int modeOk = 1;

    for (int index = 0; index < count; index++) {
        char modeKey[6];
        if (!fan_mode_key(connection, index, modeKey, sizeof(modeKey))) {
            continue;
        }

        usedModernKeys = 1;
        modeOk = smc_write_uint8(connection, modeKey, 0) && modeOk;
    }

    if (usedModernKeys) {
        if (smc_key_available(connection, "Ftst")) {
            (void)smc_write_uint8(connection, "Ftst", 0);
        }

        return modeOk;
    }

    return smc_write_uint16(connection, "FS!", 0);
}

static int set_manual_mode(io_connect_t connection, const char *mode) {
    int count = fan_count(connection);
    if (count <= 0) {
        fprintf(stderr, "No fan keys are readable.\n");
        return 0;
    }

    int usedModernKeys = 0;
    int modernOk = 1;
    for (int index = 0; index < count; index++) {
        char modeKey[6];
        if (!fan_mode_key(connection, index, modeKey, sizeof(modeKey))) {
            continue;
        }

        usedModernKeys = 1;
        char targetKey[5];
        snprintf(targetKey, sizeof(targetKey), "F%dTg", index);

        int modeOk = enable_manual_mode(connection, index, modeKey);
        int targetOk = smc_write_number(connection, targetKey, fan_target_for_mode(connection, index, mode));
        modernOk = modeOk && targetOk && modernOk;
    }

    if (usedModernKeys) {
        return modernOk;
    }

    uint16_t mask = 0;
    for (int index = 0; index < count; index++) {
        mask |= (uint16_t)(1u << index);
    }

    int targetsOk = 1;
    for (int index = 0; index < count; index++) {
        char key[5];
        snprintf(key, sizeof(key), "F%dTg", index);
        targetsOk = smc_write_number(connection, key, fan_target_for_mode(connection, index, mode)) && targetsOk;
    }

    int modeOk = smc_write_uint16(connection, "FS!", mask);

    for (int index = 0; index < count; index++) {
        char key[5];
        snprintf(key, sizeof(key), "F%dTg", index);
        targetsOk = smc_write_number(connection, key, fan_target_for_mode(connection, index, mode)) && targetsOk;
    }

    return targetsOk && modeOk;
}

static int set_max(io_connect_t connection) {
    return set_manual_mode(connection, "max");
}

static int set_balanced(io_connect_t connection) {
    return set_manual_mode(connection, "balanced");
}

static int can_write_current_targets(io_connect_t connection) {
    int count = fan_count(connection);
    if (count <= 0) {
        return 0;
    }

    int tested = 0;
    for (int index = 0; index < count; index++) {
        char key[5];
        double currentTarget = 0;
        snprintf(key, sizeof(key), "F%dTg", index);
        if (!smc_read_number(connection, key, &currentTarget)) {
            continue;
        }

        tested = 1;
        if (!smc_write_number(connection, key, currentTarget)) {
            return 0;
        }
    }

    return tested;
}

static void write_reply(int client, const char *reply) {
    (void)write(client, reply, strlen(reply));
}

static void trim_command(char *command) {
    size_t length = strlen(command);
    while (length > 0 && (command[length - 1] == '\n' || command[length - 1] == '\r' || command[length - 1] == ' ' || command[length - 1] == '\t')) {
        command[length - 1] = '\0';
        length--;
    }
}

static void handle_client(int client, io_connect_t *daemonConnection) {
    uid_t uid = 0;
    gid_t gid = 0;
    if (getpeereid(client, &uid, &gid) != 0 || uid < 500) {
        write_reply(client, "unauthorized\n");
        return;
    }

    char command[64];
    memset(command, 0, sizeof(command));
    ssize_t received = read(client, command, sizeof(command) - 1);
    if (received <= 0) {
        write_reply(client, "unavailable\n");
        return;
    }

    trim_command(command);

    if (*daemonConnection == IO_OBJECT_NULL) {
        *daemonConnection = smc_open();
    }

    if (*daemonConnection == IO_OBJECT_NULL) {
        write_reply(client, "unavailable\n");
        return;
    }

    int success = 0;
    if (strcmp(command, "auto") == 0) {
        success = set_auto(*daemonConnection);
    } else if (strcmp(command, "silent") == 0) {
        success = set_manual_mode(*daemonConnection, "silent");
    } else if (strcmp(command, "balanced") == 0) {
        success = set_balanced(*daemonConnection);
    } else if (strcmp(command, "performance") == 0) {
        success = set_manual_mode(*daemonConnection, "performance");
    } else if (strcmp(command, "max") == 0) {
        success = set_max(*daemonConnection);
    } else if (strcmp(command, "can-write") == 0) {
        success = can_write_current_targets(*daemonConnection);
    } else if (strcmp(command, "version") == 0) {
        write_reply(client, "v4\n");
        return;
    } else {
        write_reply(client, "unknown\n");
        return;
    }

    write_reply(client, success ? "ok\n" : "denied\n");
}

static int run_daemon(void) {
    signal(SIGPIPE, SIG_IGN);
    unlink(MONOTCH_FAN_DAEMON_SOCKET);

    int server = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server < 0) {
        return 70;
    }

    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, MONOTCH_FAN_DAEMON_SOCKET, sizeof(address.sun_path));

    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(server);
        return 71;
    }

    chmod(MONOTCH_FAN_DAEMON_SOCKET, 0666);

    if (listen(server, 8) != 0) {
        close(server);
        unlink(MONOTCH_FAN_DAEMON_SOCKET);
        return 72;
    }

    io_connect_t daemonConnection = smc_open();

    for (;;) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }

        handle_client(client, &daemonConnection);
        close(client);
    }

    if (daemonConnection != IO_OBJECT_NULL) {
        IOServiceClose(daemonConnection);
    }

    close(server);
    unlink(MONOTCH_FAN_DAEMON_SOCKET);
    return 0;
}

int main(int argc, const char *argv[]) {
    if (argc == 1) {
        return run_daemon();
    }

    if (argc != 2) {
        fprintf(stderr, "Usage: MonotchFanTool auto|silent|balanced|performance|max|probe|maxprobe\n");
        return 64;
    }

    io_connect_t connection = smc_open();
    if (connection == IO_OBJECT_NULL) {
        fprintf(stderr, "Could not open AppleSMC.\n");
        return 69;
    }

    int success = 0;
    if (strcmp(argv[1], "probe") == 0) {
        print_key_probe(connection, "FNum");
        print_key_probe(connection, "F0Ac");
        print_key_probe(connection, "F0Mx");
        print_key_probe(connection, "F0Tg");
        print_key_probe(connection, "F0Md");
        print_key_probe(connection, "F0md");
        print_key_probe(connection, "F1Ac");
        print_key_probe(connection, "F1Mx");
        print_key_probe(connection, "F1Tg");
        print_key_probe(connection, "F1Md");
        print_key_probe(connection, "F1md");
        print_key_probe(connection, "Ftst");
        print_key_probe(connection, "FS!");
        IOServiceClose(connection);
        return 0;
    } else if (strcmp(argv[1], "maxprobe") == 0) {
        double target = 0;
        if (!smc_read_number(connection, "F0Mx", &target) || target <= 0) {
            target = 6200;
        }
        print_write_probe(connection, "F0Tg", target);

        if (!smc_read_number(connection, "F1Mx", &target) || target <= 0) {
            target = 6200;
        }
        print_write_probe(connection, "F1Tg", target);

        printf("FS! write success=%d\n", smc_write_uint16(connection, "FS!", 3));
        IOServiceClose(connection);
        return 0;
    } else if (strcmp(argv[1], "auto") == 0) {
        success = set_auto(connection);
    } else if (strcmp(argv[1], "silent") == 0) {
        success = set_manual_mode(connection, "silent");
    } else if (strcmp(argv[1], "balanced") == 0) {
        success = set_balanced(connection);
    } else if (strcmp(argv[1], "performance") == 0) {
        success = set_manual_mode(connection, "performance");
    } else if (strcmp(argv[1], "max") == 0) {
        success = set_max(connection);
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        IOServiceClose(connection);
        return 64;
    }

    IOServiceClose(connection);

    if (!success) {
        fprintf(stderr, "SMC write denied or failed.\n");
        return 77;
    }

    return 0;
}
