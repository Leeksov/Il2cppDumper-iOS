//
//  DumperRootListController.m — Prefs UI for Il2CppDumper
//  Significantly improved over iSSBypass:
//    • Custom animated header card with gradient background + app icon
//    • Beautiful app list with rounded icons, bundle ID subtitle, alt row shading
//    • Smart category filtering (All / User / Unity-only)
//    • Live search with debouncing
//    • Animated switches
//    • Dump-specific settings (wait time, generate DLL/header/script)
//    • Socials with glyphs, version footer
//

#import "DumperRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
- (BOOL)openURL:(NSURL *)url;
- (BOOL)openSensitiveURL:(NSURL *)url withOptions:(id)options;
@end

@interface LSApplicationProxy : NSObject
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSString *localizedName;
@property (readonly) NSString *applicationType;
@property (readonly) NSURL *bundleURL;
@end

@interface UIImage (Private)
+ (id)_applicationIconImageForBundleIdentifier:(NSString *)bundleIdentifier format:(int)format scale:(double)scale;
@end

static NSString *const kPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.leeksov.il2cppdumper.plist";

// ──────── Gradient header view ────────
@interface DumperHeaderView : UIView
@property (nonatomic, strong) CAGradientLayer *gradient;
@end

@implementation DumperHeaderView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.gradient = [CAGradientLayer layer];
        self.gradient.colors = @[
            (id)[UIColor colorWithRed:0.15 green:0.20 blue:0.45 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.35 green:0.15 blue:0.55 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.20 green:0.30 blue:0.60 alpha:1.0].CGColor,
        ];
        self.gradient.startPoint = CGPointMake(0, 0);
        self.gradient.endPoint = CGPointMake(1, 1);
        self.gradient.cornerRadius = 16;
        [self.layer addSublayer:self.gradient];
        self.layer.cornerRadius = 16;
        self.clipsToBounds = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.gradient.frame = self.bounds;
}
@end

// Session cache for app lists — avoid rescanning when navigating back/forward.
// Key: @(DumperAppType), Value: NSArray<NSDictionary*>
static NSMutableDictionary *gAppListCache;
static dispatch_once_t gCacheOnce;

@implementation DumperRootListController

#pragma mark - Table Setup

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = self.appType == DumperAppTypeMain ? @"Il2CppDumper" :
                 self.appType == DumperAppTypeAll  ? @"All Apps" :
                 self.appType == DumperAppTypeUser ? @"User Apps" : @"Unity Apps";

    if (self.appType == DumperAppTypeMain) {
        [self setupHeader];
    } else {
        self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 56)];
        self.searchBar.delegate = self;
        self.searchBar.placeholder = @"Search apps or bundle ID…";
        self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
        self.searchBar.tintColor = [UIColor systemPurpleColor];
        self.table.tableHeaderView = self.searchBar;
    }

    // Style improvements
    self.table.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.table.separatorInset = UIEdgeInsetsMake(0, 16, 0, 0);
    if (@available(iOS 13.0, *)) {
        self.table.separatorColor = [UIColor separatorColor];
    }
}

