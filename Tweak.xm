// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Introspection Diagnostic Tool
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>

%hook PSListController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    NSString *className = NSStringFromClass([self class]);
    NSString *bundleID = [NSBundle bundleForClass:[self class]].bundleIdentifier ?: @"Unknown Bundle";

    // Format banner text
    NSString *msg = [NSString stringWithFormat:@"Class:\n%@\n\nBundle:\n%@", className, bundleID];

    // Display alert directly inside Settings UI
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ReStats Inspector"
                                                                   message:msg
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];

    [self presentViewController:alert animated:YES completion:nil];
}

%end
