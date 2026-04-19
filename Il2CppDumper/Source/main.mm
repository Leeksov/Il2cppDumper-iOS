//
//  main.mm — tweak entry point
//

#include "../Prefix.h"
#include "il2cpp/api.h"
#include "dumper/dumper.h"

#import "ZipArchive.h"
#import "../UI/DumperHUD.h"

static NSString *const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.leeksov.il2cppdumper.plist";

struct DumperPrefs {
    bool enabled;
    bool enabledForBundle;
    bool genScript;
    bool genHeader;
    bool genDll;
    bool copyScripts;
    int waitTime;
};

static DumperPrefs readPrefs() {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];

    DumperPrefs p;
    p.enabled          = [prefs[@"dumperEnabled"] boolValue];
    p.enabledForBundle = bid && [[prefs[@"enabledApps"] objectForKey:bid] boolValue];
    p.genScript        = prefs[@"genScript"] ? [prefs[@"genScript"] boolValue] : true;
    p.genHeader        = prefs[@"genHeader"] ? [prefs[@"genHeader"] boolValue] : true;
    p.genDll           = prefs[@"genDll"]    ? [prefs[@"genDll"] boolValue]    : true;
    p.copyScripts      = prefs[@"copyScripts"] ? [prefs[@"copyScripts"] boolValue] : true;
    p.waitTime         = prefs[@"waitTime"]  ? [prefs[@"waitTime"] intValue]   : WAIT_TIME_SEC;
    if (p.waitTime < 1)  p.waitTime = 1;
    if (p.waitTime > 30) p.waitTime = 30;
    return p;
}

static void copyScriptsToDump(NSString *dumpPath) {
    NSString *src = @"/var/jb/usr/share/Il2CppDumper/scripts";
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:src]) return;
    NSString *dst = [dumpPath stringByAppendingPathComponent:@"scripts"];
    [fm createDirectoryAtPath:dst withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *files = [fm contentsOfDirectoryAtPath:src error:nil];
    for (NSString *f in files) {
        NSString *sp = [src stringByAppendingPathComponent:f];
        NSString *dp = [dst stringByAppendingPathComponent:f];
        [fm removeItemAtPath:dp error:nil];
        [fm copyItemAtPath:sp toPath:dp error:nil];
    }
}

// Ensure prefs plist exists with defaults — same pattern as iSSBypass.
// Runs regardless of target, so Prefs bundle always finds a readable plist.
static void ensurePrefsExist() {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:kPrefsPath]) return;
    NSDictionary *defaults = @{
        @"dumperEnabled": @NO,
        @"enabledApps":   @{},
        @"genScript":     @YES,
        @"genHeader":     @YES,
        @"genDll":        @YES,
        @"copyScripts":   @YES,
        @"waitTime":      @(WAIT_TIME_SEC),
    };
    [defaults writeToFile:kPrefsPath atomically:YES];
    [fm setAttributes:@{
        NSFileOwnerAccountName: @"mobile",
        NSFileGroupOwnerAccountName: @"mobile",
        NSFilePosixPermissions: @0644,
    } ofItemAtPath:kPrefsPath error:nil];
}

ENTRY_POINT void onLoad() {
    ensurePrefsExist();

    // We're also filtered into Settings.app — do nothing there.
    NSString *currentBundle = [[NSBundle mainBundle] bundleIdentifier];
    if ([currentBundle isEqualToString:@"com.apple.Preferences"]) return;

    DumperPrefs p = readPrefs();
    if (!p.enabled || !p.enabledForBundle) {
        NSLog(@"[Il2CppDumper] Disabled for %@, skipping", currentBundle);
        return;
    }
    NSLog(@"[Il2CppDumper] Enabled for %@, initializing...", currentBundle);

    Dumper::genScript = p.genScript;
    Dumper::genHeader = p.genHeader;
    Dumper::genDll    = p.genDll;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(p.waitTime);

        NSLog(@"[Il2CppDumper] Starting dump...");
        [[DumperHUD shared] show];
        [[DumperHUD shared] setStatus:@"Starting…"];
        [[DumperHUD shared] setProgress:0.01f];

        // Wire up live progress from dumper thread → HUD
        Dumper::onProgress = [](const char* status, float progress, int64_t asm_, int64_t classes, int64_t methods) {
            NSString *s = status ? [NSString stringWithUTF8String:status] : @"";
            [[DumperHUD shared] setStatus:s];
            [[DumperHUD shared] setProgress:progress];
            [[DumperHUD shared] setStatsWithAssemblies:(NSInteger)asm_
                                              classes:(NSInteger)classes
                                              methods:(NSInteger)methods];
        };

        NSString* appPath = [[NSBundle mainBundle] bundlePath];
        NSString* binaryPath;
        if ([@BINARY_NAME isEqualToString:@"UnityFramework"])
            binaryPath = [appPath stringByAppendingPathComponent:@"Frameworks/UnityFramework.framework/UnityFramework"];
        else
            binaryPath = [appPath stringByAppendingPathComponent:@BINARY_NAME];

        [[DumperHUD shared] setStatus:@"Attaching to IL2CPP…"];
        if (!IL2CPP::attach(binaryPath.UTF8String)) {
            NSLog(@"[Il2CppDumper] FAILED: missing IL2CPP symbols");
            [[DumperHUD shared] showErrorWithMessage:@"Failed to attach — IL2CPP symbols missing."];
            return;
        }

        NSString* docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        NSString* appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey] ?: @"App";
        NSString* folderName = [NSString stringWithFormat:@"%@_%s",
            [appName stringByReplacingOccurrencesOfString:@" " withString:@""], DUMP_FOLDER];
        NSString* dumpPath = [NSString stringWithFormat:@"%@/%@", docDir, folderName];
        NSString* headersPath = [NSString stringWithFormat:@"%@/Assembly", dumpPath];
        NSString* zipPath = [NSString stringWithFormat:@"%@.zip", dumpPath];

        NSFileManager* fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:dumpPath error:nil];
        [fm removeItemAtPath:zipPath error:nil];

        NSError* error = nil;
        if (![fm createDirectoryAtPath:headersPath withIntermediateDirectories:YES attributes:nil error:&error]) {
            [[DumperHUD shared] showErrorWithMessage:
                [NSString stringWithFormat:@"Failed to create directory:\n%@", error.localizedDescription]];
            return;
        }

        auto result = Dumper::dump(dumpPath.UTF8String, headersPath.UTF8String);

        if (p.copyScripts) {
            [[DumperHUD shared] setStatus:@"Copying RE scripts…"];
            copyScriptsToDump(dumpPath);
        }

        [[DumperHUD shared] setStatus:@"Compressing to .zip…"];
        [[DumperHUD shared] setProgress:0.99f];
        if ([fm fileExistsAtPath:dumpPath]) {
            [SSZipArchive createZipFileAtPath:zipPath withContentsOfDirectory:dumpPath];
            [fm removeItemAtPath:dumpPath error:nil];
        }

        NSLog(@"[Il2CppDumper] Done. Result: %d", (int)result);
        Dumper::onProgress = nullptr;

        if (result != Dumper::Status::OK) {
            [[DumperHUD shared] showErrorWithMessage:@"Dump failed — check logs.txt inside the dump folder."];
        } else {
            [[DumperHUD shared] showSuccessWithMessage:@"Dump completed"
                                                  path:zipPath];
        }
    });
}
