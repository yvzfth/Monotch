// MonotchMediaBridge — loaded into /usr/bin/perl via DynaLoader so MediaRemote
// grants now-playing access (macOS 15.4+ restricts it to Apple platform binaries).
// Modes (env MONOTCH_MEDIA_MODE):
//   stream  — emit line-delimited JSON now-playing state on change + heartbeat
//   command — send one playback command (env MONOTCH_MEDIA_COMMAND) and exit

#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

typedef void (*MRGetNowPlayingInfoFunc)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*MRRegisterForNowPlayingNotificationsFunc)(dispatch_queue_t queue);
typedef void (*MRGetNowPlayingApplicationPIDFunc)(dispatch_queue_t queue, void (^handler)(int pid));
typedef void (*MRGetNowPlayingClientFunc)(dispatch_queue_t queue, void (^handler)(id client));
typedef NSString *(*MRNowPlayingClientGetBundleIdentifierFunc)(id client);
typedef NSString *(*MRNowPlayingClientGetParentAppBundleIdentifierFunc)(id client);
typedef Boolean (*MRSendCommandFunc)(int command, CFDictionaryRef options);
typedef void (*MRSetElapsedTimeFunc)(double elapsedTime);

enum {
    MRCommandPlay = 0,
    MRCommandPause = 1,
    MRCommandTogglePlayPause = 2,
    MRCommandNextTrack = 4,
    MRCommandPreviousTrack = 5
};

static MRGetNowPlayingInfoFunc gGetNowPlayingInfo;
static MRRegisterForNowPlayingNotificationsFunc gRegisterNotifications;
static MRGetNowPlayingApplicationPIDFunc gGetNowPlayingPID;
static MRGetNowPlayingClientFunc gGetNowPlayingClient;
static MRNowPlayingClientGetBundleIdentifierFunc gClientBundleIdentifier;
static MRNowPlayingClientGetParentAppBundleIdentifierFunc gClientParentBundleIdentifier;
static MRSendCommandFunc gSendCommand;
static MRSetElapsedTimeFunc gSetElapsedTime;

static dispatch_queue_t gQueue;
static NSUInteger gLastArtworkHash;

static void debugLog(const char *message) {
    if (getenv("MONOTCH_MEDIA_DEBUG") != NULL) {
        fprintf(stderr, "bridge: %s\n", message);
        fflush(stderr);
    }
}

static NSString *mediaKey(void *handle, const char *name) {
    void *symbol = dlsym(handle, name);
    if (symbol != NULL) {
        CFStringRef value = *(CFStringRef *)symbol;
        if (value != NULL) {
            return (__bridge NSString *)value;
        }
    }
    return [NSString stringWithUTF8String:name];
}

static void *gMediaRemoteHandle;

static NSString *stringForKey(NSDictionary *info, const char *name) {
    id value = info[mediaKey(gMediaRemoteHandle, name)];
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static double doubleForKey(NSDictionary *info, const char *name) {
    id value = info[mediaKey(gMediaRemoteHandle, name)];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        double number = [value doubleValue];
        return isfinite(number) ? number : 0;
    }
    return 0;
}

