//
//  DumperHUD.mm — custom dump status overlay
//
//  A floating card with blurred background, gradient header, animated progress,
//  live status text, and stats counters. Shown on a dedicated UIWindow to stay on top.
//

#import "DumperHUD.h"
#import <QuartzCore/QuartzCore.h>

// ─────────── Gradient progress bar ───────────
@interface GradientProgressBar : UIView
@property (nonatomic) float progress;
@property (nonatomic, strong) UIView *track;
@property (nonatomic, strong) UIView *fillContainer;
@property (nonatomic, strong) CAGradientLayer *fillGradient;
@property (nonatomic, strong) NSLayoutConstraint *fillWidth;
@end

@implementation GradientProgressBar

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;

        self.track = [UIView new];
        self.track.translatesAutoresizingMaskIntoConstraints = NO;
        self.track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
        self.track.layer.cornerRadius = 5;
        self.track.clipsToBounds = YES;
        [self addSubview:self.track];

        self.fillContainer = [UIView new];
        self.fillContainer.translatesAutoresizingMaskIntoConstraints = NO;
        [self.track addSubview:self.fillContainer];

        self.fillGradient = [CAGradientLayer layer];
        self.fillGradient.colors = @[
            (id)[UIColor colorWithRed:0.40 green:0.60 blue:1.00 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.70 green:0.40 blue:1.00 alpha:1.0].CGColor,
        ];
        self.fillGradient.startPoint = CGPointMake(0, 0.5);
        self.fillGradient.endPoint = CGPointMake(1, 0.5);
        [self.fillContainer.layer addSublayer:self.fillGradient];

        self.fillWidth = [self.fillContainer.widthAnchor constraintEqualToConstant:0];

        [NSLayoutConstraint activateConstraints:@[
            [self.track.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [self.track.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [self.track.topAnchor constraintEqualToAnchor:self.topAnchor],
            [self.track.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [self.fillContainer.leadingAnchor constraintEqualToAnchor:self.track.leadingAnchor],
            [self.fillContainer.topAnchor constraintEqualToAnchor:self.track.topAnchor],
            [self.fillContainer.bottomAnchor constraintEqualToAnchor:self.track.bottomAnchor],
            self.fillWidth,
        ]];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.fillGradient.frame = self.fillContainer.bounds;
}

- (void)setProgress:(float)progress {
    _progress = MAX(0.0f, MIN(1.0f, progress));
    self.fillWidth.constant = self.track.bounds.size.width * _progress;
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self layoutIfNeeded];
    } completion:nil];
}

- (void)setTintColorsStart:(UIColor *)start end:(UIColor *)end {
    self.fillGradient.colors = @[(id)start.CGColor, (id)end.CGColor];
}

@end


// ─────────── Gradient view (auto-layout aware) ───────────
@interface GradientView : UIView
@property (nonatomic, strong, readonly) CAGradientLayer *gradient;
@end

@implementation GradientView
+ (Class)layerClass { return [CAGradientLayer class]; }
- (CAGradientLayer *)gradient { return (CAGradientLayer *)self.layer; }
@end


// ─────────── HUD implementation ───────────
@interface DumperHUD ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIVisualEffectView *backdrop;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) GradientView *header;
@property (nonatomic, strong) UILabel *iconGlyph;
@property (nonatomic, strong) UILabel *titleLbl;
@property (nonatomic, strong) UILabel *subtitleLbl;

@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLbl;
@property (nonatomic, strong) GradientProgressBar *progressBar;
@property (nonatomic, strong) UILabel *percentLbl;
@property (nonatomic, strong) UILabel *statsLbl;
@property (nonatomic, strong) UILabel *pathLbl;
@property (nonatomic, strong) UIButton *actionButton;
@property (nonatomic, strong) UIButton *shareButton;
@property (nonatomic, strong) UIStackView *buttonRow;
@property (nonatomic, strong) NSString *sharePath;

@property (nonatomic, assign) DumperHUDState state;
@property (nonatomic, assign) BOOL visible;
@end

@implementation DumperHUD

+ (instancetype)shared {
    static DumperHUD *inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [DumperHUD new]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = DumperHUDStateProgress;
    }
    return self;
}

