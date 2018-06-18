#import "INVRegionMonitor.h"

#import <CoreLocation/CoreLocation.h>
#import <React/RCTLog.h>

NSString* INVRegionMonitorDidChangeRegionEvent = @"INVRegionMonitorDidChangeRegionEvent";
NSString* INVRegionMonitorErrorDomain = @"INVRegionMonitorErrorDomain";
NSString* INVRegionMonitorInitialTriggerDwell = @"INVRegionMonitorInitialTriggerDwell";
NSString* INVRegionMonitorInitialTriggerEnter = @"INVRegionMonitorInitialTriggerEnter";
NSString* INVRegionMonitorInitialTriggerExit = @"INVRegionMonitorInitialTriggerExit";

@interface INVRegionMonitor()

@property (nonatomic, strong) NSMutableArray <NSString *> *initialEntryRegionIdentifiers;
@property (nonatomic, strong) NSMutableArray <NSString *> *initialExitRegionIdentifiers;
@property (nonatomic, strong) NSMutableArray <NSString *> *initialStatusRegionIdentifiers;

@end

@implementation INVRegionMonitor

@synthesize locationManager;
@synthesize pendingRegions;
@synthesize pendingAuthorizations;
@synthesize isRequestingAuthorization;
@synthesize isQueueingEvents;
@synthesize queuedRegionEvents;

RCT_EXPORT_MODULE()

- (void) dealloc {
    locationManager.delegate = nil;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[INVRegionMonitorDidChangeRegionEvent];
}

- (NSDictionary *)constantsToExport
{
    return @{
        @"regionMonitorDidChangeRegion": INVRegionMonitorDidChangeRegionEvent,
        @"regionMonitorInitialTrigger": @{
                @"dwell": INVRegionMonitorInitialTriggerDwell,
                @"enter": INVRegionMonitorInitialTriggerEnter,
                @"exit": INVRegionMonitorInitialTriggerExit
        }
    };
}

- (instancetype) init {
    self = [super init];

    if (self) {
        locationManager = [[CLLocationManager alloc] init];
        locationManager.delegate = self;

        isQueueingEvents = YES;
        queuedRegionEvents = [[NSMutableArray alloc] init];

        pendingRegions = [[NSMutableDictionary alloc] init];
        pendingAuthorizations = [[NSMutableArray alloc] init];
        isRequestingAuthorization = NO;
        
        self.initialExitRegionIdentifiers = [NSMutableArray new];
        self.initialEntryRegionIdentifiers = [NSMutableArray new];
        self.initialStatusRegionIdentifiers = [NSMutableArray new];
    }

    return self;
}

- (void)_sendQueuedRegionEvents {
    for (NSDictionary *body in queuedRegionEvents) {
        [self sendEventWithName:INVRegionMonitorDidChangeRegionEvent body:body];
    }

    [queuedRegionEvents removeAllObjects];
}

- (void)startObserving {
    if (isQueueingEvents) {
        isQueueingEvents = NO;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
            [self _sendQueuedRegionEvents];
        });
    }
}

- (void)_failAuthorizationWithError:(NSError *)error {
    for (NSDictionary *pendingAuthorization in pendingAuthorizations) {
        RCTPromiseRejectBlock reject = pendingAuthorization[@"reject"];
        reject(@"authorization_failed", @"Requesting region monitoring authorization failed.", error);
    }

    [pendingAuthorizations removeAllObjects];

    for (NSString *identifier in pendingRegions.keyEnumerator) {
        NSDictionary *pendingRegion = pendingRegions[identifier];
        RCTPromiseRejectBlock reject = pendingRegion[@"reject"];
        reject(@"monitoring_failed", @"Failed to start region monitoring.", error);
    }

    [pendingRegions removeAllObjects];
}