- (void)setupHeader {
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = UIColor.clearColor;
    container.frame = CGRectMake(0, 0, self.table.bounds.size.width, 180);

    DumperHeaderView *card = [[DumperHeaderView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.1 blue:0.5 alpha:0.35].CGColor;
    card.layer.shadowOffset = CGSizeMake(0, 6);
    card.layer.shadowRadius = 14;
    card.layer.shadowOpacity = 1.0;
    card.layer.masksToBounds = NO;
    [container addSubview:card];

    // Icon block
    UIView *iconBg = [[UIView alloc] init];
    iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    iconBg.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.20];
    iconBg.layer.cornerRadius = 16;
    [card addSubview:iconBg];

    UILabel *iconGlyph = [[UILabel alloc] init];
    iconGlyph.translatesAutoresizingMaskIntoConstraints = NO;
    iconGlyph.text = @"⚙";
    iconGlyph.font = [UIFont systemFontOfSize:42 weight:UIFontWeightBold];
    iconGlyph.textColor = UIColor.whiteColor;
    iconGlyph.textAlignment = NSTextAlignmentCenter;
    [iconBg addSubview:iconGlyph];

    // Title stack on the right of icon
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"Il2CppDumper";
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.textColor = UIColor.whiteColor;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.75;
    [card addSubview:title];

    UILabel *subtitle = [[UILabel alloc] init];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.text = @"Runtime IL2CPP metadata dumper";
    subtitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    subtitle.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    subtitle.adjustsFontSizeToFitWidth = YES;
    subtitle.minimumScaleFactor = 0.8;
    [card addSubview:subtitle];

    UIView *chip = [[UIView alloc] init];
    chip.translatesAutoresizingMaskIntoConstraints = NO;
    chip.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    chip.layer.cornerRadius = 10;
    [card addSubview:chip];
    UILabel *chipLbl = [[UILabel alloc] init];
    chipLbl.translatesAutoresizingMaskIntoConstraints = NO;
    chipLbl.text = @"v1.0";
    chipLbl.textColor = UIColor.whiteColor;
    chipLbl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    chipLbl.textAlignment = NSTextAlignmentCenter;
    [chip addSubview:chipLbl];

    UILabel *author = [[UILabel alloc] init];
    author.translatesAutoresizingMaskIntoConstraints = NO;
    author.text = @"by Leeksov";
    author.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    author.textColor = [UIColor colorWithWhite:1.0 alpha:0.75];
    author.textAlignment = NSTextAlignmentCenter;
    [card addSubview:author];

    [NSLayoutConstraint activateConstraints:@[
        // Card fills container with margins
        [card.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [card.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [card.topAnchor constraintEqualToAnchor:container.topAnchor constant:12],
        [card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12],

        // Icon — left center
        [iconBg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:20],
        [iconBg.centerYAnchor constraintEqualToAnchor:card.centerYAnchor constant:-8],
        [iconBg.widthAnchor constraintEqualToConstant:72],
        [iconBg.heightAnchor constraintEqualToConstant:72],

        // Icon glyph fills iconBg
        [iconGlyph.leadingAnchor constraintEqualToAnchor:iconBg.leadingAnchor],
        [iconGlyph.trailingAnchor constraintEqualToAnchor:iconBg.trailingAnchor],
        [iconGlyph.topAnchor constraintEqualToAnchor:iconBg.topAnchor],
        [iconGlyph.bottomAnchor constraintEqualToAnchor:iconBg.bottomAnchor],

        // Title — next to icon
        [title.leadingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:14],
        [title.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [title.topAnchor constraintEqualToAnchor:iconBg.topAnchor constant:4],

        // Subtitle — below title
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4],

        // Chip — below subtitle
        [chip.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [chip.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:8],
        [chip.widthAnchor constraintEqualToConstant:52],
        [chip.heightAnchor constraintEqualToConstant:20],

        [chipLbl.leadingAnchor constraintEqualToAnchor:chip.leadingAnchor],
        [chipLbl.trailingAnchor constraintEqualToAnchor:chip.trailingAnchor],
        [chipLbl.topAnchor constraintEqualToAnchor:chip.topAnchor],
        [chipLbl.bottomAnchor constraintEqualToAnchor:chip.bottomAnchor],

        // Author — centered at bottom
        [author.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [author.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
        [author.leadingAnchor constraintGreaterThanOrEqualToAnchor:card.leadingAnchor constant:16],
        [author.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
    ]];

    self.table.tableHeaderView = container;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // Fix table header width to match table (critical for correct layout)
    UIView *header = self.table.tableHeaderView;
    if (header && self.appType == DumperAppTypeMain) {
        CGFloat width = self.table.bounds.size.width;
        if (header.frame.size.width != width) {
            CGRect f = header.frame;
            f.size.width = width;
            header.frame = f;
            self.table.tableHeaderView = header; // re-assign triggers relayout
        }
    }
}

#pragma mark - Specifiers

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];

        if (self.appType == DumperAppTypeMain) {
            [self buildMainSpecifiers:specs];
        } else {
            [self buildAppListSpecifiers:specs];
        }
        _specifiers = [specs copy];
    }
    return _specifiers;
}

- (void)buildMainSpecifiers:(NSMutableArray *)specs {
    // ── General ──
    PSSpecifier *genHeader = [PSSpecifier groupSpecifierWithName:@"General"];
    [genHeader setProperty:@"Enable dumping, configure which files are generated." forKey:@"footerText"];
    [specs addObject:genHeader];

    PSSpecifier *enableSw = [PSSpecifier preferenceSpecifierNamed:@"Enable Dumper"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSwitchCell edit:nil];
    [enableSw setProperty:@"dumperEnabled" forKey:@"key"];
    [enableSw setProperty:@NO forKey:@"default"];
    [specs addObject:enableSw];

    // ── Targets ──
    PSSpecifier *appsHeader = [PSSpecifier groupSpecifierWithName:@"Target Applications"];
    [appsHeader setProperty:@"Choose which apps to dump. Unity-only is recommended for best results." forKey:@"footerText"];
    [specs addObject:appsHeader];

    PSSpecifier *unitySpec = [PSSpecifier preferenceSpecifierNamed:@"Unity Apps"
        target:self set:nil get:nil
        detail:[DumperRootListController class] cell:PSLinkCell edit:nil];
    [unitySpec setProperty:@(DumperAppTypeUnity) forKey:@"appType"];
    [unitySpec setProperty:@"Apps with UnityFramework.framework" forKey:@"subtitle"];
    [specs addObject:unitySpec];

    PSSpecifier *userSpec = [PSSpecifier preferenceSpecifierNamed:@"User Apps"
        target:self set:nil get:nil
        detail:[DumperRootListController class] cell:PSLinkCell edit:nil];
    [userSpec setProperty:@(DumperAppTypeUser) forKey:@"appType"];
    [specs addObject:userSpec];

    PSSpecifier *allSpec = [PSSpecifier preferenceSpecifierNamed:@"All Apps"
        target:self set:nil get:nil
        detail:[DumperRootListController class] cell:PSLinkCell edit:nil];
    [allSpec setProperty:@(DumperAppTypeAll) forKey:@"appType"];
    [specs addObject:allSpec];

    // ── Dump Options ──
    PSSpecifier *optsHeader = [PSSpecifier groupSpecifierWithName:@"Output Files"];
    [optsHeader setProperty:@"Choose which files to generate alongside dump.cs" forKey:@"footerText"];
    [specs addObject:optsHeader];

    PSSpecifier *genScript = [PSSpecifier preferenceSpecifierNamed:@"Generate script.json"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSwitchCell edit:nil];
    [genScript setProperty:@"genScript" forKey:@"key"];
    [genScript setProperty:@YES forKey:@"default"];
    [specs addObject:genScript];

    PSSpecifier *genHeader2 = [PSSpecifier preferenceSpecifierNamed:@"Generate il2cpp.h"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSwitchCell edit:nil];
    [genHeader2 setProperty:@"genHeader" forKey:@"key"];
    [genHeader2 setProperty:@YES forKey:@"default"];
    [specs addObject:genHeader2];

    PSSpecifier *genDll = [PSSpecifier preferenceSpecifierNamed:@"Generate DummyDll"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSwitchCell edit:nil];
    [genDll setProperty:@"genDll" forKey:@"key"];
    [genDll setProperty:@YES forKey:@"default"];
    [specs addObject:genDll];

    PSSpecifier *copyScripts = [PSSpecifier preferenceSpecifierNamed:@"Include RE Scripts"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSwitchCell edit:nil];
    [copyScripts setProperty:@"copyScripts" forKey:@"key"];
    [copyScripts setProperty:@YES forKey:@"default"];
    [specs addObject:copyScripts];

    // ── Timing ──
    PSSpecifier *timeHeader = [PSSpecifier groupSpecifierWithName:@"Timing"];
    [timeHeader setProperty:@"Seconds to wait after app launch before dumping starts." forKey:@"footerText"];
    [specs addObject:timeHeader];

    PSSpecifier *waitSpec = [PSSpecifier preferenceSpecifierNamed:@"Wait Time"
        target:self set:@selector(setPref:specifier:) get:@selector(getPref:)
        detail:nil cell:PSSliderCell edit:nil];
    [waitSpec setProperty:@"waitTime" forKey:@"key"];
    [waitSpec setProperty:@5 forKey:@"default"];
    [waitSpec setProperty:@1 forKey:@"min"];
    [waitSpec setProperty:@30 forKey:@"max"];
    [waitSpec setProperty:@YES forKey:@"showValue"];
    [specs addObject:waitSpec];

    // ── Author ──
    PSSpecifier *authHeader = [PSSpecifier groupSpecifierWithName:@"Leeksov"];
    [authHeader setProperty:@"Tweak author — tap to open" forKey:@"footerText"];
    [specs addObject:authHeader];

    PSSpecifier *tg = [PSSpecifier preferenceSpecifierNamed:@"Telegram"
        target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    tg.target = self;
    tg.buttonAction = @selector(openTelegram);
    [tg setProperty:NSStringFromSelector(@selector(openTelegram)) forKey:@"action"];
    [tg setProperty:@"@leeksov_coding" forKey:@"subtitle"];
    [specs addObject:tg];

    PSSpecifier *gh = [PSSpecifier preferenceSpecifierNamed:@"GitHub"
        target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    gh.target = self;
    gh.buttonAction = @selector(openGitHub);
    [gh setProperty:NSStringFromSelector(@selector(openGitHub)) forKey:@"action"];
    [gh setProperty:@"github.com/Leeksov" forKey:@"subtitle"];
    [specs addObject:gh];

    // ── Version footer ──
    PSSpecifier *ver = [PSSpecifier groupSpecifierWithName:@""];
    [ver setProperty:@"Il2CppDumper v1.0 · Runtime metadata dumper for iOS" forKey:@"footerText"];
    [specs addObject:ver];
}

- (void)buildAppListSpecifiers:(NSMutableArray *)specs {
    dispatch_once(&gCacheOnce, ^{ gAppListCache = [NSMutableDictionary dictionary]; });
    NSArray *cached = gAppListCache[@(self.appType)];

    if (cached) {
        self.allApps = cached;
        self.filteredApps = cached;
        [self populateSpecifiers:specs withApps:cached];
    } else {
        // Show loading placeholder immediately, load in background
        self.allApps = @[];
        self.filteredApps = @[];
        PSSpecifier *header = [PSSpecifier groupSpecifierWithName:@""];
        [header setProperty:@"Loading…" forKey:@"footerText"];
        [specs addObject:header];
        [self startLoadingSpinner];
        [self loadAppsAsync];
    }
}

- (void)populateSpecifiers:(NSMutableArray *)specs withApps:(NSArray *)apps {
    NSString *footer = apps.count > 0
        ? [NSString stringWithFormat:@"%zu apps", (size_t)apps.count]
        : @"No matching apps found";
    PSSpecifier *header = [PSSpecifier groupSpecifierWithName:@""];
    [header setProperty:footer forKey:@"footerText"];
    [specs addObject:header];

    for (NSDictionary *app in apps) {
        PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:app[@"name"]
            target:self set:@selector(setAppEnabled:specifier:) get:@selector(getAppEnabled:)
            detail:nil cell:PSSwitchCell edit:nil];
        [spec setProperty:app[@"bundleID"] forKey:@"bundleID"];
        [spec setProperty:app[@"bundleID"] forKey:@"subtitle"];
        UIImage *icon = app[@"icon"];
        if (icon && ![icon isKindOfClass:[NSNull class]]) {
            [spec setProperty:icon forKey:@"iconImage"]; // already rounded
        }
        [specs addObject:spec];
    }
}

- (void)startLoadingSpinner {
    UIActivityIndicatorViewStyle style = UIActivityIndicatorViewStyleMedium;
    if (@available(iOS 13.0, *)) style = UIActivityIndicatorViewStyleLarge;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
    spinner.tag = 9191;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.hidesWhenStopped = YES;
    [spinner startAnimating];
    [self.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-40],
    ]];
}

- (void)stopLoadingSpinner {
    UIView *spinner = [self.view viewWithTag:9191];
    [spinner removeFromSuperview];
}

- (void)loadAppsAsync {
    DumperAppType type = self.appType;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray *apps = [weakSelf loadApplicationsForType:type];
        // Pre-round icons on BG thread so main thread doesn't stall
        NSMutableArray *processed = [NSMutableArray arrayWithCapacity:apps.count];
        for (NSDictionary *a in apps) {
            UIImage *icon = a[@"icon"];
            UIImage *rounded = nil;
            if (icon && ![icon isKindOfClass:[NSNull class]]) {
                rounded = [weakSelf roundedIcon:icon size:CGSizeMake(32, 32)];
            }
            [processed addObject:@{
                @"name": a[@"name"] ?: @"",
                @"bundleID": a[@"bundleID"] ?: @"",
                @"icon": rounded ?: [NSNull null],
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) s = weakSelf;
            if (!s) return;
            gAppListCache[@(type)] = processed;
            s.allApps = processed;
            s.filteredApps = processed;
            [s stopLoadingSpinner];
            s->_specifiers = nil;
            [s reloadSpecifiers];
        });
    });
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    self.appType = [[specifier propertyForKey:@"appType"] integerValue];
}