- (void)ensureBuilt {
    if (self.window) return;

    // On iOS 13+ a UIWindow MUST be attached to a UIWindowScene,
    // otherwise it won't appear in Unity/Metal games.
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            if (scene.activationState == UISceneActivationStateForegroundActive ||
                scene.activationState == UISceneActivationStateForegroundInactive) {
                win = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
                break;
            }
        }
    }
    if (!win) win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window = win;
    self.window.windowLevel = UIWindowLevelAlert + 100;
    self.window.backgroundColor = UIColor.clearColor;
    self.window.rootViewController = [UIViewController new];
    self.window.rootViewController.view.backgroundColor = UIColor.clearColor;

    UIView *root = self.window.rootViewController.view;

    // Blurred backdrop
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    self.backdrop = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.backdrop.frame = root.bounds;
    self.backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backdrop.alpha = 0;
    [root addSubview:self.backdrop];

    // Card
    self.card = [UIView new];
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    self.card.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    self.card.layer.cornerRadius = 22;
    self.card.clipsToBounds = NO;
    self.card.layer.shadowColor = UIColor.blackColor.CGColor;
    self.card.layer.shadowOffset = CGSizeMake(0, 10);
    self.card.layer.shadowRadius = 24;
    self.card.layer.shadowOpacity = 0.5;
    self.card.alpha = 0;
    self.card.transform = CGAffineTransformMakeScale(0.92, 0.92);
    [root addSubview:self.card];

    // Card content container (clipped)
    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.layer.cornerRadius = 22;
    content.clipsToBounds = YES;
    content.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
    [self.card addSubview:content];

    // ── Header (gradient) ──
    self.header = [GradientView new];
    self.header.translatesAutoresizingMaskIntoConstraints = NO;
    self.header.gradient.colors = @[
        (id)[UIColor colorWithRed:0.15 green:0.22 blue:0.55 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.45 green:0.20 blue:0.70 alpha:1.0].CGColor,
    ];
    self.header.gradient.startPoint = CGPointMake(0, 0);
    self.header.gradient.endPoint = CGPointMake(1, 1);
    [content addSubview:self.header];

    // Icon glyph
    UIView *iconBg = [UIView new];
    iconBg.translatesAutoresizingMaskIntoConstraints = NO;
    iconBg.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    iconBg.layer.cornerRadius = 14;
    [self.header addSubview:iconBg];

    self.iconGlyph = [UILabel new];
    self.iconGlyph.translatesAutoresizingMaskIntoConstraints = NO;
    self.iconGlyph.text = @"⚙";
    self.iconGlyph.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    self.iconGlyph.textColor = UIColor.whiteColor;
    self.iconGlyph.textAlignment = NSTextAlignmentCenter;
    [iconBg addSubview:self.iconGlyph];

    self.titleLbl = [UILabel new];
    self.titleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLbl.text = @"Il2CppDumper";
    self.titleLbl.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    self.titleLbl.textColor = UIColor.whiteColor;
    [self.header addSubview:self.titleLbl];

    self.subtitleLbl = [UILabel new];
    self.subtitleLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLbl.text = @"Extracting metadata…";
    self.subtitleLbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.subtitleLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.85];
    [self.header addSubview:self.subtitleLbl];

    // ── Body ──

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.color = [UIColor colorWithWhite:1.0 alpha:0.8];
    self.spinner.hidesWhenStopped = YES;
    [self.spinner startAnimating];
    [content addSubview:self.spinner];

    self.statusLbl = [UILabel new];
    self.statusLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLbl.text = @"Initializing…";
    self.statusLbl.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.statusLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    self.statusLbl.textAlignment = NSTextAlignmentCenter;
    self.statusLbl.numberOfLines = 2;
    self.statusLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:self.statusLbl];

    self.progressBar = [[GradientProgressBar alloc] initWithFrame:CGRectZero];
    self.progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.progressBar];

    self.percentLbl = [UILabel new];
    self.percentLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.percentLbl.text = @"0%";
    self.percentLbl.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    self.percentLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    self.percentLbl.textAlignment = NSTextAlignmentRight;
    [content addSubview:self.percentLbl];

    self.statsLbl = [UILabel new];
    self.statsLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.statsLbl.text = @"—";
    self.statsLbl.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    self.statsLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    self.statsLbl.textAlignment = NSTextAlignmentCenter;
    [content addSubview:self.statsLbl];

    self.pathLbl = [UILabel new];
    self.pathLbl.translatesAutoresizingMaskIntoConstraints = NO;
    self.pathLbl.text = @"";
    self.pathLbl.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    self.pathLbl.textColor = [UIColor colorWithWhite:1.0 alpha:0.55];
    self.pathLbl.textAlignment = NSTextAlignmentCenter;
    self.pathLbl.numberOfLines = 3;
    self.pathLbl.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.pathLbl.hidden = YES;
    [content addSubview:self.pathLbl];

    // Share button — hidden until success state
    self.shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shareButton setTitle:@"  Share" forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
        UIImage *icon = [UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:cfg];
        [self.shareButton setImage:icon forState:UIControlStateNormal];
        self.shareButton.tintColor = UIColor.whiteColor;
    }
    self.shareButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.shareButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.shareButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.55 blue:1.0 alpha:0.35];
    self.shareButton.layer.cornerRadius = 12;
    self.shareButton.hidden = YES;
    [self.shareButton addTarget:self action:@selector(handleShareTap) forControlEvents:UIControlEventTouchUpInside];

    // Action (OK / Dismiss)
    self.actionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.actionButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionButton setTitle:@"Please wait…" forState:UIControlStateNormal];
    self.actionButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.actionButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.actionButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    self.actionButton.layer.cornerRadius = 12;
    self.actionButton.enabled = NO;
    self.actionButton.alpha = 0.5;
    [self.actionButton addTarget:self action:@selector(handleActionTap) forControlEvents:UIControlEventTouchUpInside];

    // Button row
    self.buttonRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.shareButton, self.actionButton]];
    self.buttonRow.translatesAutoresizingMaskIntoConstraints = NO;
    self.buttonRow.axis = UILayoutConstraintAxisHorizontal;
    self.buttonRow.distribution = UIStackViewDistributionFillEqually;
    self.buttonRow.spacing = 10;
    [content addSubview:self.buttonRow];

    // Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [self.card.widthAnchor constraintEqualToConstant:320],

        [content.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:self.card.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],

        // Header
        [self.header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [self.header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.header.topAnchor constraintEqualToAnchor:content.topAnchor],
        [self.header.heightAnchor constraintEqualToConstant:92],

        [iconBg.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor constant:18],
        [iconBg.centerYAnchor constraintEqualToAnchor:self.header.centerYAnchor],
        [iconBg.widthAnchor constraintEqualToConstant:56],
        [iconBg.heightAnchor constraintEqualToConstant:56],

        [self.iconGlyph.leadingAnchor constraintEqualToAnchor:iconBg.leadingAnchor],
        [self.iconGlyph.trailingAnchor constraintEqualToAnchor:iconBg.trailingAnchor],
        [self.iconGlyph.topAnchor constraintEqualToAnchor:iconBg.topAnchor],
        [self.iconGlyph.bottomAnchor constraintEqualToAnchor:iconBg.bottomAnchor],

        [self.titleLbl.leadingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:14],
        [self.titleLbl.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor constant:-16],
        [self.titleLbl.topAnchor constraintEqualToAnchor:iconBg.topAnchor constant:4],

        [self.subtitleLbl.leadingAnchor constraintEqualToAnchor:self.titleLbl.leadingAnchor],
        [self.subtitleLbl.trailingAnchor constraintEqualToAnchor:self.titleLbl.trailingAnchor],
        [self.subtitleLbl.topAnchor constraintEqualToAnchor:self.titleLbl.bottomAnchor constant:4],

        // Spinner + status
        [self.spinner.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.statusLbl.centerYAnchor],
        [self.spinner.widthAnchor constraintEqualToConstant:18],

        [self.statusLbl.leadingAnchor constraintEqualToAnchor:self.spinner.trailingAnchor constant:10],
        [self.statusLbl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.statusLbl.topAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:22],

        // Progress
        [self.progressBar.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.progressBar.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-60],
        [self.progressBar.topAnchor constraintEqualToAnchor:self.statusLbl.bottomAnchor constant:18],
        [self.progressBar.heightAnchor constraintEqualToConstant:10],

        [self.percentLbl.leadingAnchor constraintEqualToAnchor:self.progressBar.trailingAnchor constant:8],
        [self.percentLbl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.percentLbl.centerYAnchor constraintEqualToAnchor:self.progressBar.centerYAnchor],

        // Stats
        [self.statsLbl.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.statsLbl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.statsLbl.topAnchor constraintEqualToAnchor:self.progressBar.bottomAnchor constant:14],

        // Path (hidden until complete)
        [self.pathLbl.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:16],
        [self.pathLbl.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-16],
        [self.pathLbl.topAnchor constraintEqualToAnchor:self.statsLbl.bottomAnchor constant:8],

        // Button row
        [self.buttonRow.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [self.buttonRow.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [self.buttonRow.heightAnchor constraintEqualToConstant:44],
        [self.buttonRow.topAnchor constraintEqualToAnchor:self.pathLbl.bottomAnchor constant:14],
        [self.buttonRow.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
    ]];
}

#pragma mark - Public API

- (void)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.visible) return;
        [self ensureBuilt];
        [self.window makeKeyAndVisible];
        self.visible = YES;
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.backdrop.alpha = 1.0;
            self.card.alpha = 1.0;
            self.card.transform = CGAffineTransformIdentity;
        } completion:nil];
    });
}

