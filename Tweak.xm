// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (Crash Fix & Final Build)
// Rootless rewrite: ElleKit · iOS 15–18 · arm64 + arm64e
// Target Class: PSUICellularController (com.apple.telephony.CellularSettingsUI)
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface PSUICellularController : PSListController
@end

#ifndef PSLinkListCell
#define PSLinkListCell 6
#endif

// Private API additions
@interface PSListController (ReStatsAdditions)
- (void)_reStatsPerformReset;
@end

// Preference storage
static NSString *const kRSSuite      = @"com.lo.restats";
static NSString *const kRSInterval   = @"resetIntervalDays";    // NSInteger; 0 = disabled
static NSString *const kRSLastReset  = @"lastResetTimestamp";   // double (POSIX epoch)

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
// Dynamic Hooking on PSUICellularController
// ─────────────────────────────────────────────────────────────────────────────

%hook PSUICellularController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    // Prevent duplicate row injection if already present
    if ([self specifierForID:@"RSIntervalPicker"] != nil) return;

    Class listItemsCtrl = NSClassFromString(@"PSListItemsController");

    PSSpecifier *picker = [%c(PSSpecifier)
        preferenceSpecifierNamed:@"Auto-Reset Interval"
                         target:self
                            set:@selector(rsSetInterval:specifier:)
                            get:@selector(rsGetInterval:)
                         detail:listItemsCtrl
                           cell:(PSCellType)6
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];

    NSArray *values = @[@0, @7, @14, @30, @60, @90];
    NSArray *titles = @[@"Disabled", @"Every 7 Days", @"Every 14 Days", @"Monthly (30 Days)", @"Every 60 Days", @"Every 90 Days"];

    [picker setProperty:values forKey:@"values"];
    [picker setProperty:titles forKey:@"titles"];
    [picker setProperty:@0 forKey:@"default"];
    
    // Required by PSListItemsController when selecting options
    [picker setProperty:kRSSuite forKey:@"defaults"];
    [picker setProperty:kRSInterval forKey:@"key"];
    [picker setProperty:kRSSuite forKey:@"defaultsDomain"];

    // Dynamically insert into table view
    [self addSpecifier:picker animated:NO];

    // Trigger reset evaluation if overdue
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
- (id)rsGetInterval:(PSSpecifier *)spec {
    return @(RSIntervalDays());
}

%new
- (void)rsSetInterval:(id)value specifier:(PSSpecifier *)spec {
    NSInteger days = [value integerValue];
    [RSPrefs() setInteger:days forKey:kRSInterval];
    [RSPrefs() synchronize];
    [self reloadSpecifier:spec animated:YES];
}

%new
- (void)_reStatsPerformReset {
    NSArray *candidates = @[
        @"resetStatistics:",
        @"resetCellularStatistics:",
        @"_resetDataCounters",
        @"cellularResetStatistics:",
        @"performResetStatistics"
    ];
    
    for (NSString *name in candidates) {
        SEL s = NSSelectorFromString(name);
        if (![self respondsToSelector:s]) continue;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:s withObject:nil];
#pragma clang diagnostic pop
        RSRecordReset();
        return;
    }
}

%end

// Manual Reset Tracker
%hook PSListController
- (void)resetStatistics:(id)specifier {
    %orig(specifier);
    RSRecordReset();
}
%end
