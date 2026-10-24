// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (v17 · Enabled PSLinkCell & Tap Interception)
// Rootless · ElleKit · iOS 15–18 · arm64 + arm64e
// Target: PSUICellularController (com.apple.telephony.CellularSettingsUI)
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface PSUICellularController : PSListController
@end

@interface PSUICellularController (ReStatsAdditions)
- (void)_reStatsPerformReset;
- (void)rsOpenIntervalPicker:(PSSpecifier *)spec;
@end

static NSString *const kRSSuite     = @"com.lo.restats";
static NSString *const kRSInterval  = @"resetIntervalDays";
static NSString *const kRSLastReset = @"lastResetTimestamp";

static NSUserDefaults *RSPrefs(void) {
    static NSUserDefaults *_d;
    static dispatch_once_t _t;
    dispatch_once(&_t, ^{
        _d = [[NSUserDefaults alloc] initWithSuiteName:kRSSuite];
    });
    return _d;
}

static NSInteger RSIntervalDays(void) {
    NSInteger v = [RSPrefs() integerForKey:kRSInterval];
    return (v > 0) ? v : 0;
}

static NSDate *RSLastResetDate(void) {
    double ts = [RSPrefs() doubleForKey:kRSLastReset];
    return (ts > 0.0) ? [NSDate dateWithTimeIntervalSince1970:ts] : nil;
}

static void RSRecordReset(void) {
    [RSPrefs() setDouble:NSDate.date.timeIntervalSince1970 forKey:kRSLastReset];
    [RSPrefs() synchronize];
}

static BOOL RSResetOverdue(void) {
    NSInteger days = RSIntervalDays();
    if (days <= 0) return NO;

    NSDate *last = RSLastResetDate();
    if (!last) return YES;

    NSCalendar       *cal   = NSCalendar.currentCalendar;
    NSDateComponents *delta = [[NSDateComponents alloc] init];
    delta.day = days;

    NSDate *nextDue = [cal dateByAddingComponents:delta toDate:last options:0];
    return ([nextDue compare:NSDate.date] == NSOrderedAscending);
}

%hook PSUICellularController

- (NSMutableArray *)specifiers {
    NSMutableArray *orig = %orig;
    if (!orig || orig.count == 0) {
        return orig;
    }

    // Check if our picker is already injected
    for (PSSpecifier *s in orig) {
        if ([[s identifier] isEqualToString:@"RSIntervalPicker"]) {
            return orig;
        }
    }

    NSMutableArray *specs = [orig mutableCopy];

    // PSLinkCell with target + getter ensures the row remains enabled and displays subtitle
    PSSpecifier *picker = [NSClassFromString(@"PSSpecifier")
        preferenceSpecifierNamed:@"Auto-Reset Interval"
                         target:self
                            set:nil
                            get:@selector(rsGetIntervalSubtitle:)
                         detail:nil
                           cell:(PSCellType)PSLinkCell
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];
    [picker setProperty:@YES forKey:@"enabled"];

    [specs addObject:picker];

    [self setValue:specs forKey:@"_specifiers"];

    return specs;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *spec = [self specifierAtIndexPath:indexPath];
    if ([[spec identifier] isEqualToString:@"RSIntervalPicker"]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self rsOpenIntervalPicker:spec];
        return;
    }
    %orig(tableView, indexPath);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    if (RSResetOverdue()) {
        __weak PSUICellularController *ws = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{ [ws _reStatsPerformReset]; }
        );
    }
}

%new
- (id)rsGetIntervalSubtitle:(PSSpecifier *)__unused spec {
    NSInteger days = RSIntervalDays();
    if (days <= 0) return @"Disabled";
    if (days == 30) return @"Monthly (30 Days)";
    return [NSString stringWithFormat:@"Every %ld Days", (long)days];
}

%new
- (void)rsOpenIntervalPicker:(PSSpecifier *)spec {
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"Auto-Reset Interval"
                         message:@"Choose how often to automatically reset mobile data statistics."
                  preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *titles = @[@"Disabled", @"Every 7 Days", @"Every 14 Days", @"Monthly (30 Days)", @"Every 60 Days", @"Every 90 Days"];
    NSArray *values = @[@0, @7, @14, @30, @60, @90];

    for (NSInteger i = 0; i < titles.count; i++) {
        NSInteger days = [values[i] integerValue];
        [alert addAction:[UIAlertAction actionWithTitle:titles[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [RSPrefs() setInteger:days forKey:kRSInterval];
            [RSPrefs() synchronize];

            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];

            [self reloadSpecifier:spec animated:YES];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    if ([alert respondsToSelector:@selector(popoverPresentationController)]) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = self.view.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

%new
- (void)_reStatsPerformReset {
    NSArray<NSString *> *candidates = @[
        @"resetStatistics:",
        @"resetCellularStatistics:",
        @"cellularResetStatistics:",
        @"_resetDataCounters",
        @"performResetStatistics"
    ];

    for (NSString *name in candidates) {
        SEL s = NSSelectorFromString(name);
        if (![self respondsToSelector:s]) continue;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        if ([name hasSuffix:@":"]) {
            [self performSelector:s withObject:nil];
        } else {
            [self performSelector:s];
        }
#pragma clang diagnostic pop

        RSRecordReset();
        return;
    }
}

%end

%hook PSListController

- (void)resetStatistics:(id)specifier {
    %orig(specifier);
    if ([self isKindOfClass:%c(PSUICellularController)]) {
        RSRecordReset();
    }
}

%end
