/** @file   ASDeviceController.mm
 *  @brief  Top-level controller for devices. There is a single instance of the controller. It manages
 *          all device plug/unplug events and device enumeration and access.
 *
 *
 *  Copyright (c) 2008-2013, tSoniq. http://tsoniq.com
 *
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
 *
 *  	*	Redistributions of source code must retain the above copyright notice, this list of
 *  	    conditions and the following disclaimer.
 *  	*	Redistributions in binary form must reproduce the above copyright notice, this list
 *  	    of conditions and the following disclaimer in the documentation and/or other materials
 *  	    provided with the distribution.
 *  	*	Neither the name of tSoniq nor the names of its contributors may be used to endorse
 *  	    or promote products derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
 *  ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 *  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "ASDeviceController.h"
#import "AQFileUtilities.h"
#import "ASPreferenceController.h"

using namespace ts;
static char deviceQueueKey;

@interface ASDeviceController (Worker)
- (void)deviceDetected;
- (void)deviceConnected:(ASDevice*)device;
- (void)deviceDisconnected:(ASDevice*)device;
- (void)publishDevice:(ASDeviceNode*)node notification:(NSString*)name;
@end

static bool deviceDetect(ASDeviceFactory* factory, void* context, unsigned ident)
{
    (void)factory; (void)ident;
    @autoreleasepool { [(ASDeviceController*)context deviceDetected]; }
    return true;
}
static void deviceConnect(ASDeviceFactory* factory, void* context, unsigned ident, ASDevice* device)
{
    (void)factory; (void)ident;
    @autoreleasepool { [(ASDeviceController*)context deviceConnected:device]; }
}
static void deviceDisconnect(ASDeviceFactory* factory, void* context, unsigned ident, ASDevice* device)
{
    (void)factory; (void)ident;
    @autoreleasepool { [(ASDeviceController*)context deviceDisconnected:device]; }
}

// A recovery copy must finish before the destructive task starts.
static NSString* ASCreateRecoveryCopy(ASNode* node, NSString* root, NSInteger days, NSString** message)
{
    if ([node isKindOfClass:[ASFileNode class]] || [node isKindOfClass:[ASAppletNode class]]) [node reload];
    if ([node isKindOfClass:[ASAppletNode class]])
    {
        ASAppletNode* appletNode = (ASAppletNode*)node;
        unsigned count = 0, ram = 0;
        if (![appletNode device]->getAppletResourceUsage(&count, &ram, [appletNode applet]) ||
            count != [appletNode numberOfChildren])
        {
            *message = @"The Neo’s complete file list could not be read for the recovery copy. No files on the Neo have been changed. Check the connection and try again.";
            return nil;
        }
    }
    NSFileManager* manager = [NSFileManager defaultManager];
    NSError* error = nil;
    if (![root isAbsolutePath] || ![manager createDirectoryAtPath:root withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions: @0700} error:&error])
    {
        *message = @"The recovery folder could not be created. No files on the Neo have been changed. Check your backup folder in Preferences.";
        return nil;
    }
    NSDate* now = [NSDate date];
    NSDateFormatter* formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setCalendar:[[[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian] autorelease]];
    [formatter setDateFormat:@"yyyy-MM-dd HH.mm.ss"];
    NSString* name = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:now], [[[NSUUID UUID] UUIDString] substringToIndex:8]];
    NSString* final = [root stringByAppendingPathComponent:name];
    NSString* pending = [final stringByAppendingString:@" (Incomplete)"];
    if (!aq_CreatePrivateDirectory(pending, &error) || ![node saveUnderPath:pending])
    {
        *message = @"The recovery copy could not be saved. No files on the Neo have been changed. Check your backup folder and free disk space, then try again.";
        return nil;
    }
    NSDictionary* information = @{@"formatVersion": @1, @"kind": @"AlphaSyncRecoveryCopy", @"createdAt": now,
                                   @"sourceName": ([node displayName] ? [node displayName] : @"")};
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:information format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data || !aq_WriteUniqueFile(pending, @".recovery-information", @"plist", data, &error) ||
        !aq_RenameItemExclusively(pending, final, &error))
    {
        *message = @"The recovery copy could not be finished. No files on the Neo have been changed. Check your backup folder and try again.";
        return nil;
    }
    if (days > 0)
    {
        NSArray* names = [manager contentsOfDirectoryAtPath:root error:&error];
        for (NSString* entry in names)
        {
            NSString* path = [root stringByAppendingPathComponent:entry];
            NSDictionary* attributes = [manager attributesOfItemAtPath:path error:nil];
            if (![attributes[NSFileType] isEqual:NSFileTypeDirectory] || [entry hasSuffix:@" (Incomplete)"]) continue;
            NSData* metadata = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@".recovery-information.plist"]];
            NSDictionary* record = metadata ? [NSPropertyListSerialization propertyListWithData:metadata options:0 format:NULL error:NULL] : nil;
            if (![record isKindOfClass:[NSDictionary class]] || ![record[@"kind"] isEqual:@"AlphaSyncRecoveryCopy"] ||
                ![record[@"formatVersion"] isEqual:@1] ||
                ![record[@"createdAt"] isKindOfClass:[NSDate class]]) continue;
            if ([now timeIntervalSinceDate:record[@"createdAt"]] <= days * 86400.0) continue;
            if (![manager trashItemAtURL:[NSURL fileURLWithPath:path] resultingItemURL:NULL error:&error]) break;
        }
        if (error)
        {
            *message = [NSString stringWithFormat:@"A recovery copy was saved at %@, but older copies could not be moved to Trash: %@. No files on the Neo have been changed.", final, [error localizedDescription]];
            return nil;
        }
    }
    return final;
}

@interface ASDeviceController ()
- (void)queueTaskForNode:(ASNode*)node refresh:(BOOL)refresh protected:(BOOL)protect
                   task:(id (^)(ASNode*))task completion:(void (^)(id, NSString*))completion;
@end

@implementation ASDeviceController
- (id)init
{
    if ((self = [super init]))
    {
        shuttingDown = false;
        notificationCenter = [NSNotificationCenter defaultCenter];
        rootNode = [[ASNode alloc] init];
        workerNodes = [[NSMutableDictionary alloc] init];
        dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_autorelease_frequency(
            DISPATCH_QUEUE_SERIAL, DISPATCH_AUTORELEASE_FREQUENCY_WORK_ITEM);
        deviceQueue = dispatch_queue_create("com.tsoniq.AlphaSync.devices", attributes);
        dispatch_queue_set_specific(deviceQueue, &deviceQueueKey, self, NULL);
        deviceFactory = new ASDeviceFactory((dispatch_queue_s*)deviceQueue);
    }
    return self;
}

- (void)dealloc
{
    // Normal shutdown drains this queue first.  Keep teardown on that queue even
    // for callers that release a controller without enabling any devices.
    shuttingDown = true;
    ASDeviceFactory* factory = deviceFactory;
    if (dispatch_get_specific(&deviceQueueKey) == self) delete factory;
    else dispatch_sync(deviceQueue, ^{ delete factory; });
    dispatch_release(deviceQueue);
    [workerNodes release];
    [rootNode release];
    [super dealloc];
}

- (BOOL)enable
{
    if (shuttingDown) return NO;
    dispatch_async(deviceQueue, ^{
        if (!deviceFactory->enable(self, deviceDetect, deviceConnect, deviceDisconnect))
            dispatch_async(dispatch_get_main_queue(), ^{
                [notificationCenter postNotificationName:kASDeviceControllerError object:@"Unable to enable USB device detection."];
            });
    });
    return YES;
}

- (void)disable
{
    dispatch_async(deviceQueue, ^{ deviceFactory->disable(); });
}

- (ASNode*)systemRoot { return rootNode; }
- (BOOL)isBusy { return pendingTaskCount != 0 || shuttingDown; }

- (void)deviceDetected
{
    if (shuttingDown) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!shuttingDown) [notificationCenter postNotificationName:kASDeviceControllerDeviceDetected object:nil];
    });
}

- (void)publishDevice:(ASDeviceNode*)node notification:(NSString*)name
{
    if (shuttingDown) return;
    ASDeviceNode* snapshot = (ASDeviceNode*)[[node copyForDisplay] autorelease];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shuttingDown) return;
        for (ASDeviceNode* previous in [[[rootNode children] copy] autorelease])
            if ([previous connectionID] == [snapshot connectionID]) [rootNode removeChild:previous];
        [rootNode addChild:snapshot];
        [notificationCenter postNotificationName:name object:snapshot];
    });
}

- (void)deviceConnected:(ASDevice*)device
{
    if (shuttingDown) return;
    ASDeviceNode* node = [[[ASDeviceNode alloc] initWithDevice:device] autorelease];
    [node setConnectionID:++nextConnectionID];
    workerNodes[@([node connectionID])] = node;
    [self publishDevice:node notification:kASDeviceControllerDeviceConnected];
}

- (void)deviceDisconnected:(ASDevice*)device
{
    NSNumber* identity = nil;
    for (NSNumber* key in workerNodes)
        if ([(ASDeviceNode*)workerNodes[key] device] == device) { identity = key; break; }
    if (!identity) return;
    // A new connection gets a new identity even if a USB object reuses an old address.
    // Queued work for the old connection therefore cannot reach the new device.
    [[identity retain] autorelease];
    [workerNodes removeObjectForKey:identity];
    if (shuttingDown) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        for (ASDeviceNode* node in [[[rootNode children] copy] autorelease])
            if ([node connectionID] == [identity unsignedIntegerValue])
            {
                [rootNode removeChild:node];
                [notificationCenter postNotificationName:kASDeviceControllerDeviceDisconnected object:node];
            }
    });
}

- (void)performTaskForNode:(ASNode*)node refresh:(BOOL)refresh task:(id (^)(ASNode*))task
               completion:(void (^)(id result, NSString* error))completion
{
    [self queueTaskForNode:node refresh:refresh protected:NO task:task completion:completion];
}

- (void)performProtectedTaskForNode:(ASNode*)node refresh:(BOOL)refresh task:(id (^)(ASNode*))task
                       completion:(void (^)(id result, NSString* error))completion
{
    [self queueTaskForNode:node refresh:refresh protected:YES task:task completion:completion];
}

- (void)queueTaskForNode:(ASNode*)node refresh:(BOOL)refresh protected:(BOOL)protect
                   task:(id (^)(ASNode*))task completion:(void (^)(id, NSString*))completion
{
    NSAssert([NSThread isMainThread], @"Schedule device work from the main thread.");
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    BOOL saveOriginal = protect && [defaults boolForKey:@"SaveRecoveryCopies"];
    NSString* recoveryRoot = [[defaults stringForKey:@"BackupFolder"] stringByAppendingPathComponent:@"Recovery Copies"];
    NSInteger retention = [defaults integerForKey:@"RecoveryRetentionDays"];
    if (retention != 0 && retention != 7 && retention != 30 && retention != 90) retention = 30;
    ASDeviceNode* owner = [node isKindOfClass:[ASDeviceNode class]] ? (ASDeviceNode*)node : [node ancestorOfClass:[ASDeviceNode class]];
    ASAppletNode* applet = [node isKindOfClass:[ASAppletNode class]] ? (ASAppletNode*)node : [node ancestorOfClass:[ASAppletNode class]];
    NSNumber* identity = @([owner connectionID]);
    NSInteger appletIndex = applet ? [applet appletIndex] : -1;
    NSInteger fileIndex = [node isKindOfClass:[ASFileNode class]] ? [(ASFileNode*)node fileIndex] : -1;
    NSString* selectedName = [node displayName];
    if (shuttingDown || !owner)
    {
        if (completion) completion(nil, @"The Neo is no longer available.");
        return;
    }
    ++pendingTaskCount;
    [notificationCenter postNotificationName:kASDeviceControllerTaskChanged object:self];
    dispatch_async(deviceQueue, ^{
        ASDeviceNode* live = workerNodes[identity];
        ASNode* selected = live;
        if (appletIndex >= 0)
        {
            selected = nil;
            for (ASAppletNode* child in [live children])
                if ([child appletIndex] == appletIndex) { selected = child; break; }
        }
        if (fileIndex >= 0)
        {
            ASNode* found = nil;
            for (ASFileNode* child in [selected children])
                if ([child fileIndex] == fileIndex && [[child displayName] isEqualToString:selectedName]) { found = child; break; }
            selected = found;
        }
        id result = nil;
        NSString* error = nil;
        if (!selected) error = @"The selected file or Neo is no longer available. Select it again and retry.";
        else
        {
            [selected setOperationError:nil];
            NSString* recovery = saveOriginal ? ASCreateRecoveryCopy(selected, recoveryRoot, retention, &error) : nil;
            BOOL protectionFailed = saveOriginal && !recovery;
            if (!protectionFailed) result = task(selected);
            if (!error && (!result || ([result isKindOfClass:[NSNumber class]] && ![result boolValue])))
            {
                error = [selected operationError];
                if (!error) error = @"The device operation could not be completed.";
            }
            if (error && recovery) error = [error stringByAppendingFormat:@"\n\nRecovery copy: %@", recovery];
            if (refresh && !protectionFailed)
            {
                [live reload];
                [self publishDevice:live notification:kASDeviceControllerDataChanged];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            --pendingTaskCount;
            [notificationCenter postNotificationName:kASDeviceControllerTaskChanged object:self];
            if (completion) completion(result, error);
        });
    });
}

- (void)reloadAllDevices
{
    for (ASDeviceNode* node in [[[rootNode children] copy] autorelease])
        [self performTaskForNode:node refresh:YES task:^id(ASNode* working) {
            (void)working; return @YES;
        } completion:nil];
}

- (void)closeDevice:(ASDeviceNode*)node
{
    [self performTaskForNode:node refresh:NO task:^id(ASNode* working) {
        return @([(ASDeviceNode*)working device]->restart());
    } completion:nil];
}

- (void)closeAllDevices
{
    for (ASDeviceNode* node in [[[rootNode children] copy] autorelease]) [self closeDevice:node];
}

- (void)shutdownWithCompletion:(void (^)(void))completion
{
    shuttingDown = YES;
    dispatch_async(deviceQueue, ^{
        for (ASDeviceNode* node in [workerNodes allValues]) [node device]->restart();
        deviceFactory->disable();
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(); });
    });
}
@end
