//
//  AlertUtils.h
//  Il2CppDumper
//

#pragma once

#import <UIKit/UIKit.h>

#define ___ALERT_TITLE @"Dumper by Eux (Asura)"

void showWaiting(NSString *msg, UIAlertController* __strong *alert);
void dismisWaiting(UIAlertController *al);

void showSuccess(NSString *msg);
void showInfo(NSString *msg, float duration);
void showError(NSString *msg);
void showWarning(NSString *msg);