- (void)setProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBuilt];
        [self.progressBar setProgress:progress];
        self.percentLbl.text = [NSString stringWithFormat:@"%d%%", (int)roundf(progress * 100)];
    });
}

- (void)setStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBuilt];
        self.statusLbl.text = status ?: @"";
    });
}

- (void)setStatsWithAssemblies:(NSInteger)a classes:(NSInteger)c methods:(NSInteger)m {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBuilt];
        self.statsLbl.text = [NSString stringWithFormat:@"%ld asm · %ld classes · %ld methods",
            (long)a, (long)c, (long)m];
    });
}

- (void)showSuccessWithMessage:(NSString *)msg path:(NSString *)path {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBuilt];
        self.state = DumperHUDStateSuccess;
        self.sharePath = path;
        [self.spinner stopAnimating];
        [self.progressBar setProgress:1.0];
        self.percentLbl.text = @"100%";
        self.iconGlyph.text = @"✓";
        self.subtitleLbl.text = @"Completed successfully";
        self.statusLbl.text = msg ?: @"Done!";
        self.pathLbl.text = path ?: @"";
        self.pathLbl.hidden = NO;
        // Green gradient
        self.header.gradient.colors = @[
            (id)[UIColor colorWithRed:0.18 green:0.55 blue:0.35 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.10 green:0.65 blue:0.55 alpha:1.0].CGColor,
        ];
        [self.progressBar setTintColorsStart:[UIColor colorWithRed:0.4 green:0.9 blue:0.6 alpha:1.0]
                                         end:[UIColor colorWithRed:0.2 green:1.0 blue:0.7 alpha:1.0]];
        [self.actionButton setTitle:@"Done" forState:UIControlStateNormal];
        self.actionButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.14];
        self.actionButton.enabled = YES;
        self.actionButton.alpha = 1.0;

        // Reveal share button with a subtle animation
        BOOL canShare = path && [[NSFileManager defaultManager] fileExistsAtPath:path];
        if (canShare) {
            self.shareButton.hidden = NO;
            self.shareButton.alpha = 0;
            self.shareButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
            [UIView animateWithDuration:0.3 delay:0.1 usingSpringWithDamping:0.75 initialSpringVelocity:0.5
                                options:0 animations:^{
                self.shareButton.alpha = 1.0;
                self.shareButton.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    });
}