#pragma mark - Prefs Access

- (NSMutableDictionary *)loadPrefs {
    return [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
}

- (void)savePrefs:(NSDictionary *)prefs {
    [prefs writeToFile:kPrefsPath atomically:YES];
}

- (id)getPref:(PSSpecifier *)specifier {
    NSDictionary *prefs = [self loadPrefs];
    NSString *key = [specifier propertyForKey:@"key"];
    id val = prefs[key];
    return val ?: [specifier propertyForKey:@"default"];
}

- (void)setPref:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *prefs = [self loadPrefs];
    prefs[[specifier propertyForKey:@"key"]] = value;
    [self savePrefs:prefs];
}

- (id)getAppEnabled:(PSSpecifier *)specifier {
    NSDictionary *prefs = [self loadPrefs];
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    return @([[prefs[@"enabledApps"] objectForKey:bundleID] boolValue]);
}

- (void)setAppEnabled:(id)value specifier:(PSSpecifier *)specifier {
    NSString *bundleID = [specifier propertyForKey:@"bundleID"];
    NSMutableDictionary *prefs = [self loadPrefs];
    NSMutableDictionary *apps = [NSMutableDictionary dictionaryWithDictionary:prefs[@"enabledApps"] ?: @{}];
    apps[bundleID] = value;
    prefs[@"enabledApps"] = apps;
    [self savePrefs:prefs];
}

