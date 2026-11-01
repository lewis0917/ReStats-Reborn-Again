#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

// ── Close any earlier hooks if they exist above this line ──

%hook PSUICellularController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    // ── Diagnostic selector dump ──
    NSMutableString *out = [NSMutableString string];
    Class cls = [self class];
    while (cls && cls != [NSObject class]) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = name.lowercaseString;
            if ([lower containsString:@"reset"] ||
                [lower containsString:@"stat"]  ||
                [lower containsString:@"counter"] ||
                [lower containsString:@"clear"]) {
                [out appendFormat:@"%@ -> %@\n", NSStringFromClass(cls), name];
            }
        }
        free(methods);
        cls = class_getSuperclass(cls);
    }

    [out writeToFile:@"/var/jb/tmp/restats_selectors.txt"
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];
}

%end