- (void)_requestAuthorization {
    NSString *plistKey = @"NSLocationAlwaysUsageDescription";
    NSString *alwaysUsageDescription = [NSBundle mainBundle].infoDictionary[plistKey];

    if (!alwaysUsageDescription) {
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:9 userInfo:@{
            @"status": @0,
            @"message": [NSString stringWithFormat:@"%@ not set.", plistKey],
        }];

        [self _failAuthorizationWithError:error];
    }
    else {
        [locationManager requestAlwaysAuthorization];
    }
}

- (void)_addCircularRegion:(NSDictionary *)center
                    radius:(CLLocationDistance)radius
                identifier:(NSString *)identifier
            initialTrigger:(NSString *)initialTrigger {
    CLLocationCoordinate2D coordinate;
    coordinate.latitude = [center[@"latitude"] doubleValue];
    coordinate.longitude = [center[@"longitude"] doubleValue];

    RCTLogInfo(@"_addCircularRegion:radius:identifier: %f %f %@", coordinate.latitude, coordinate.longitude, identifier);

    CLCircularRegion* region = [[CLCircularRegion alloc]
                                   initWithCenter:coordinate
                                   radius:MIN(locationManager.maximumRegionMonitoringDistance, radius)
                                   identifier:identifier];
    [locationManager startMonitoringForRegion:region];
    
    if (initialTrigger == nil) {
        return;
    }
    
    if ([initialTrigger isEqualToString:INVRegionMonitorInitialTriggerEnter] || [initialTrigger isEqualToString:INVRegionMonitorInitialTriggerDwell]) {
        
        [self.initialStatusRegionIdentifiers addObject:identifier];
        [self.initialEntryRegionIdentifiers addObject:identifier];
        
    } else if ([initialTrigger isEqualToString:INVRegionMonitorInitialTriggerExit]) {
        
        [self.initialStatusRegionIdentifiers addObject:identifier];
        [self.initialExitRegionIdentifiers addObject:identifier];
    }
}

- (BOOL)_isRegionMonitoringPossible:(CLAuthorizationStatus)status {
    return (
        [CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]] &&
        (
            status == kCLAuthorizationStatusAuthorized ||
            status == kCLAuthorizationStatusAuthorizedAlways ||
            status == kCLAuthorizationStatusNotDetermined
        )
    );
}

- (void)_sendRegionChangeEventWithIdentifier:(NSString *)identifier didEnter:(BOOL)didEnter didExit:(BOOL)didExit {
    NSDictionary *body = @{
        @"region": @{
            @"identifier": identifier,
        },
        @"didEnter": @(didEnter),
        @"didExit": @(didExit),
    };

    if (isQueueingEvents) {
        [queuedRegionEvents addObject:body];

        // TODO: Check the count of the queuedRegionEvents as it shouldn't grow too big.
    }
    else {
        [self sendEventWithName:INVRegionMonitorDidChangeRegionEvent body:body];
    }
}

- (CLCircularRegion *)_getMonitoredRegionWithIdentifier:(NSString *)identifier {
    NSSet *regions = [locationManager.monitoredRegions objectsPassingTest:^BOOL(CLCircularRegion *region, BOOL *stop) {
        return ([region.identifier isEqualToString:identifier]);
    }];
    return [regions anyObject];
}