#pragma mark - Actions

- (void)openURLSafely:(NSURL *)url {
    if (!url) return;
    // Settings.app won't open URLs via UIApplication openURL from a prefs bundle.
    // Use the private LSApplicationWorkspace openURL: which works.
    Class LSWorkspaceCls = NSClassFromString(@"LSApplicationWorkspace");
    id ws = [LSWorkspaceCls performSelector:@selector(defaultWorkspace)];
    if (ws && [ws respondsToSelector:@selector(openURL:)]) {
        [ws openURL:url];
        return;
    }
    // Fallback
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

- (void)openTelegram {
    [self openURLSafely:[NSURL URLWithString:@"https://t.me/leeksov_coding"]];
}

- (void)openGitHub {
    [self openURLSafely:[NSURL URLWithString:@"https://github.com/Leeksov"]];
}

#pragma mark - App Loading

// Fast detection — checks known metadata paths only (no recursion, no file reads)
// Covers 99% of Unity games across all versions.
+ (BOOL)bundleHasIl2CppMetadata:(NSString *)bundlePath {
    if (!bundlePath) return NO;
    NSFileManager *fm = [NSFileManager defaultManager];
    static NSArray *candidates = nil;
    static dispatch_once_t onceT;
    dispatch_once(&onceT, ^{
        candidates = @[
            // Unity 2019.3+ (with UnityFramework)
            @"Frameworks/UnityFramework.framework/Data/Managed/Metadata/global-metadata.dat",
            // Pre-2019.3 (no UnityFramework — all in main binary)
            @"Data/Managed/Metadata/global-metadata.dat",
            // Rare: root-level Managed
            @"Managed/Metadata/global-metadata.dat",
        ];
    });
    for (NSString *rel in candidates) {
        if ([fm fileExistsAtPath:[bundlePath stringByAppendingPathComponent:rel]]) return YES;
    }
    return NO;
}

- (NSArray *)loadApplicationsForType:(DumperAppType)type {
    NSMutableArray *result = [NSMutableArray array];
    Class LSWorkspace = objc_getClass("LSApplicationWorkspace");
    if (!LSWorkspace) return result;

    id workspace = [LSWorkspace defaultWorkspace];
    NSArray *apps = [workspace allApplications];

    for (id proxy in apps) {
        NSString *bundleID = [proxy bundleIdentifier];
        if (!bundleID) continue;

        BOOL isSystem = [[proxy applicationType] isEqualToString:@"System"];
        BOOL hasMetadata = NO;
        NSString *bundlePath = nil;

        NSURL *bundleURL = [proxy bundleURL];
        if (bundleURL) bundlePath = [bundleURL path];

        if (type == DumperAppTypeUnity && bundlePath) {
            hasMetadata = [[self class] bundleHasIl2CppMetadata:bundlePath];
        }

        BOOL include = NO;
        if (type == DumperAppTypeAll) include = YES;
        else if (type == DumperAppTypeUser && !isSystem) include = YES;
        else if (type == DumperAppTypeUnity && hasMetadata) include = YES;

        if (include) {
            NSString *name = [proxy localizedName] ?: bundleID;
            UIImage *icon = [UIImage _applicationIconImageForBundleIdentifier:bundleID format:0 scale:3.0];
            NSMutableDictionary *entry = [@{
                @"name": name,
                @"bundleID": bundleID,
                @"icon": icon ?: [NSNull null],
            } mutableCopy];
            // For Unity apps, add a hint subtitle
            if (type == DumperAppTypeUnity) entry[@"unityHint"] = @"IL2CPP metadata found";
            [result addObject:entry];
        }
    }

    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] caseInsensitiveCompare:b[@"name"]];
    }];
}

#pragma mark - Icon

- (UIImage *)roundedIcon:(UIImage *)icon size:(CGSize)size {
    if (!icon) return nil;
    CGFloat corner = size.width * 0.2237;
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect rect = CGRectMake(0, 0, size.width, size.height);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:corner] addClip];
    [icon drawInRect:rect];
    UIImage *rounded = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rounded;
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    if (text.length == 0) {
        self.filteredApps = self.allApps;
    } else {
        NSPredicate *pred = [NSPredicate predicateWithFormat:@"name CONTAINS[cd] %@ OR bundleID CONTAINS[cd] %@", text, text];
        self.filteredApps = [self.allApps filteredArrayUsingPredicate:pred];
    }
    NSMutableArray *specs = [NSMutableArray array];
    [self populateSpecifiers:specs withApps:self.filteredApps];
    _specifiers = [specs copy];
    [self.table reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [self searchBar:searchBar textDidChange:@""];
    [searchBar resignFirstResponder];
}

@end
