// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (v24 · ARC & Deprecation Fixes)
// Rootless · ElleKit · iOS 15–18 · arm64 + arm64e
// Target: PSUICellularController (com.apple.telephony.CellularSettingsUI)
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UserNotifications/UserNotifications.h>

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

static NSString *const kRSSuite          = @"com.lo.restats";
static NSString *const kRSInterval       = @"resetIntervalDays";
static NSString *const kRSLastReset      = @"lastResetTimestamp";
static NSString *const kRSNotificationID = @"com.lo.restats.resetdue";

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

// ─── Notification scheduling ──────────────────────────────────────────────────

static void RSScheduleNotification(void) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];

    [center removePendingNotificationRequestsWithIdentifiers:@[kRSNotificationID]];

    NSInteger days = RSIntervalDays();
    if (days <= 0) return;

    NSDate *base  = RSLastResetDate() ?: [NSDate date];
    NSCalendar *cal = NSCalendar.currentCalendar;

    NSDateComponents *delta = [NSDateComponents new];
    delta.day = days;
    NSDate *fireDate = [cal dateByAddingComponents:delta toDate:base options:0];

    NSDateComponents *fire = [cal
        components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|
                   NSCalendarUnitHour|NSCalendarUnitMinute
          fromDate:fireDate];

    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = @"Mobile Data Reset Due";
    content.body  = [NSString stringWithFormat:
        @"Your %ld-day cycle is complete. Tap to open Mobile Data and reset statistics.",
        (long)days];
    content.sound = UNNotificationSound.defaultSound;

    UNCalendarNotificationTrigger *trigger =
        [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:fire
                                                                repeats:NO];

    UNNotificationRequest *request =
        [UNNotificationRequest requestWithIdentifier:kRSNotificationID
                                             content:content
                                             trigger:trigger];

    [center addNotificationRequest:request withCompletionHandler:^(NSError *err) {
        if (err) NSLog(@"[ReStats] notification schedule error: %@", err);
    }];
}

static void RSRequestPermissionThenSchedule(void) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:UNAuthorizationOptionAlert|UNAuthorizationOptionSound
                          completionHandler:^(BOOL granted, NSError *error) {
        if (granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ RSScheduleNotification(); });
        }
    }];
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
    [picker setProperty:@YES forKey:@"enabled"];

    [specs addObject:group];
    [specs addObject:picker];

    [self setValue:specs forKey:@"_specifiers"];
    return specs;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    if (RSResetOverdue()) {
        PSUICellularController *selfRef = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC),
            dispatch_get_main_queue(),
            ^{ [selfRef _reStatsPerformReset]; }
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
    NSDate *last  = RSLastResetDate();
    NSInteger days = RSIntervalDays();

    if (!last) {
        return @"A notification will remind you when your reset cycle is due. "
                "Local reset counts differ from your carrier's billing tally — "
                "always verify remaining data directly with your provider.";
    }

    NSDateComponents *elapsed = [[NSCalendar currentCalendar]
        components:NSCalendarUnitDay
          fromDate:last
            toDate:[NSDate date]
           options:0];

    NSString *nextLine = (days > 0)
        ? [NSString stringWithFormat:@"Next reset notification in %ld day%@.",
           (long)(days - elapsed.day),
           (days - elapsed.day == 1) ? @"" : @"s"]
        : @"Automatic reset is disabled.";

    return [NSString stringWithFormat:
        @"%@ Local statistics are offset from your carrier's billing cycle — "
         "verify remaining data directly with your provider.", nextLine];
}

%new
- (void)rsOpenIntervalPicker:(PSSpecifier *)spec {
    NSArray<NSString *> *titles = RSTitles();
    NSArray<NSNumber *> *values = RSValues();

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Auto-Reset Interval"
                         message:@"A notification will remind you when the cycle is due. "
                                  "Opening the notification brings you here to reset automatically."
                  preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSUInteger i = 0; i < titles.count; i++) {
        NSInteger days = [values[i] integerValue];
        [alert addAction:[UIAlertAction
            actionWithTitle:titles[i]
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
            [RSPrefs() setInteger:days forKey:kRSInterval];
            [RSPrefs() synchronize];

            RSRequestPermissionThenSchedule();

            [spec setName:[self rsFormattedTitle]];

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
        RSScheduleNotification();

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
        RSScheduleNotification();
    }
}

%end
