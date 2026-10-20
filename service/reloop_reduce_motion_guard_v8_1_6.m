#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t gStopRequested = 0;
static NSString *gExecutablePath = nil;

static NSString *stateFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/ReloopBridge/reduce-motion-before-traktor-v8.1.6"];
}

static NSString *logFilePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Logs/ReloopBridge/reduce_motion_guard_v8_1_6.log"];
}

static NSString *timestamp(void) {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [f stringFromDate:[NSDate date]];
}

static void logMessage(NSString *message) {
    NSString *line = [NSString stringWithFormat:@"%@ | %@\n", timestamp(), message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    NSString *dir = [logFilePath() stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    if (![[NSFileManager defaultManager] fileExistsAtPath:logFilePath()]) {
        [data writeToFile:logFilePath() atomically:YES];
    } else {
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logFilePath()];
        [h seekToEndOfFile];
        [h writeData:data];
        [h closeFile];
    }
}

static BOOL localEffectiveState(void) {
    return [[NSWorkspace sharedWorkspace] accessibilityDisplayShouldReduceMotion];
}

static BOOL freshEffectiveState(BOOL *ok) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = gExecutablePath;
    task.arguments = @[@"--state-local"];

    NSPipe *outPipe = [NSPipe pipe];
    NSPipe *errPipe = [NSPipe pipe];
    task.standardOutput = outPipe;
    task.standardError = errPipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (__unused NSException *e) {
        *ok = NO;
        return NO;
    }

    NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (task.terminationStatus != 0) {
        *ok = NO;
        return NO;
    }
    if ([s isEqualToString:@"enabled"]) {
        *ok = YES;
        return YES;
    }
    if ([s isEqualToString:@"disabled"]) {
        *ok = YES;
        return NO;
    }

    *ok = NO;
    return NO;
}

static BOOL currentEffectiveState(BOOL *ok) {
    return freshEffectiveState(ok);
}

static BOOL traktorRunning(void) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/pgrep";
    task.arguments = @[@"-x", @"Traktor"];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (__unused NSException *e) {
        return NO;
    }

    return task.terminationStatus == 0;
}

static void runKillall(NSString *processName) {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/killall";
    task.arguments = @[processName];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (__unused NSException *e) {
    }
}

static void broadcastReduceMotionChanged(void) {
    // Dock and other long-running UI processes cache Reduce Motion.
    // This is the distributed notification they register for when the
    // accessibility Reduce Motion status changes. No Dock restart is used.
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"AXInterfaceReduceMotionStatusDidChange"
                      object:nil
                    userInfo:nil
          deliverImmediately:YES];
}

static BOOL waitForFreshState(BOOL wanted, NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        BOOL ok = NO;
        BOOL state = currentEffectiveState(&ok);
        if (ok && state == wanted) return YES;
        [NSThread sleepForTimeInterval:0.5];
    }

    BOOL ok = NO;
    BOOL state = currentEffectiveState(&ok);
    return ok && state == wanted;
}

static BOOL writeReduceMotionPreference(BOOL enabled) {
    CFPreferencesSetValue(CFSTR("reduceMotion"),
                          enabled ? kCFBooleanTrue : kCFBooleanFalse,
                          CFSTR("com.apple.universalaccess"),
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);

    Boolean synced = CFPreferencesSynchronize(CFSTR("com.apple.universalaccess"),
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost);
    if (!synced) {
        logMessage(@"ERROR: CFPreferencesSynchronize failed for com.apple.universalaccess.");
        return NO;
    }

    runKillall(@"cfprefsd");
    runKillall(@"universalaccessd");

    // Give the relaunched accessibility preference service a moment to settle,
    // then tell already-running UI processes to re-read Reduce Motion.
    [NSThread sleepForTimeInterval:0.20];
    broadcastReduceMotionChanged();
    [NSThread sleepForTimeInterval:0.20];
    broadcastReduceMotionChanged();

    return waitForFreshState(enabled, 5.0);
}

static BOOL setReduceMotion(BOOL enabled) {
    BOOL ok = NO;
    BOOL current = currentEffectiveState(&ok);
    if (ok && current == enabled) return YES;

    logMessage(enabled ? @"Setting Reduce Motion ON."
                       : @"Setting Reduce Motion OFF.");

    if (!writeReduceMotionPreference(enabled)) {
        logMessage(enabled
                   ? @"ERROR: Could not verify Reduce Motion effectively ON."
                   : @"ERROR: Could not verify Reduce Motion effectively OFF.");
        return NO;
    }

    logMessage(enabled
               ? @"Reduce Motion effective state: enabled."
               : @"Reduce Motion effective state: disabled.");
    return YES;
}

