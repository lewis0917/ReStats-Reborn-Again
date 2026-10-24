// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (v10 · associated object specifier injection)
// Rootless · ElleKit · iOS 15–18 · arm64 + arm64e
// Target: PSUICellularController (com.apple.telephony.CellularSettingsUI)
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <objc/runtime.h>

@interface PSUICellularController : PSListController
@end

#ifndef PSLinkListCell
#define PSLinkListCell 6
#endif

@interface PSUICellularController (ReStatsAdditions)
- (void)_reStatsPerformReset;
@end

// ─── Preference storage ───────────────────────────────────────────────────────

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

// ─── PSUICellularController hook ──────────────────────────────────────────────

static const char *kRSCachedSpecifiersKey = "RSCachedSpecifiersKey";

%hook PSUICellularController

- (NSMutableArray *)specifiers {
    // 1. If we already injected and cached our array on this controller instance, return it immediately.
    // Returning the EXACT same pointer identity prevents table group desync & scroll crashes.
    NSMutableArray *cached = objc_getAssociatedObject(self, kRSCachedSpecifiersKey);
    if (cached) {
        return cached;
    }

    // 2. Fetch the original specifier array
    NSArray *orig = %orig;
    if (!orig || orig.count == 0) return (NSMutableArray *)orig;

    // 3. Make a single mutable copy
    NSMutableArray *specs = [orig mutableCopy];

    // Check if item was somehow already added
    for (PSSpecifier *s in specs) {
        if ([[s identifier] isEqualToString:@"RSIntervalPicker"]) {
            objc_setAssociatedObject(self, kRSCachedSpecifiersKey, specs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return specs;
        }
    }

    // 4. Construct our PSLinkListCell specifier
    Class listItemsCtrl = NSClassFromString(@"PSListItemsController");

    PSSpecifier *picker = [NSClassFromString(@"PSSpecifier")
        preferenceSpecifierNamed:@"Auto-Reset Interval"
                         target:self
                            set:@selector(rsSetInterval:specifier:)
                            get:@selector(rsGetInterval:)
                         detail:listItemsCtrl
                           cell:(PSCellType)PSLinkListCell
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];
    [picker setProperty:@[@0, @7, @14, @30, @60, @90]
                 forKey:@"values"];
    [picker setProperty:@[@"Disabled", @"Every 7 Days", @"Every 14 Days",
                          @"Monthly (30 Days)", @"Every 60 Days", @"Every 90 Days"]
                 forKey:@"titles"];
    [picker setProperty:@0                forKey:@"default"];
    [picker setProperty:kRSSuite          forKey:@"defaults"];
    [picker setProperty:kRSInterval       forKey:@"key"];
    [picker setProperty:@"PSLinkListCell" forKey:@"cellClass"];

    // Append to array
    [specs addObject:picker];

    // 5. Store the augmented array instance on 'self' so all future calls during scrolling return this exact array.
    objc_setAssociatedObject(self, kRSCachedSpecifiersKey, specs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

// ─── Manual reset tracker ─────────────────────────────────────────────────────

%hook PSListController

- (void)resetStatistics:(id)specifier {
    %orig(specifier);
    if ([self isKindOfClass:%c(PSUICellularController)]) {
        RSRecordReset();
    }
}

%end
