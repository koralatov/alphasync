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
    NSAssert([NSThread isMainThread], @"Schedule device work from the main thread.");
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
        if (!selected) error = @"The selected file or Neo is no longer available.  Select it again and retry.";
        else
        {
            [selected setOperationError:nil];
            result = task(selected);
            if (!result || ([result isKindOfClass:[NSNumber class]] && ![result boolValue]))
            {
                error = [selected operationError];
                if (!error) error = @"The device operation could not be completed.";
            }
            if (refresh)
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