static void writeLine(NSDictionary *payload) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    if (data == nil) {
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emitState(void) {
    // Resolve the source app first, but never let a silent PID callback block emission.
    __block int resolvedPID = 0;
    dispatch_semaphore_t pidDone = dispatch_semaphore_create(0);
    dispatch_queue_t pidQueue = dispatch_queue_create("monotch.media.bridge.pid", DISPATCH_QUEUE_SERIAL);
    gGetNowPlayingPID(pidQueue, ^(int pid) {
        resolvedPID = pid;
        dispatch_semaphore_signal(pidDone);
    });
    dispatch_semaphore_wait(pidDone, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2));
    int pid = resolvedPID;

    // The PID is often a helper (e.g. WebKit GPU process); the client's parent
    // bundle identifier points at the actual browser/app.
    __block NSString *clientBundleID = nil;
    __block NSString *clientParentBundleID = nil;
    if (gGetNowPlayingClient != NULL && (gClientBundleIdentifier != NULL || gClientParentBundleIdentifier != NULL)) {
        dispatch_semaphore_t clientDone = dispatch_semaphore_create(0);
        gGetNowPlayingClient(pidQueue, ^(id client) {
            if (client != nil) {
                if (gClientBundleIdentifier != NULL) {
                    clientBundleID = gClientBundleIdentifier(client);
                }
                if (gClientParentBundleIdentifier != NULL) {
                    clientParentBundleID = gClientParentBundleIdentifier(client);
                }
            }
            dispatch_semaphore_signal(clientDone);
        });
        dispatch_semaphore_wait(clientDone, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2));
    }

    {
        debugLog("requesting now playing info");
        gGetNowPlayingInfo(gQueue, ^(CFDictionaryRef infoRef) {
            debugLog("info callback fired");
            NSDictionary *info = (__bridge NSDictionary *)infoRef;
            NSMutableDictionary *payload = [NSMutableDictionary dictionary];
            payload[@"event"] = @"state";

            if (info.count > 0) {
                double rate = doubleForKey(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
                double position = doubleForKey(info, "kMRMediaRemoteNowPlayingInfoElapsedTime");
                NSDate *timestamp = info[mediaKey(gMediaRemoteHandle, "kMRMediaRemoteNowPlayingInfoTimestamp")];
                if (rate > 0 && [timestamp isKindOfClass:[NSDate class]]) {
                    position += -timestamp.timeIntervalSinceNow * rate;
                }

                payload[@"title"] = stringForKey(info, "kMRMediaRemoteNowPlayingInfoTitle");
                payload[@"artist"] = stringForKey(info, "kMRMediaRemoteNowPlayingInfoArtist");
                payload[@"album"] = stringForKey(info, "kMRMediaRemoteNowPlayingInfoAlbum");
                payload[@"duration"] = @(doubleForKey(info, "kMRMediaRemoteNowPlayingInfoDuration"));
                payload[@"position"] = @(position);
                payload[@"playing"] = @(rate > 0);

                NSData *artwork = info[mediaKey(gMediaRemoteHandle, "kMRMediaRemoteNowPlayingInfoArtworkData")];
                if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0 && artwork.length < 4 * 1024 * 1024) {
                    // NSData's -hash only covers the first ~80 bytes; album covers
                    // share identical image headers, so it collides across tracks.
                    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                    CC_SHA256(artwork.bytes, (CC_LONG)artwork.length, digest);
                    NSUInteger artworkHash = 0;
                    memcpy(&artworkHash, digest, sizeof(artworkHash));
                    artworkHash &= 0x7FFFFFFFFFFFFFFFULL;

                    payload[@"artworkHash"] = @(artworkHash);
                    if (artworkHash != gLastArtworkHash) {
                        gLastArtworkHash = artworkHash;
                        payload[@"artworkB64"] = [artwork base64EncodedStringWithOptions:0];
                    }
                }
            } else {
                payload[@"title"] = @"";
                payload[@"playing"] = @NO;
            }

            NSString *bundleID = @"";
            if (clientParentBundleID.length > 0) {
                bundleID = clientParentBundleID;
            } else if (clientBundleID.length > 0) {
                bundleID = clientBundleID;
            }

            NSRunningApplication *application = nil;
            if (bundleID.length > 0) {
                application = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleID].firstObject;
            }
            if (application == nil && pid > 0) {
                application = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            }
            if (bundleID.length == 0) {
                bundleID = application.bundleIdentifier ?: @"";
            }
            payload[@"bundleID"] = bundleID;
            payload[@"appName"] = application.localizedName ?: @"";

            writeLine(payload);
        });
    }
}

