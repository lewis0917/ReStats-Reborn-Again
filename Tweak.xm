// ─────────────────────────────────────────────────────────────────────────────
// ReStats — Tweak.xm (Fixed & Optimized)
// Rootless rewrite: ElleKit · iOS 15–18 · arm64 + arm64e
// ─────────────────────────────────────────────────────────────────────────────

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

// Forward declare PSCellType enum in case Preferences headers lack it
#ifndef PSLinkListCell
#define PSLinkListCell 6
#endif

// Private API additions
@interface PSListController (ReStatsAdditions)
- (void)_reStatsPerformReset;
@end

@interface PSSpecifier (RSSubscript)
- (id)objectForKeyedSubscript:(NSString *)key;
- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;
@end

// Preference key constants
extern NSString *const PSValuesKey;
extern NSString *const PSTitlesKey;
extern NSString *const PSDefaultValueKey;
extern NSString *const PSDefaultsKey;
extern NSString *const PSKeyNameKey;

// Storage
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

// Date arithmetic
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

// Context detection
static BOOL RSIsCellularController(__unsafe_unretained PSListController *ctrl) {
    NSString *cn = NSStringFromClass([ctrl class]);
    if ([cn containsString:@"Cellular"] || [cn containsString:@"DataUsage"]) return YES;

    NSString *bid = [NSBundle bundleForClass:[ctrl class]].bundleIdentifier;
    if ([[bid lowercaseString] containsString:@"cellular"]) return YES;

    static NSArray *resetCandidates;
    static dispatch_once_t _rt;
    dispatch_once(&_rt, ^{
        resetCandidates = @[
            @"resetStatistics:",
            @"resetCellularStatistics:",
            @"resetAllCellularStatistics:",
            @"_resetDataCounters",
            @"cellularResetStatistics:",
            @"performResetStatistics"
        ];
    });
    for (NSString *selName in resetCandidates) {
        if ([ctrl respondsToSelector:NSSelectorFromString(selName)]) return YES;
    }

    return NO;
}

// Runtime reset-selector discovery
static SEL RSFindResetSelector(__unsafe_unretained id target) {
    static NSArray *candidates;
    static dispatch_once_t _ct;
    dispatch_once(&_ct, ^{
        candidates = @[
            @"resetStatistics:",
            @"resetCellularStatistics:",
            @"resetAllCellularStatistics:",
            @"_resetDataCounters",
            @"cellularResetStatistics:",
            @"performResetStatistics"
        ];
    });
    for (NSString *name in candidates) {
        SEL s = NSSelectorFromString(name);
        if ([target respondsToSelector:s]) return s;
    }
    return NULL;
}

static BOOL RSAlreadyInjected(NSArray *specs) {
    for (PSSpecifier *sp in specs) {
        if ([sp respondsToSelector:@selector(identifier)] &&
            [[sp identifier] isEqualToString:@"RSIntervalPicker"]) return YES;
    }
    return NO;
}

// Default hook group
%hook PSListController

- (NSArray *)specifiers {
    NSArray *orig = %orig;
    if (!RSIsCellularController(self) || RSAlreadyInjected(orig)) return orig;

    Class listItemsCtrl = NSClassFromString(@"PSListItemsController");

        PSSpecifier *picker = [%c(PSSpecifier)
        preferenceSpecifierNamed:@"Auto-Reset Interval"
                         target:self
                            set:@selector(rsSetInterval:specifier:)
                            get:@selector(rsGetInterval:)
                         detail:listItemsCtrl
                           cell:(PSCellType)6 // Cast integer literal to PSCellType
                           edit:nil];

    [picker setIdentifier:@"RSIntervalPicker"];

    // Use setProperty:forKey: instead of setObject:forKey:
    [picker setProperty:kRSSuite forKey:@"defaults"];
    [picker setProperty:kRSInterval forKey:@"key"];
    [picker setProperty:kRSSuite forKey:@"defaultsDomain"];

    NSMutableArray *mut = [orig mutableCopy];
    NSUInteger insertAt = (mut.count > 1) ? (mut.count - 1) : mut.count;
    [mut insertObject:picker atIndex:insertAt];
    return [mut copy];
}

%new
- (id)rsGetInterval:(PSSpecifier *)__unused spec {
    return @(RSIntervalDays());
}

%new
- (void)rsSetInterval:(id)value specifier:(PSSpecifier *)__unused spec {
    [RSPrefs() setInteger:[value integerValue] forKey:kRSInterval];
    [RSPrefs() synchronize];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    if (!RSIsCellularController(self) || !RSResetOverdue()) return;

    __weak PSListController *ws = self;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{ [ws _reStatsPerformReset]; }
    );
}

%new
- (void)_reStatsPerformReset {
    SEL resetSel = RSFindResetSelector(self);

    if (resetSel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:resetSel withObject:nil];
#pragma clang diagnostic pop
        RSRecordReset();
        return;
    }

    for (PSSpecifier *sp in [self specifiers]) {
        if (![sp respondsToSelector:@selector(identifier)]) continue;
        NSString *ident = [(id)sp identifier] ?: @"";
        if (![ident.lowercaseString containsString:@"reset"]) continue;

        SEL action = sp.buttonAction;
        if (!action || ![self respondsToSelector:action]) continue;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self performSelector:action withObject:sp];
#pragma clang diagnostic pop
        RSRecordReset();
        return;
    }
}

%end

// Manual Reset Sync Group
%group RSManualSync

%hook PSListController
- (void)resetStatistics:(id)specifier {
    %orig(specifier);
    if (RSIsCellularController(self)) RSRecordReset();
}
%end

%end

// Constructor
%ctor {
    %init;
    Class plc = NSClassFromString(@"PSListController");
    if (plc && [plc instancesRespondToSelector:@selector(resetStatistics:)]) {
        %init(RSManualSync);
    }
}
