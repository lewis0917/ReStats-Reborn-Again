// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (v22 · prototype + UX context)
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
- (NSString *)rsFormattedTitle;
- (NSString *)rsFooterText;
@end

#ifndef PSButtonCell
#define PSButtonCell 7
#endif

#ifndef PSGroupCell
#define PSGroupCell 0
#endif

static NSString *const kRSSuite     = @"com.lo.restats";
static NSString *const kRSInterval  = @"resetIntervalDays";
static NSString *const kRSLastReset = @"lastResetTimestamp";

static NSArray<NSNumber *> *RSValues(void) {
    return @[@0, @7, @14, @30, @60, @90];
}

static NSArray<NSString *> *RSTitles(void) {
    return @[@"Disabled", @"Every 7 Days", @"Every 14 Days",
             @"Monthly (30 Days)", @"Every 60 Days", @"Every 90 Days"];
}

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

// ─────────────────────────────────────────────────────────────────────────────

%hook PSUICellularController

- (NSMutableArray *)specifiers {
    NSMutableArray *orig = %orig;
    if (!orig || orig.count == 0) return orig;

    for (PSSpecifier *s in orig) {
        if ([[s identifier] isEqualToString:@"RSGroupHeader"]) return orig;
    }

    NSMutableArray *specs = [orig mutableCopy];

    // Group header — carries the footer disclaimer and last-reset context.
    // PSGroupCell is the section separator type PSListController expects;
    // footerText surfaces below the injected row without any extra specifier.
    PSSpecifier *group = [NSClassFromString(@"PSSpecifier")
        preferenceSpecifierNamed:@"Auto-Reset"
                         target:self
                            set:nil
                            get:nil
                         detail:nil
                           cell:(PSCellType)PSGroupCell
                           edit:nil];

    [group setIdentifier:@"RSGroupHeader"];
    [group setProperty:[self rsFooterText] forKey:@"footerText"];

    // Tappable button row — title encodes current interval + last reset date.
    PSSpecifier *picker = [NSClassFromString(@"PSSpecifier")
        preferenceSpecifierNamed:[self rsFormattedTitle]
                         target:self
                            set:nil
                            get:nil
                         detail:nil
                           cell:(PSCellType)PSButtonCell
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];
    [picker setButtonAction:@selector(rsOpenIntervalPicker:)];

    [specs addObject:group];
    [specs addObject:picker];

    [self setValue:specs forKey:@"_specifiers"];
    return specs;
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
- (NSString *)rsFormattedTitle {
    NSInteger current = RSIntervalDays();
    NSArray<NSNumber *> *values = RSValues();
    NSArray<NSString *> *titles = RSTitles();

    NSString *intervalLabel = @"Disabled";
    for (NSUInteger i = 0; i < values.count; i++) {
        if ([values[i] integerValue] == current) {
            intervalLabel = titles[i];
            break;
        }
    }

    NSDate *last = RSLastResetDate();
    if (last && current > 0) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        return [NSString stringWithFormat:@"%@ · Last reset: %@",
                intervalLabel, [fmt stringFromDate:last]];
    }

    return [NSString stringWithFormat:@"Auto-Reset: %@", intervalLabel];
}

%new
- (NSString *)rsFooterText {
    NSDate *last = RSLastResetDate();
    NSInteger days = RSIntervalDays();

    if (!last) {
        return @"Statistics have not been automatically reset yet. "
                "Local reset counts differ from your carrier's billing tally — "
                "always verify remaining data directly with your provider.";
    }

    NSDateComponents *elapsed = [[NSCalendar currentCalendar]
        components:NSCalendarUnitDay
          fromDate:last
            toDate:[NSDate date]
           options:0];

    NSString *nextLine = (days > 0)
        ? [NSString stringWithFormat:@"Next automatic reset in %ld day%@.",
           (long)(days - elapsed.day),
           (days - elapsed.day == 1) ? @"" : @"s"]
        : @"Automatic reset is disabled.";

    return [NSString stringWithFormat:
        @"%@ Local statistics are offset from your carrier's billing cycle — "
         "verify remaining data directly with your provider.",
        nextLine];
}

%new
- (void)rsOpenIntervalPicker:(PSSpecifier *)spec {
    NSArray<NSString *> *titles = RSTitles();
    NSArray<NSNumber *> *values = RSValues();

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Auto-Reset Interval"
                         message:@"Displayed usage is offset from your carrier's billing cycle. "
                                  "Always verify remaining data with your provider."
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSUInteger i = 0; i < titles.count; i++) {
        NSInteger days = [values[i] integerValue];
        [alert addAction:[UIAlertAction
            actionWithTitle:titles[i]
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
            [RSPrefs() setInteger:days forKey:kRSInterval];
            [RSPrefs() synchronize];

            [spec setName:[self rsFormattedTitle]];

            // Refresh group footer to reflect updated next-reset countdown.
            PSSpecifier *header = [self specifierForID:@"RSGroupHeader"];
            if (header) {
                [header setProperty:[self rsFooterText] forKey:@"footerText"];
                [self reloadSpecifier:header animated:YES];
            }

            UIImpactFeedbackGenerator *haptic = [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleMedium];
            [haptic impactOccurred];

            [self reloadSpecifier:spec animated:YES];
        }]];
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                             style:UIAlertActionStyleCancel
                                           handler:nil]];

    if (alert.popoverPresentationController) {
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

        // Refresh both specifiers so the UI reflects the new reset timestamp
        // immediately without requiring the user to back out and re-enter.
        PSSpecifier *pickerSpec = [self specifierForID:@"RSIntervalPicker"];
        PSSpecifier *headerSpec = [self specifierForID:@"RSGroupHeader"];

        if (pickerSpec) {
            [pickerSpec setName:[self rsFormattedTitle]];
            [self reloadSpecifier:pickerSpec animated:YES];
        }
        if (headerSpec) {
            [headerSpec setProperty:[self rsFooterText] forKey:@"footerText"];
            [self reloadSpecifier:headerSpec animated:YES];
        }

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