- (void)handleShareTap {
    if (!self.sharePath) return;
    NSURL *fileURL = [NSURL fileURLWithPath:self.sharePath];
    UIActivityViewController *vc = [[UIActivityViewController alloc]
        initWithActivityItems:@[fileURL] applicationActivities:nil];
    // iPad support
    vc.popoverPresentationController.sourceView = self.shareButton;
    vc.popoverPresentationController.sourceRect = self.shareButton.bounds;

    UIViewController *presenter = self.window.rootViewController;
    [presenter presentViewController:vc animated:YES completion:nil];
}

- (void)showErrorWithMessage:(NSString *)msg {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self ensureBuilt];
        self.state = DumperHUDStateError;
        self.shareButton.hidden = YES;
        [self.spinner stopAnimating];
        self.iconGlyph.text = @"!";
        self.subtitleLbl.text = @"Something went wrong";
        self.statusLbl.text = msg ?: @"Unknown error";
        self.statsLbl.text = @"";
        self.pathLbl.hidden = YES;
        // Red gradient
        self.header.gradient.colors = @[
            (id)[UIColor colorWithRed:0.75 green:0.20 blue:0.25 alpha:1.0].CGColor,
            (id)[UIColor colorWithRed:0.90 green:0.35 blue:0.20 alpha:1.0].CGColor,
        ];
        [self.progressBar setTintColorsStart:[UIColor systemRedColor]
                                         end:[UIColor systemOrangeColor]];
        [self.actionButton setTitle:@"Dismiss" forState:UIControlStateNormal];
        self.actionButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:0.35];
        self.actionButton.enabled = YES;
        self.actionButton.alpha = 1.0;
    });
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.visible) return;
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            self.backdrop.alpha = 0;
            self.card.alpha = 0;
            self.card.transform = CGAffineTransformMakeScale(0.94, 0.94);
        } completion:^(BOOL finished) {
            self.window.hidden = YES;
            self.visible = NO;
        }];
    });
}

- (void)handleActionTap {
    [self dismiss];
}

@end