RCT_EXPORT_METHOD(addCircularRegion:(nonnull NSDictionary *)center
                             radius:(CLLocationDistance)radius
                         identifier:(nonnull NSString *)identifier
                    initialTrigger:(nullable NSString *)initialTrigger
                          resolver:(RCTPromiseResolveBlock)resolve
                          rejecter:(RCTPromiseRejectBlock)reject) {
    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (![self _isRegionMonitoringPossible:status]) {
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:6 userInfo:nil];
        reject(@"monitoring_unavailable", @"Region monitoring unavailable, restricted or denied by the user.", error);
        return;
    }

    if (pendingRegions[identifier]) {
        // There is a pending region so we immediately fail adding this region.
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:1 userInfo:nil];
        reject(@"pending_region", @"Adding region failed because of a pending region with the same identifier.", error);
        return;
    }

    CLCircularRegion *existingRegion = [self _getMonitoredRegionWithIdentifier:identifier];
    if (existingRegion != nil) {
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:8 userInfo:nil];
        reject(@"region_already_exists", @"Adding region failed because a region with the same idenitifier already exists.", error);
        return;
    }
    
    NSMutableDictionary *region = [[NSMutableDictionary alloc] initWithDictionary:@{
        @"center": center,
        @"radius": @(radius),
        @"resolve": resolve,
        @"reject": reject,
    }];
    
    if (initialTrigger) {
        region[@"initialTrigger"] = initialTrigger;
    }

    pendingRegions[identifier] = initialTrigger;

    RCTLogInfo(@"Checking status %d", status);

    if (status == kCLAuthorizationStatusNotDetermined) {
        RCTLogInfo(@"isRequestingAuthorization %d", isRequestingAuthorization);

        if (!isRequestingAuthorization) {
            isRequestingAuthorization = YES;

            RCTLogInfo(@"requestAlwaysAuthorization %d", status);

            [self _requestAuthorization];
        }

        return;
    }

    [self _addCircularRegion:center radius:radius identifier:identifier initialTrigger:initialTrigger];
}

RCT_EXPORT_METHOD(clearRegions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    [locationManager.monitoredRegions enumerateObjectsUsingBlock:^(__kindof CLRegion * _Nonnull region, BOOL * _Nonnull stop) {
        RCTLogInfo(@"Stop monitoring region %@", region.identifier);
        [locationManager stopMonitoringForRegion:region];
    }];

    resolve(nil);
}

RCT_EXPORT_METHOD(removeCircularRegion:(nonnull NSString *)identifier
                              resolver:(RCTPromiseResolveBlock)resolve
                              rejecter:(RCTPromiseRejectBlock)reject) {
    CLCircularRegion *region = [self _getMonitoredRegionWithIdentifier:identifier];

    if (region != nil) {
        RCTLogInfo(@"Stop monitoring region %@", region.identifier);

        [locationManager stopMonitoringForRegion:region];

        resolve(nil);
    }
    else {
        RCTLogInfo(@"Could not find region %@ in %@", region.identifier, locationManager.monitoredRegions);

        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:2 userInfo:nil];
        reject(@"remove_region", @"Removing region failed because the region does not exist.", error);
    }
}

RCT_EXPORT_METHOD(requestAuthorization:(RCTPromiseResolveBlock)resolve
                              rejecter:(RCTPromiseRejectBlock)reject) {
    if (isRequestingAuthorization) {
        // Requesting authorization is in progress.
        [pendingAuthorizations addObject:@{
            @"resolve": resolve,
            @"reject": reject,
        }];

        return;
    }

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if ([self _isRegionMonitoringPossible:status]) {
        if (status == kCLAuthorizationStatusNotDetermined) {
            RCTLogInfo(@"Status not determined, requesting authorization");

            isRequestingAuthorization = YES;

            [pendingAuthorizations addObject:@{
                @"resolve": resolve,
                @"reject": reject,
            }];

            [self _requestAuthorization];
        }
        else if (status == kCLAuthorizationStatusAuthorizedAlways ||
                 status == kCLAuthorizationStatusAuthorized) {
            // We are already authorized.
            resolve(nil);
        }
    }
    else {
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:6 userInfo:@{
            @"status": @(status),
        }];

        reject(@"request_authorization", @"Region monitoring unavailable, restricted or denied by the user.", error);
    }
}

