// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (v4 · cellClass Fix)
// Rootless · ElleKit · iOS 15–18 · arm64 + arm64e
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

// Forward declaration scoped to the actual subclass — _reStatsPerformReset
// lives on PSUICellularController, not PSListController.
@interface PSUICellularController (ReStatsAdditions)
- (void)_reStatsPerformReset;
@end

// ─── Preference storage ───────────────────────────────────────────────────────

static NSString *const kRSSuite     = @"com.lo.restats";
static NSString *const kRSInterval  = @"resetIntervalDays";   // NSInteger; 0 = disabled
static NSString *const kRSLastReset = @"lastResetTimestamp";  // double (POSIX epoch)

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

// ─── PSUICellularController hook ──────────────────────────────────────────────

%hook PSUICellularController

- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);

    if ([self specifierForID:@"RSIntervalPicker"] != nil) return;

    Class listItemsCtrl = NSClassFromString(@"PSListItemsController");

    // NSClassFromString is safer than %c() here — resolves gracefully if the
    // class image hasn't been mapped yet at hook time. Same caveat applies to
    // PSListItemsController above.
    PSSpecifier *picker = [NSClassFromString(@"PSSpecifier")
        preferenceSpecifierNamed:@"Auto-Reset Interval"
                         target:self
                            set:@selector(rsSetInterval:specifier:)
                            get:@selector(rsGetInterval:)
                         detail:listItemsCtrl
                           cell:6   // PSLinkListCell — forced as raw integer
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];

    [picker setProperty:@[@0, @7, @14, @30, @60, @90]
                 forKey:@"values"];
    [picker setProperty:@[@"Disabled", @"Every 7 Days", @"Every 14 Days",
                          @"Monthly (30 Days)", @"Every 60 Days", @"Every 90 Days"]
                 forKey:@"titles"];
    [picker setProperty:@0          forKey:@"default"];

    // PSListItemsController reads these to persist and restore selection state.
    [picker setProperty:kRSSuite    forKey:@"defaults"];
    [picker setProperty:kRSInterval forKey:@"key"];

    // The Preferences framework resolves the cell class from this string key
    // before it reads the cell type integer — without it the integer is ignored
    // and the framework falls back to PSToggleSwitchCell (confirmed by screenshot).
    [picker setProperty:@"PSLinkListCell" forKey:@"cellClass"];

    [self addSpecifier:picker animated:NO];

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
- (id)rsGetInterval:(PSSpecifier *)__unused spec {
    return @(RSIntervalDays());
}

%new
- (void)rsSetInterval:(id)value specifier:(PSSpecifier *)spec {
    [RSPrefs() setInteger:[value integerValue] forKey:kRSInterval];
    [RSPrefs() synchronize];
    [self reloadSpecifier:spec animated:YES];
}

%new
- (void)_reStatsPerformReset {
    NSArray<NSString *> *candidates = @[
        @"resetStatistics:",
        @"resetCellularStatistics:",
        @"cellularResetStatistics:",
        @"_resetDataCounters",      // no-arg — branch below handles the call form
        @"performResetStatistics"   // no-arg
    ];

    for (NSString *name in candidates) {
        SEL s = NSSelectorFromString(name);
        if (![self respondsToSelector:s]) continue;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        // Selectors without a trailing colon take zero arguments.
        // Calling performSelector:withObject: on a zero-arg IMP pushes a value
        // into x2 the callee never reads — UB-adjacent on arm64.
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

// ─── Manual reset tracker ─────────────────────────────────────────────────────
// Hooks at PSListController level because resetStatistics: may be dispatched
// polymorphically from that base, but guards on isKindOfClass: so unrelated
// Settings panes don't stamp a cellular timestamp on their own resets.

%hook PSListController

- (void)resetStatistics:(id)specifier {
    %orig(specifier);
    if ([self isKindOfClass:%c(PSUICellularController)]) {
        RSRecordReset();
    }
}

%end
