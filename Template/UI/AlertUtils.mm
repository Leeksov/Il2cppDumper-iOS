//
//  AlertUtils.mm
//  Il2CppDumper
//

#include "AlertUtils.h"

static UIWindow* _alertWindow = nil;

static UIWindow* getAlertWindow() {
    if (!_alertWindow) {
        _alertWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _alertWindow.windowLevel = UIWindowLevelAlert + 1;
        _alertWindow.rootViewController = [UIViewController new];
    }
    return _alertWindow;
}

static void presentAlert(UIAlertController *ac) {
    UIWindow *w = getAlertWindow();
    [w makeKeyAndVisible];
    [w.rootViewController presentViewController:ac animated:YES completion:nil];
}

static void dismissAlertWindow() {
    if (_alertWindow) {
        _alertWindow.hidden = YES;
        _alertWindow = nil;
    }
}

void showWaiting(NSString *msg, UIAlertController *__strong *alert)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:___ALERT_TITLE
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        spinner.translatesAutoresizingMaskIntoConstraints = NO;
        [spinner startAnimating];
        [ac.view addSubview:spinner];
        [NSLayoutConstraint activateConstraints:@[
            [spinner.centerXAnchor constraintEqualToAnchor:ac.view.centerXAnchor],
            [spinner.bottomAnchor constraintEqualToAnchor:ac.view.bottomAnchor constant:-20]
        ]];
        *alert = ac;
        presentAlert(ac);
    });
}

void dismisWaiting(UIAlertController *alert)
{
    if (!alert) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [alert dismissViewControllerAnimated:YES completion:^{ dismissAlertWindow(); }];
    });
}

void showSuccess(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:___ALERT_TITLE
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            dismissAlertWindow();
        }]];
        presentAlert(ac);
    });
}

void showInfo(NSString *msg, float duration)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:___ALERT_TITLE
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        presentAlert(ac);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ac dismissViewControllerAnimated:YES completion:^{ dismissAlertWindow(); }];
        });
    });
}

void showError(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:___ALERT_TITLE
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            dismissAlertWindow();
        }]];
        presentAlert(ac);
    });
}

void showWarning(NSString *msg)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:___ALERT_TITLE
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            dismissAlertWindow();
        }]];
        presentAlert(ac);
    });
}