static void runCommandMode(void) {
    const char *command = getenv("MONOTCH_MEDIA_COMMAND");
    if (command == NULL) {
        exit(1);
    }

    if (strcmp(command, "seek") == 0) {
        const char *positionValue = getenv("MONOTCH_MEDIA_POSITION");
        if (positionValue != NULL && gSetElapsedTime != NULL) {
            gSetElapsedTime(atof(positionValue));
        }
    } else if (gSendCommand != NULL) {
        int code = -1;
        if (strcmp(command, "play") == 0) code = MRCommandPlay;
        else if (strcmp(command, "pause") == 0) code = MRCommandPause;
        else if (strcmp(command, "toggle") == 0) code = MRCommandTogglePlayPause;
        else if (strcmp(command, "next") == 0) code = MRCommandNextTrack;
        else if (strcmp(command, "previous") == 0) code = MRCommandPreviousTrack;
        if (code >= 0) {
            gSendCommand(code, NULL);
        }
    }

    // A PID roundtrip guarantees the command's XPC message flushed before exit.
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    gGetNowPlayingPID(gQueue, ^(int pid) {
        dispatch_semaphore_signal(done);
    });
    dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
    exit(0);
}

static void watchParent(void) {
    // The app holds our stdin pipe; EOF means it exited — don't linger orphaned.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char scratch[256];
        while (true) {
            ssize_t bytesRead = read(STDIN_FILENO, scratch, sizeof(scratch));
            if (bytesRead <= 0) {
                exit(0);
            }
        }
    });
}

static void runStreamMode(void) {
    gRegisterNotifications(gQueue);

    NSArray<NSString *> *notificationNames = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"
    ];
    for (NSString *name in notificationNames) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(NSNotification *note) {
            emitState();
        }];
    }

    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), 2 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
    dispatch_source_set_event_handler(timer, ^{
        emitState();
    });
    dispatch_resume(timer);

    watchParent();
    debugLog("stream mode started");
    emitState();
    CFRunLoopRun();
}

// Called from perl AFTER dl_load_file returns — doing this work inside a dyld
// constructor stalls MediaRemote's info callbacks (dyld lock held during dlopen).
extern void monotch_main(void) {
    @autoreleasepool {
        gMediaRemoteHandle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (gMediaRemoteHandle == NULL) {
            writeLine(@{@"event": @"error", @"message": @"MediaRemote unavailable"});
            exit(1);
        }

        gGetNowPlayingInfo = (MRGetNowPlayingInfoFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteGetNowPlayingInfo");
        gRegisterNotifications = (MRRegisterForNowPlayingNotificationsFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        gGetNowPlayingPID = (MRGetNowPlayingApplicationPIDFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteGetNowPlayingApplicationPID");
        gGetNowPlayingClient = (MRGetNowPlayingClientFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteGetNowPlayingClient");
        gClientBundleIdentifier = (MRNowPlayingClientGetBundleIdentifierFunc)dlsym(gMediaRemoteHandle, "MRNowPlayingClientGetBundleIdentifier");
        gClientParentBundleIdentifier = (MRNowPlayingClientGetParentAppBundleIdentifierFunc)dlsym(gMediaRemoteHandle, "MRNowPlayingClientGetParentAppBundleIdentifier");
        gSendCommand = (MRSendCommandFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteSendCommand");
        gSetElapsedTime = (MRSetElapsedTimeFunc)dlsym(gMediaRemoteHandle, "MRMediaRemoteSetElapsedTime");

        gQueue = dispatch_queue_create("monotch.media.bridge", DISPATCH_QUEUE_SERIAL);

        const char *mode = getenv("MONOTCH_MEDIA_MODE");
        if (mode != NULL && strcmp(mode, "command") == 0) {
            runCommandMode();
            return;
        }

        if (gGetNowPlayingInfo == NULL || gRegisterNotifications == NULL || gGetNowPlayingPID == NULL) {
            writeLine(@{@"event": @"error", @"message": @"MediaRemote symbols missing"});
            exit(1);
        }

        runStreamMode();
    }
}
