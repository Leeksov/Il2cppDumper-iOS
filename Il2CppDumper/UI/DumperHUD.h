//
//  DumperHUD.h — beautiful in-app dump status overlay
//

#pragma once
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DumperHUDState) {
    DumperHUDStateProgress = 0,
    DumperHUDStateSuccess  = 1,
    DumperHUDStateError    = 2,
};

@interface DumperHUD : NSObject

+ (instancetype)shared;

// Show the HUD (on main thread-safe)
- (void)show;

// Progress updates — 0.0..1.0
- (void)setProgress:(float)progress;
- (void)setStatus:(NSString *)status;
- (void)setStatsWithAssemblies:(NSInteger)asmCount
                       classes:(NSInteger)classCount
                       methods:(NSInteger)methodCount;

// Terminal states
- (void)showSuccessWithMessage:(NSString *)msg path:(NSString *)path;
- (void)showErrorWithMessage:(NSString *)msg;

// Hide immediately
- (void)dismiss;

@end