static BOOL saveOriginalStateIfNeeded(void) {
    NSString *path = stateFilePath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;

    BOOL ok = NO;
    BOOL original = currentEffectiveState(&ok);
    if (!ok) {
        logMessage(@"ERROR: Could not read effective Reduce Motion state before Traktor.");
        return NO;
    }

    NSString *s = original ? @"enabled\n" : @"disabled\n";
    NSError *err = nil;
    if (![s writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        logMessage([NSString stringWithFormat:@"ERROR: Could not save pre-Traktor state: %@",
                    err.localizedDescription ?: @"unknown error"]);
        return NO;
    }

    logMessage([NSString stringWithFormat:@"Saved pre-Traktor Reduce Motion state: %@.",
                original ? @"enabled" : @"disabled"]);
    return YES;
}

static BOOL restoreOriginalStateIfNeeded(void) {
    NSString *path = stateFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return YES;

    NSError *err = nil;
    NSString *s = [NSString stringWithContentsOfFile:path
                                           encoding:NSUTF8StringEncoding
                                              error:&err];
    if (!s) {
        logMessage(@"ERROR: Could not read saved pre-Traktor Reduce Motion state.");
        return NO;
    }

    BOOL wanted;
    if ([s hasPrefix:@"enabled"]) wanted = YES;
    else if ([s hasPrefix:@"disabled"]) wanted = NO;
    else {
        logMessage(@"ERROR: Saved pre-Traktor Reduce Motion state is invalid.");
        return NO;
    }

    if (!setReduceMotion(wanted)) {
        logMessage(@"ERROR: Pre-Traktor Reduce Motion state could not be restored; state file retained.");
        return NO;
    }

    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    logMessage([NSString stringWithFormat:@"Restored pre-Traktor Reduce Motion state: %@.",
                wanted ? @"enabled" : @"disabled"]);
    return YES;
}

static void signalHandler(int sig) {
    (void)sig;
    gStopRequested = 1;
}

static int permissionTest(void) {
    if (traktorRunning()) {
        fprintf(stderr, "ERROR: Close Traktor before the permission check.\n");
        return 2;
    }

    BOOL readOK = NO;
    BOOL original = currentEffectiveState(&readOK);
    if (!readOK) {
        fprintf(stderr, "ERROR: Could not read the effective Reduce Motion state.\n");
        return 3;
    }

    printf("Permission check: effective Reduce Motion is %s.\n",
           original ? "enabled" : "disabled");
    printf("Permission check: rewriting the same state; no visible toggle should occur...\n");

    // Write the existing state back to the protected domain. This proves the
    // helper has access without briefly changing the user's motion setting.
    if (!writeReduceMotionPreference(original)) {
        fprintf(stderr,
                "FDA_REQUIRED\n"
                "The helper could not write and verify the protected Reduce Motion preference.\n");
        return 4;
    }

    printf("FDA_OK\n");
    return 0;
}

static int runGuard(void) {
    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    signal(SIGHUP, signalHandler);

    BOOL ok = NO;
    BOOL initial = currentEffectiveState(&ok);
    logMessage([NSString stringWithFormat:
                @"Reduce Motion guard v8.1.6 started. Effective state: %@.",
                ok ? (initial ? @"enabled" : @"disabled") : @"unknown"]);

    if (!traktorRunning()) restoreOriginalStateIfNeeded();

    BOOL lastRunning = NO;
    BOOL haveLast = NO;

    while (!gStopRequested) {
        @autoreleasepool {
            BOOL running = traktorRunning();

            if (running) {
                if (!haveLast || !lastRunning) {
                    logMessage(@"Traktor detected.");
                    saveOriginalStateIfNeeded();
                }
                setReduceMotion(YES);
            } else {
                if (haveLast && lastRunning) {
                    logMessage(@"Traktor no longer detected.");
                }
                restoreOriginalStateIfNeeded();
            }

            lastRunning = running;
            haveLast = YES;
        }

        for (int i = 0; i < 20 && !gStopRequested; i++) usleep(100000);
    }

    logMessage(@"Reduce Motion guard stopping.");
    restoreOriginalStateIfNeeded();

    BOOL finalOK = NO;
    BOOL finalState = currentEffectiveState(&finalOK);
    logMessage([NSString stringWithFormat:
                @"Reduce Motion guard stopped. Effective state: %@.",
                finalOK ? (finalState ? @"enabled" : @"disabled") : @"unknown"]);
    return 0;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        gExecutablePath = [[[NSProcessInfo processInfo] arguments][0] stringByStandardizingPath];

        if (argc != 2) {
            fprintf(stderr, "Usage: %s --permission-test | --state | --state-local | --guard\n", argv[0]);
            return 64;
        }

        NSString *arg = [NSString stringWithUTF8String:argv[1]];
        if ([arg isEqualToString:@"--state-local"]) {
            printf("%s\n", localEffectiveState() ? "enabled" : "disabled");
            return 0;
        }
        if ([arg isEqualToString:@"--state"]) {
            BOOL ok = NO;
            BOOL state = currentEffectiveState(&ok);
            if (!ok) return 1;
            printf("%s\n", state ? "enabled" : "disabled");
            return 0;
        }
        if ([arg isEqualToString:@"--permission-test"]) return permissionTest();
        if ([arg isEqualToString:@"--guard"]) return runGuard();

        fprintf(stderr, "Unknown option.\n");
        return 64;
    }
}