- (void) locationManager:(CLLocationManager *)locationManager
       didDetermineState:(CLRegionState)state
               forRegion:(CLRegion *)region {
    RCTLogInfo(@"locationManager:didDetermineState:forRegion: %ld %@", (long)state, region.identifier);
    RCTLogInfo(@"Monitored regions %@", locationManager.monitoredRegions);

    if (state == CLRegionStateUnknown) {
        // TODO: Should we add some sort of delay here?

        [locationManager requestStateForRegion:region];
    }
    else {
        
        BOOL didEnter = NO;
        BOOL didExit = NO;

        if (state == CLRegionStateOutside) {
            didExit = true;
        }
        else if (state == CLRegionStateInside) {
            didEnter = true;
        }
        
        // If we're requesting the initial state for this region
        if ([self.initialStatusRegionIdentifiers containsObject:region.identifier]) {
            
            // Only send didEnter or didExit if we've requested them as initial notifications
            didEnter = didEnter && [self.initialEntryRegionIdentifiers containsObject: region.identifier];
            didExit = didExit && [self.initialExitRegionIdentifiers containsObject: region.identifier];
            
            [self.initialStatusRegionIdentifiers removeObject:region.identifier];
            [self.initialEntryRegionIdentifiers removeObject:region.identifier];
            [self.initialExitRegionIdentifiers removeObject:region.identifier];
        }

        if (didExit || didEnter) {
            [self _sendRegionChangeEventWithIdentifier:region.identifier didEnter:didEnter didExit:didExit];
        }
    }

}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    RCTLogInfo(@"Auth is %d", status);

    isRequestingAuthorization = NO;

    if (status == kCLAuthorizationStatusAuthorizedAlways ||
        status == kCLAuthorizationStatusAuthorized) {
        
        if (pendingRegions.count > 0) {
            
            for (NSString *identifier in pendingRegions.keyEnumerator) {
                
                NSDictionary *pendingRegion = pendingRegions[identifier];
                NSDictionary *center = pendingRegion[@"center"];
                NSNumber *radius = pendingRegion[@"radius"];
                NSString *initialTrigger = pendingRegion[@"initialTrigger"];

                [self _addCircularRegion:center radius:radius.doubleValue identifier:identifier initialTrigger:initialTrigger];
            }

            // We shouldn't remove the pending regions as they are resolved or rejected after they
            // are added.
        }

        if (pendingAuthorizations.count > 0) {
            for (NSDictionary *pendingAuthorization in pendingAuthorizations) {
                RCTPromiseResolveBlock resolve = pendingAuthorization[@"resolve"];
                resolve(nil);
            }

            [pendingAuthorizations removeAllObjects];
        }
    }
    else {
        NSError *error = [[NSError alloc] initWithDomain:INVRegionMonitorErrorDomain code:5 userInfo:@{
            @"status": @(status),
        }];

        [self _failAuthorizationWithError:error];
    }
}

- (void)locationManager:(CLLocationManager *)manager
monitoringDidFailForRegion:(CLRegion *)region
              withError:(NSError *)error {
    RCTLogInfo(@"monitoringDidFailForRegion:withError %@ %@!", region.identifier, error);

    // TODO: Check if we already have this region in the monitoredRegions?
    RCTLogInfo(@"%@", locationManager.monitoredRegions);

    NSString *identifier = region.identifier;
    NSDictionary *pendingRegion = pendingRegions[identifier];

    if (pendingRegion != nil) {
        RCTPromiseRejectBlock reject = pendingRegion[@"reject"];
        reject(@"monitoring_failed", @"Failed to start region monitoring.", error);

        [pendingRegions removeObjectForKey:identifier];
        
        [self.initialStatusRegionIdentifiers removeObject:identifier];
        [self.initialEntryRegionIdentifiers removeObject:identifier];
        [self.initialExitRegionIdentifiers removeObject:identifier];
    }
}

- (void)locationManager:(CLLocationManager *)manager
didStartMonitoringForRegion:(CLRegion *)region {
    RCTLogInfo(@"didStartMonitoringForRegion %@!", region.identifier);
    
    NSString *identifier = region.identifier;
    NSDictionary *pendingRegion = pendingRegions[identifier];

    if (pendingRegion != nil) {
        RCTPromiseResolveBlock resolve = pendingRegion[@"resolve"];
        resolve(nil);

        [pendingRegions removeObjectForKey:identifier];

        RCTLogInfo(@"Check the state of the region... %@", region);

        if ([self.initialStatusRegionIdentifiers containsObject:region.identifier]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                // We request the state so we can immediatelly emit an event if we're already inside this region.
                [locationManager requestStateForRegion:region];
            });
        }
    }
}

@end
